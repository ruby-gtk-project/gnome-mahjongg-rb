# gnome-mahjongg — upstream component inventory

Upstream ref: `origin/main` (Vala + GtkBuilder `.ui`). Port branch: `ruby`.
Method: `component-identification` skill — declarative UI read first
(`data/ui/*.ui` are the component map), then every `src/*.vala` that backs a
template, then the GSettings schema, the GResource manifest, `data/css/style.css`
and `po/POTFILES.in`.

Upstream has **six** declarative roots: five `<template>` (`PauseOverlay`,
`RulesDialog`, `ScoreDialog`, `MahjonggWindow`) plus `data/ui/menu.ui`
(a bare `<menu id="menu">`, no backing class) and `data/ui/shortcuts-dialog.ui`
(a top-level `<object class="AdwShortcutsDialog">`, also with no backing class).
`GameView` is built entirely in code — a `Gtk.Widget` subclass with a `snapshot`
override — so it produces no `.ui` rows.

## Verdict

**Every user-facing component upstream has is already present on `ruby`.**
The port is at full structural parity: 17 of 17 components exist, including the
three runtime `Adw.AlertDialog`s and the `no-scores` empty state, which are easy
to miss because they live inside method bodies rather than in a `.ui`.

One item of dead scaffolding remains (see Blockers).

## Components

| # | Upstream file(s) | Port file | Kind | Present |
|---:|---|---|---|---|
| 1 | `src/gnome-mahjongg.vala` | `lib/mahjongg/application.rb` | application (14 actions, 9 accel groups, `--version` option, GSettings, CSS provider) | yes |
| 2 | `data/ui/window.ui` + `src/window.vala` | `lib/mahjongg/window.rb` | window | yes |
| 3 | `data/ui/menu.ui` | `lib/mahjongg/menu.rb` | primary menu model | yes |
| 4 | `data/ui/pause-overlay.ui` + `src/pause-overlay.vala` | `lib/mahjongg/pause_overlay.rb` | overlay | yes |
| 5 | `data/ui/rules-dialog.ui` + `src/rules-dialog.vala` | `lib/mahjongg/rules_dialog.rb` | preferences-style dialog | yes |
| 6 | `data/ui/score-dialog.ui` + `src/score-dialog.vala` | `lib/mahjongg/score_dialog.rb` | dialog | yes |
| 7 | `data/ui/score-dialog.ui` (`no-scores` stack page) | `lib/mahjongg/score_dialog.rb` (`#no_scores_page`) | empty state | yes |
| 8 | `data/ui/shortcuts-dialog.ui` | `lib/mahjongg/shortcuts_dialog.rb` | shortcuts dialog | yes |
| 9 | `src/gnome-mahjongg.vala` (`about_cb`) | `lib/mahjongg/about_dialog.rb` | about dialog | yes |
| 10 | `src/gnome-mahjongg.vala` (`moved_cb`) | `lib/mahjongg/application.rb` (`#offer_way_out`) | alert dialog — "No Moves Left" | yes |
| 11 | `src/gnome-mahjongg.vala` (`_layout_cb`) | `lib/mahjongg/application.rb` (`#confirm_layout_change`) | alert dialog — "Change Layout?" | yes |
| 12 | `src/score-dialog.vala` (`clear_scores_cb`) | `lib/mahjongg/score_dialog.rb` (line ~416) | alert dialog — "Clear All Scores?" | yes |
| 13 | `src/game-view.vala` | `lib/mahjongg/game_view.rb` | custom drawing widget | yes |
| 14 | `src/game.vala` | `lib/mahjongg/game.rb` | model (+ `Timer`) | yes |
| 15 | `src/map.vala` | `lib/mahjongg/map.rb` | model (`Slot`, `Map`, `Maps`) | yes |
| 16 | `src/history.vala` | `lib/mahjongg/history.rb` | model (`HistoryEntry`, `History`) | yes |
| 17 | `src/game-save.vala` | `lib/mahjongg/game_save.rb` | model | yes |

Non-component upstream files, for completeness: `src/config.vapi` (build glue,
no port needed), `src/meson.build`, `tests/*` (covered by `test/logic_test.rb`,
`test/ui_test.rb`, `test/gtk_driver.rb`).

## Per-component detail

### `data/ui/window.ui` + `src/window.vala` — the game window
| Widget | × | CSS | Signals / actions | Port |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | `compact` (dynamic, via breakpoint), `devel` (when app id ends `.Devel`) | `notify::visible-dialog`, `notify::suspended` | yes |
| `Adw.Breakpoint` | 1 | — | `max-height: 380px` → `compact` | yes (`apply` + `unapply`) |
| `Adw.ToolbarView` | 1 | `postmodern` / `smooth` / `educational` (dynamic, one at a time) | — | yes |
| `Adw.HeaderBar` | 1 | — | — | yes |
| `Adw.WindowTitle` | 1 | `numeric` | title = clock, subtitle = "Moves Left: %2u" | yes |
| `Gtk.Button` | 4 | — | `app.undo`, `app.redo`, `app.pause`, `app.hint` | yes |
| `Gtk.MenuButton` | 1 | — | primary, `notify::active` → pause | yes |
| `Gtk.Overlay` | 1 | — | hosts `PauseOverlay` | yes |
| `Gtk.Stack` | 1 | `game`, `tile-filter` (unless `GSK_RENDERER=cairo`), `dim-label` (while paused) | two `GameView` children, `primary` / `secondary` | yes |

