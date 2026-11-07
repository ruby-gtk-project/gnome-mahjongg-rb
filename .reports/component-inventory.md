# Component inventory — gnome-mahjongg-rb

Surveyed against `origin/main` (Vala/GtkBuilder upstream) on 2026-11-07.
Scope: full app (small codebase — 9 source files, 6 UI files). This is an
opening survey, not a parity audit; `component-parity` should follow up on any
item below marked "verify" before it is trusted as done.

## Headline

The `ruby` branch already has a `lib/mahjongg/*.rb` file for every upstream
unit, totalling ~3,380 lines against upstream's ~3,100 lines of Vala + ~900
lines of `.ui`/blueprint. No upstream source file is unmapped and no `lib/`
file is a stub. This inventory exists to name the mapping precisely and flag
what still needs a close read, not to report missing components.

## Mapping

| # | Upstream file(s) | Port file | Kind | Status |
|---|---|---|---|---|
| 1 | `src/gnome-mahjongg.vala` | `lib/mahjongg/application.rb` | Application (actions, accelerators, About, game lifecycle) | **exists** (419 lines) |
| 2 | `src/window.vala` + `data/ui/window.ui` | `lib/mahjongg/window.rb` | Main window (`Adw.ApplicationWindow`) | **exists** (337 lines) |
| 3 | `src/game.vala` | `lib/mahjongg/game.rb` | Game model (`Tile`, `Match`, `Game`) — no widgets | **exists** (676 lines) |
| 4 | `src/game-view.vala` | `lib/mahjongg/game_view.rb` | Board widget (`Gtk.Widget` subclass, custom `snapshot`) | **exists** (439 lines) |
| 5 | `src/map.vala` + `data/maps/mahjongg.map` | `lib/mahjongg/map.rb` | Layout/map model (`Slot`, `Map`, `Maps`) — no widgets | **exists** (229 lines) |
| 6 | `src/history.vala` | `lib/mahjongg/history.rb` | Score history store (`History`, `HistoryEntry`) — no widgets | **exists** (118 lines) |
| 7 | `src/game-save.vala` | `lib/mahjongg/game_save.rb` | In-progress-game save/restore (XML-ish) — no widgets | **exists** (147 lines) |
| 8 | `src/pause-overlay.vala` + `data/ui/pause-overlay.ui` | `lib/mahjongg/pause_overlay.rb` | Pause overlay (`Gtk.Box` osd overlay) | **exists** (116 lines) |
| 9 | `src/rules-dialog.vala` + `data/ui/rules-dialog.ui` | `lib/mahjongg/rules_dialog.rb` | Game Rules dialog (`Adw.PreferencesDialog`) | **exists** (87 lines) |
| 10 | `src/score-dialog.vala` + `data/ui/score-dialog.ui` | `lib/mahjongg/score_dialog.rb` | Scores dialog (`Adw.Dialog`, `Gtk.ColumnView`) | **exists** (449 lines) |
| 11 | `data/ui/menu.ui` (no backing source file) | `lib/mahjongg/menu.rb` | Primary menu model | **exists** (107 lines) |
| 12 | `data/ui/shortcuts-dialog.ui` (no backing source file) | `lib/mahjongg/shortcuts_dialog.rb` | Keyboard Shortcuts dialog (`Adw.ShortcutsDialog`) | **exists** (80 lines) |
| 13 | *(inline in `gnome-mahjongg.vala::about_cb`)* | `lib/mahjongg/about_dialog.rb` | About dialog (`Adw.AboutDialog`) | **exists** (85 lines) |
| 14 | `data/org.gnome.Mahjongg.gschema.xml.in` | *(consumed via GLib settings, no single `lib/` file — verify how `ruby` reads/writes GSettings)* | GSettings schema (4 keys + 2 enums) | **verify** — confirm a GSettings-backed store exists and is wired the same as upstream (`tileset`, `mapset`, `map-rotation`, `background-color`, `window-width/height`, `window-is-maximized`) |
| 15 | `po/*.po` catalogue | `lib/mahjongg/i18n.rb` + locale data under `data/` | Translation plumbing | **exists** — `i18n.rb` documents that upstream's exact msgids/msgctxt must be reused; **verify** the `.po` catalogue itself was carried over (see "Not yet inventoried" below) |
| 16 | *(cross-cutting: `Signals` pattern replaces GObject signals)* | `lib/mahjongg/signals.rb` | Internal plumbing (not a user-facing component, but the mechanism `Game`/`GameView`/`Window` use for `moved`, `paused_changed`, `tick`, `attempt_move`, `redraw_tile`) | **exists** (21 lines) |
| 17 | *(cross-cutting: data dir / locale dir resolution)* | `lib/mahjongg/paths.rb` | Internal plumbing | **exists** (32 lines) |
| 18 | *(gem version)* | `lib/mahjongg/version.rb` | Internal plumbing | **exists** (11 lines) |

