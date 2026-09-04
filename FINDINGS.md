# ruby-gnome defects and quirks found porting Mahjongg

Everything here was hit while porting gnome-mahjongg 49.1.1, against
ruby-gnome 4.3.9, GTK 4.22.4 and libadwaita 1.9.3 on Ruby 3.3.10.

## Adwaita::ShortcutsItem rejects the constructor its introspection advertises

`Adwaita::ShortcutsItem.new` reports two keyword signatures and accepts
neither:

```
Adwaita::ShortcutsItem#initialize(title: utf8, accelerator: utf8)
Adwaita::ShortcutsItem#initialize(title: utf8, action_name: utf8)

irb> Adwaita::ShortcutsItem.new(title: 'New Game', action_name: 'app.new-game')
ArgumentError: wrong arguments
```

Positional arguments work, but always resolve to the *first* overload, so the
second argument is stored as an accelerator whichever one you meant:

```ruby
Adwaita::ShortcutsItem.new('New Game', 'app.new-game').accelerator
# => "app.new-game"
```

**Workaround** (`lib/mahjongg/shortcuts_dialog.rb`): construct with an empty
accelerator and set the action afterwards.

```ruby
Adwaita::ShortcutsItem.new(title, '').tap { |item| item.action_name = action }
```

## Adwaita::AlertDialog has no `response`

`adw_alert_dialog_response()` is not bound, so a test cannot answer a dialog
the way a button does. `choose` is async and awkward to drive. Emitting the
signal is equivalent:

```ruby
dialog.signal_emit('response', 'change_layout')
dialog.close
```

## Adwaita::AboutDialog has no `from_appdata`

`adw_about_dialog_new_from_appdata()` is not bound — `Adwaita::AboutDialog`
has no singleton methods at all. The properties it would have filled in are
all settable, so `lib/mahjongg/about_dialog.rb` sets them by hand.

## GVariant is unwrapped on the way out, but not on the way in

Anything that returns a `GVariant` hands back a plain Ruby object:

```ruby
action.state                       # => "Turtle", not a GLib::Variant
parameter                          # in an "activate" handler: "Turtle"
settings.get_default_value('tileset')  # => "postmodern"
```

Calling `.get_string` on any of those raises `NoMethodError: undefined method
'get_string' for an instance of String`. Setting still needs the wrapper:
`action.state = GLib::Variant.new('Turtle')`.

## Tearing down a widget tree from Ruby's finalizers segfaults

At interpreter exit, `rb_objspace_call_finalizer` unrefs the toplevel window,
and disposing the Adwaita widget tree crashes inside
`g_object_notify_queue_thaw`:

```
gtk_widget_unparent → g_object_notify_queue_thaw → signal_emit_unlocked_R
[BUG] Segmentation fault
```

`Gtk::CustomSorter` reaches the same end by a shorter route — a sorter
collected while GTK still owns it crashes in `gtk_custom_sorter_dispose` →
`rb_gi_callback_data_free`.

Two consequences, both in the test harness:

- `test/gtk_driver.rb` ends with `exit!`, not `exit`, so a clean run is not
  turned into a spurious failure by the shutdown crash.
- `lib/mahjongg/score_dialog.rb` keeps a strong reference to every
  `Gtk::CustomSorter` and `Gtk::MultiSorter` it builds, so none is collected
  while its column still points at it.

## GtkWidgetPaintable snapshots to nothing while a redraw is pending

The screenshot recipe in the `ruby-gtk-testing` skill works for the first shot
of a run and then returns `nil` from `Gtk::Snapshot#to_node` for every later
one, reported as "widget produced no render node (not realised yet?)" even
though the widget is realised, mapped, visible and correctly sized.

The widget has a queued redraw that the main loop has not serviced. Draining
it first fixes every case except one still mid-animation:

```ruby
GLib::MainContext.default.then do |context|
  100.times { context.pending? ? context.iteration(false) : break }
end
```

For an animation (the pause overlay's 200 ms reveal), take the screenshot in
the *next* driver step — one tick later, the animation has finished.

The same file also has to reuse one `Gsk::CairoRenderer` for the whole run:
realising and unrealising a fresh one per shot has the same nil-node effect,
and unrealising it at all trips
`gsk_renderer_dispose: assertion failed: (!priv->is_realized)`.

## The dconf backend accepts writes and rolls them back without a session bus

Not a ruby-gnome defect, but it cost an hour. With no D-Bus session, writes
through `Gio::Settings` appear to succeed — `get_string` returns the new value
immediately — and are then silently reverted to the schema default when the
backend's D-Bus call fails, some seconds later. A test that writes a setting
and checks it two steps afterwards sees the default and no error anywhere.

`ENV['GSETTINGS_BACKEND'] = 'memory'` in `test/ui_test.rb`.

## Icon names can be claimed by a desktop theme that draws nothing

`Gtk::IconTheme#add_search_path` puts the shipped icons in the `hicolor`
fallback, so any installed icon theme carrying the same name wins — including
one whose version is malformed. On the machine this port was written on,
`WhiteSur-dark` ships a `stopwatch-symbolic` with no `viewBox`, which renders
blank at any size, and `has_icon?` cheerfully reports `true`.

This is not fixable from the application side: GTK searches the current theme
before the app's own resource path, so upstream's GResource icons lose the
same way. Recorded here only so the next person does not spend an hour on it —
the fix belongs in the icon theme.