Note: the port's `devel` CSS class is not applicable — it ships a single app id
(`org.gnome.Mahjongg.Rb`) with no `.Devel` variant.

### `data/ui/menu.ui` — the primary menu
Three sections. Section 1: New Game / Restart Game / Scores. Section 2: three
submenus — `_Layout` (filled at runtime from the layout catalogue,
`app.layout` with a string target), `Layout _Progression` (3 radio items,
`app.layout-progression`), `_Appearance` (two labelled sections: Background, 3
radio items; Theme, 3 radio items). Section 3: Game Rules / Keyboard Shortcuts /
About. Port reproduces all of it, including the `msgctxt` disambiguators
(`mahjongg map name`, `layout progression`, `background color`,
`mahjongg theme name`).

### `data/ui/pause-overlay.ui` — the paused card
`Gtk.Box` (`osd`, `pause-overlay`, `toolbar`) → `Gtk.Revealer` (slide-up, 200ms)
→ `Gtk.Box` → title-1 label "Paused" + three pill buttons: Resume
(`pill suggested-action`, `app.pause`, grabs focus), Restart (`pill`,
`app.restart-game`, visible iff Quit is not), Quit (`pill destructive-action`,
`app.quit`). Port: present.

### `data/ui/rules-dialog.ui` — Game Rules
`Adw.PreferencesDialog` (content-width 600) → one `Adw.PreferencesPage` → one
`Adw.PreferencesGroup` → **7** `Adw.ActionRow`, each with a prefix `Gtk.Image`.
Row 1's image is the app icon (`APP_ID-symbolic`); the other six are
`object-select-symbolic`, `stopwatch-symbolic`, `media-playback-pause-symbolic`,
`edit-undo-symbolic`, `dialog-information-symbolic`,
`media-playlist-shuffle-symbolic`. Rows 4–7 carry subtitles. Port: present.

### `data/ui/score-dialog.ui` — Scores
`Adw.Dialog` 360×500 → `Adw.ToolbarView` → header (`Gtk.Stack` of
`Gtk.DropDown` / `Adw.WindowTitle` "Game Completed 🎉"; start button
`user-trash-symbolic` "Clear Scores…") → content (`Gtk.Stack` of
`Adw.StatusPage` "No Scores" / `Gtk.ScrolledWindow` + `Gtk.ColumnView` with
Rank / Time / Player columns) → bottom bar (`toolbar`) with a `Gtk.CenterBox`
holding a pill suggested New Game button and a Quit button with an
`Adw.ButtonContent`. Behaviour in `src/score-dialog.vala`: three
`Gtk.SignalListItemFactory` cell factories (`Gtk.Inscription` with `caption` /
`numeric` / `heading`; the player column is a `Gtk.Stack` of inscription and a
frameless `Gtk.Entry` for the just-finished row), `Gtk.MultiSorter` +
`Gtk.CustomSorter` per column, `Gtk.NoSelection` over a `Gtk.SortListModel`, and
a `Gtk.EventControllerFocus` that scrolls to the new entry. Port: all present.

### `data/ui/shortcuts-dialog.ui` — Keyboard Shortcuts
`Adw.ShortcutsDialog` → 2 `Adw.ShortcutsSection` (Game: 6 items; General: 5
items). All items but "Show Main Menu" (`F10`, spelled out) read their
accelerator off an action name. Port: present, same split.

### `src/game-view.vala` — the board
`Gtk.Widget` subclass, `snapshot` override, `Gtk.GestureClick` controller,
tile-shake tick callback, librsvg sprite-sheet rendering with a Cairo fallback.
Port: `lib/mahjongg/game_view.rb`, a `Gtk::DrawingArea` taking the Cairo path
(documented in the file's own header comment) — a deliberate, noted divergence,
not a gap.

## Non-widget assets

| Upstream | Port | Present |
|---|---|---|
| `data/org.gnome.Mahjongg.gschema.xml.in` (7 keys, 2 enums) | `data/schemas/org.gnome.Mahjongg.Rb.gschema.xml` | yes |
| `data/css/style.css` | `data/css/style.css` — byte-identical, loaded by `Application#build` via `Gtk::CssProvider#load_from_path` | yes |
| `data/org.gnome.Mahjongg.gresource.xml.in` | no GResource; `lib/mahjongg/paths.rb` reads the same files off disk | yes (by design) |
| `data/themes/*.svg`, `data/maps/mahjongg.map`, `data/icons/scalable/actions/*` | same paths under `data/` | yes |
| `po/` — 93 catalogues, `LINGUAS` identical | `po/` — 93 catalogues, `LINGUAS` identical | yes |

## Blockers

1. **Dead scaffolding: `lib/gnome_mahjongg/`.** `lib/gnome_mahjongg.rb` and
   `lib/gnome_mahjongg/application.rb` are the untouched generator stub — an
   `Adwaita::StatusPage` reading "The Ruby port has not been written yet." —
   and `exe/gnome-mahjongg` is its launcher. Nothing else in the tree requires
   them; the real app is `lib/mahjongg/**` behind `exe/gnome-mahjongg-rb`. Two
   entry points, one of which renders a placeholder, is the one thing in this
   repo that will read as an unfinished port. Delete both files and that `exe`,
   or make `exe/gnome-mahjongg` an alias of the real launcher.
2. **No upstream `.Devel` counterpart.** `src/window.vala` adds a `devel` CSS
   class when `APP_ID` ends in `.Devel`. The port ships one app id, so the class
   can never apply. Harmless, but it is a parity row that will never close and
   should be recorded as out of scope rather than chased.