## Per-unit detail (for `component-parity` to verify against)

### `lib/mahjongg/application.rb` — app actions, accelerators, lifecycle
Upstream installs 14 actions (`new-game`, `undo`, `redo`, `hint`, `pause`,
`restart-game`, `scores`, `layout` (stateful `s`), `layout-progression`
(stateful `s`), `background-color` (stateful `s`), `theme` (stateful `s`),
`rules`, `about`, `quit`) and 8 accelerator sets (`app.new-game`→`<Primary>n`,
`app.restart-game`→`<Primary>r`, `app.pause`→`Escape`/`Pause`/`<Primary>p`,
`app.hint`→`<Primary>h`, `app.undo`→`<Primary>z`, `app.redo`→`<Shift><Primary>z`,
`app.rules`→`F1`, `app.quit`→`<Primary>q`, plus `window.close`→`<Primary>w`).
It also owns two `Adw.AlertDialog` flows: "No Moves Left" (reshuffle / new
game / quit / continue) and "Change Layout?" (cancel / destructive change).
Verify all 14 actions, all 9 accelerator bindings, and both alert dialogs
(including their response IDs and `DESTRUCTIVE` appearance) are present.

### `lib/mahjongg/window.rb` — main window
Upstream template: `AdwToolbarView` > top `AdwHeaderBar` (undo/redo buttons
start, menu button + pause button + hint button end) + content `GtkOverlay`
wrapping a `GtkStack` (css class `game`, `tile-filter` when not using cairo)
holding two `GameView`s ("primary"/"secondary") for crossfade/slide
transitions. `AdwBreakpoint` sets `compact` below 380px height. CSS classes:
`devel` (when `APP_ID` ends `.Devel`), per-theme class on the toolbar view,
`dim-label` and overlay add/remove of the pause overlay while paused. Signals:
`notify::active` on menu button, `notify::visible-dialog`, `notify::suspended`
— all three pause the game. Verify the two `GameView` instances, the stack
transition logic (`SLIDE_LEFT` vs `CROSSFADE` vs `NONE`), and the three pause
triggers are all present.

### `lib/mahjongg/game_view.rb` — board widget
Custom `Gtk.Widget` with a `GestureClick` controller (single vs double-click:
double-click with no tile hit triggers `autoplay_end_game`), a custom
`snapshot` override drawing from either a `Gdk.Texture` (GL path) or a
`Cairo.Pattern` (cairo fallback, selected via `GSK_RENDERER=cairo`), tile-shake
animation via `add_tick_callback`. Verify both render paths and the shake
animation constants (250ms duration, 6Hz frequency, 3px min amplitude, 0.04
scale factor) are ported.

### `lib/mahjongg/pause_overlay.rb` — pause overlay
`GtkBox` (css: `osd`, `pause-overlay`, `toolbar`) containing a `GtkRevealer`
bound bidirectionally to its own `visible`, with a vertical box: "Paused"
title-1 label, then resume button (pill+suggested-action,
`app.pause`), restart button (pill, `app.restart-game`, visibility inverse-
bound to the quit button's visibility), quit button (pill+destructive-action,
`app.quit`). `show(resuming_game)` hides the quit button when resuming.
Verify the inverse-binding behavior (restart hidden exactly when quit is
hidden) and focus-grab on resume button.

### `lib/mahjongg/rules_dialog.rb` — Game Rules dialog
`Adw.PreferencesDialog`, content-width 600, one page/group with 7
`AdwActionRow`s, each with a prefix `GtkImage` (first one's icon-name set in
code to `"{APP_ID}-symbolic"`, not in the `.ui`). Verify all 7 rows' exact
title/subtitle text and icon names (`object-select-symbolic`,
`stopwatch-symbolic`, `media-playback-pause-symbolic`, `edit-undo-symbolic`,
`dialog-information-symbolic`, `media-playlist-shuffle-symbolic`).

### `lib/mahjongg/score_dialog.rb` — Scores dialog
`Adw.Dialog` 360×500, `AdwToolbarView` with header `GtkStack` (layout dropdown
vs. "Game Completed 🎉" title), clear-scores button (start, hidden when
showing a completed-game result), content `GtkStack` ("no-scores" ->
`AdwStatusPage`, "scores" -> `GtkColumnView` in a `GtkScrolledWindow` with 3
columns: rank/time/player), bottom bar with New Game (pill+suggested) and
Quit (`AdwButtonContent`) buttons in a `GtkCenterBox`. Behavior to verify:
rank/time/player column factories and multi-sorters (rank→date→player,
player→rank→date), the editable player-name `GtkEntry` swapped in via a
per-row `GtkStack` only for the just-completed entry, clear-scores
confirmation `Adw.AlertDialog`, and scroll-to-rank/focus-grab on dialog open
when a `completed_entry` is present.

