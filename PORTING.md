# Porting GNOME Mahjongg from Vala to Ruby

Upstream is ~2,900 lines of Vala plus six `.ui` files and a GResource bundle.
This is what each piece became, and where the port deliberately differs.

## File map

| Upstream | Here |
|---|---|
| `src/gnome-mahjongg.vala` | `lib/mahjongg/application.rb` |
| `src/window.vala` + `data/ui/window.ui` | `lib/mahjongg/window.rb` |
| `src/game.vala` | `lib/mahjongg/game.rb` |
| `src/game-view.vala` | `lib/mahjongg/game_view.rb` |
| `src/map.vala` | `lib/mahjongg/map.rb` |
| `src/game-save.vala` | `lib/mahjongg/game_save.rb` |
| `src/history.vala` | `lib/mahjongg/history.rb` |
| `src/score-dialog.vala` + `.ui` | `lib/mahjongg/score_dialog.rb` |
| `src/rules-dialog.vala` + `.ui` | `lib/mahjongg/rules_dialog.rb` |
| `src/pause-overlay.vala` + `.ui` | `lib/mahjongg/pause_overlay.rb` |
| `data/ui/menu.ui` | `lib/mahjongg/menu.rb` |
| `data/ui/shortcuts-dialog.ui` | `lib/mahjongg/shortcuts_dialog.rb` |
| `Adw.AboutDialog.from_appdata` | `lib/mahjongg/about_dialog.rb` |

The `.ui` files have no Ruby equivalent worth having: `Gtk::Builder` templates
need a GType per template class, and the house style already describes widget
trees declaratively. Every template became a class of memoized widget methods
with the same structure, so the two read side by side.

## Where the port differs, and why

**No GResource.** A Vala binary compiles its data in; a Ruby script cannot.
Layouts, tile sets, CSS and icons stay on disk under `data/`, found through
`Mahjongg::Paths`, which honours `MAHJONGG_RB_DATA_DIR` so the installed
wrapper can point at the store path.

Two knock-on changes:

- `themes/smooth.svg` and `themes/educational.svg` are one-line SVG wrappers
  around a PNG, and referred to it as `resource:///org/gnome/Mahjongg/themes/…`.
  Those two `href`s now name the PNG beside them. Nothing else in the tile
  sets changed. (Missing this renders a perfectly valid, perfectly empty
  board, which is why `test/ui_test.rb` asserts the sheet is not blank.)
- The shipped action icons go on the icon-theme search path instead of the
  application's resource path. This is a fallback either way — a desktop icon
  theme carrying `stopwatch-symbolic` supplies its own, exactly as it would
  upstream.

**The board is a `Gtk::DrawingArea`, not a `Gtk.Widget` subclass.** Upstream
overrides `snapshot` and pushes the tile sheet through a Gsk texture node,
falling back to Cairo under `GSK_RENDERER=cairo`. Registering a Ruby GType
just to override `snapshot` buys nothing here, so the port is the Cairo path
only: render the sheet into a `Cairo::ImageSurface` at the size the tiles need
and blit one cell per tile. The sizing arithmetic — layer offsets of
`tile_width / 7` and `tile_height / 10`, the 43×2 sheet, the scale-down/scale-up
steps in `theme_size` — is upstream's, unchanged, because the tile artwork is
drawn to those ratios.

**Plain callbacks instead of GObject signals.** `Game` emits `:moved`,
`:paused_changed`, `:tick`, `:redraw_tile` and `:attempt_move` through the
three-method `Mahjongg::Signals` module. Registering GTypes to get multicast
callbacks would be pure ceremony.

`HistoryEntry` *is* a `GLib::Object`, because the score dialog puts entries
straight into a `Gio::ListStore`, which takes nothing else.

**`Game` is not `Enumerable`.** `Game#map` is the layout. Including Enumerable
would shadow it with `Enumerable#map`, so iteration goes through `game.tiles`.

**`Random` instead of `GLib.Rand`.** Both are Mersenne Twister but they are
seeded differently, so a board generated from seed *n* here is not the board
Vala generates from seed *n*. Nothing depends on that: the save file stores
every tile's face, and the seed is only used so Restart reproduces the board
within one implementation.

**Rendering settles a frame late.** Upstream measures the board inside
`snapshot`, and so does this. The first frame is what tells the view how big
the tiles are, so the sheet cannot be rendered before it; `resize_theme`
queues a second frame once the sheet exists. `draw` therefore always measures
and re-renders, and only paints if there is something to paint.

## What is not ported

**Translations.** Upstream carries ~80 message catalogues. The strings here
are the English originals, untranslated, and there is no gettext wiring. That
is the one piece of upstream parity deliberately left out; everything else —
every window, dialog, menu item, shortcut, preference, action, empty state and
error state — is present.

## Verifying it

`rake test` runs two scripts:

- `test/logic_test.rb` — 51 checks with no widgets: layout parsing, board
  generation and reproducibility, matching, undo/redo, hints, the save-file
  round trip, the score file.
- `test/ui_test.rb` — 80 checks driving the real window offscreen: selecting
  and matching tiles by clicking their centres, shaking a blocked tile,
  undo/redo, the hint penalty, pausing and resuming, all three tile sets, the
  dark background, changing layout (both answers to the confirmation), every
  dialog, the no-moves-left state, and playing a board out to a win and a
  recorded score. It writes screenshots to `tmp/shots`.
