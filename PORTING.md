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

**Translations come from upstream's own catalogues.** All 93 `po/*.po` files
are reused unchanged, which means every string in this port has to match its
msgid exactly — including the `msgctxt` disambiguators, so `p_('background
color', 'Light')` and `p_('mahjongg map name', 'Turtle')` are spelled the way
the catalogues expect. `rake locale` compiles them with the gettext gem's
`rmsgfmt`; `rake metadata` merges the same catalogues into the desktop entry
and the AppStream metainfo with GNU `msgfmt --desktop` / `--xml`, which is why
those two files are generated from `.in` templates rather than tracked.

The text domain binds with `output_charset: 'UTF-8'`, because GTK and Pango
want UTF-8 whatever the locale's charset is; without it every umlaut in a
German run arrives as `?`.

**The command line is GApplication's.** `--version` is registered with
`add_main_option` and answered in `handle-local-options`, as upstream does, so
it turns up in `--help` translated rather than being pulled out of `ARGV`
by hand.

## Verifying it

`rake test` runs two scripts:

- `test/logic_test.rb` — 59 checks with no widgets: layout parsing, board
  generation and reproducibility, matching, undo/redo, hints, the save-file
  round trip, the score file, and the translations (that all 93 catalogues
  compile, that a German run really does say "Pausiert", and that `--version`
  and `--help` answer as they should).
- `test/ui_test.rb` — 80 checks driving the real window offscreen: selecting
  and matching tiles by clicking their centres, shaking a blocked tile,
  undo/redo, the hint penalty, pausing and resuming, all three tile sets, the
  dark background, changing layout (both answers to the confirmation), every
  dialog, the no-moves-left state, and playing a board out to a win and a
  recorded score. It writes screenshots to `tmp/shots`. It pins the locale to
  C so its assertions can compare against the English originals;
  `MAHJONGG_RB_TEST_LANGUAGE=de rake test` runs it translated, for looking at
  rather than asserting on.