### `lib/mahjongg/menu.rb` — primary menu
3 top sections: (new-game/restart-game/scores), (layout submenu — built
dynamically from the map catalogue, not static like upstream's placeholder
10 items — / layout-progression submenu — 3 static radio items / appearance
submenu — background 3 items + theme 3 items), (rules/shortcuts/about).
Verify the layout submenu is populated from the same map set and in the same
order upstream's runtime `layout_menu.append_item` loop produces (upstream's
`.ui` ships 10 placeholder labels that get wiped and rebuilt at runtime —
do not compare the port against the static `.ui` text, compare against the
runtime-built menu).

### `lib/mahjongg/shortcuts_dialog.rb` — Keyboard Shortcuts dialog
`Adw.ShortcutsDialog`, 2 sections: "Game" (6 items: new-game, restart-game,
pause, undo, redo, hint — all action-bound) and "General" (5 items: rules
(action-bound), "Show Main Menu" (hardcoded `F10`, no action — GTK's built-in
accel), shortcuts (action-bound), window.close, quit). Verify the F10 item is
reproduced as a literal accelerator, not an action binding (there is no
`app.`/`win.` action backing it upstream either).

### `lib/mahjongg/about_dialog.rb` — About dialog
16 developers, 8 artists, 3 documenters, a "Layouts by" credit section (3
names: Rexford Newbould, Krzysztof Foltman, Sapphire Becker), two-line
copyright string, `translator-credits`. Verify every name list matches
upstream exactly (order and spelling) — this is pure data and easy to drift on
edits to either side.

### `lib/mahjongg/game.rb`, `lib/mahjongg/map.rb`, `lib/mahjongg/history.rb`, `lib/mahjongg/game_save.rb`
Model classes, no widgets — in scope for `test-parity` (game generation,
solvability search, undo/redo, hint cycling, shuffle, save/restore XML format,
history line format) rather than `component-parity`. Flagged here only so
they aren't mistaken for missing components; they are fully present as
`lib/` files.

## Not yet inventoried in this pass (flag for follow-up)

- **GSettings schema** (`data/org.gnome.Mahjongg.gschema.xml.in`): 2 enums
  (`BackgroundColor`, `MapRotation`) and 7 keys. Did not find this pass's scope
  checking whether `ruby`'s `data/` carries a compiled/compilable copy of this
  schema or whether settings are persisted another way. **Action:** read
  `lib/mahjongg/application.rb`'s settings access and `data/` for a schema
  file before the next pass claims parity on persisted preferences.
- **`po/` catalogue**: upstream ships ~100 `.po` files. Confirm the `ruby`
  branch's `data/locale` (or equivalent) was generated from the same
  catalogue and that `rake locale` (mentioned in `paths.rb`'s comment) is
  wired up, rather than comparing msgid text by hand again here.
- **`data/org.gnome.Mahjongg.metainfo.xml.in.in`**: upstream's About dialog
  used to load from this via `from_appdata`; the port hand-codes the same
  fields (per `about_dialog.rb`'s own comment). Worth a line-by-line diff
  against the metainfo file's `<description>`/`<releases>` if those are
  surfaced anywhere in the port (they did not appear to be, which matches
  upstream only using metainfo for the About dialog's copyright/credits, not
  changelog display).
- **CSS** (`data/css/style.css`): not read this pass. Upstream's `.ui`/code
  apply `game`, `tile-filter`, `compact`, `devel`, `osd`, `pause-overlay`,
  `toolbar`, `pill`, `suggested-action`, `destructive-action`, `dim-label`,
  per-theme classes (`postmodern`/`smooth`/`educational`), `numeric`,
  `caption`, `heading`. Confirm `data/css/style.css` (or an equivalent) ships
  in the port and defines the classes the `.ui`-only side (theme borders,
  `pause-overlay`, `game`) depends on.
- Actual widget-tree fidelity (every `Gtk.Button`/`Adw.ActionRow`/etc. with its
  exact CSS classes and signal connections, per file) was read from source on
  both sides for this survey but not diffed row-by-row — that is
  `component-parity`'s job, using this file list as its starting map.

## Totals

- Upstream: 9 `.vala` files (~3,100 lines) + 6 `.ui` files (~900 lines) + 1
  gschema + metainfo + ~100 `.po` files.
- `ruby` branch: 17 `lib/mahjongg/*.rb` files + `lib/mahjongg.rb` (~3,400
  lines total), one file per upstream unit, no stubs.
- Components with no backing upstream source file (`menu.ui`,
  `shortcuts-dialog.ui`, and the inline About dialog in
  `gnome-mahjongg.vala::about_cb`) each still have their own `lib/` file
  (`menu.rb`, `shortcuts_dialog.rb`, `about_dialog.rb`) — correctly scoped as
  their own units per the `component-identification` skill's rule for
  standalone `.ui` objects and inline-built dialogs.
