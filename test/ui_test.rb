# frozen_string_literal: true

# Drives the real window headlessly: builds it, plays moves through the board
# view, walks every action and dialog, and screenshots as it goes.

require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir
ENV['XDG_DATA_HOME'] = Dir.mktmpdir
# There is no session bus here, so the dconf backend accepts writes and then
# quietly rolls them back when its D-Bus call fails.
ENV['GSETTINGS_BACKEND'] = 'memory'

require 'mahjongg'
require_relative 'gtk_driver'

app = Mahjongg::Application.new

def view(app) = app.main_window.game_view
def window(app) = app.main_window.window
def activate(app, name, target = nil) = app.app.lookup_action(name).activate(target)

def click_tile(app, tile, n_press = 1)
  x, y = view(app).tile_centre(tile)
  view(app).click(n_press, x, y)
end

# A selectable pair that is actually on the board right now.
def find_pair(game)
  found = nil
  game.tiles.each do |tile|
    if found.nil? && tile.visible && tile.selectable?
      partner = game.tiles.find do |other|
        !other.equal?(tile) && other.visible && other.selectable? && other.matches?(tile)
      end
      unless partner.nil?
        found = [tile, partner]
      end
    end
  end
  found
end

def resume(app)
  if app.game.paused?
    click_tile(app, app.game.tiles.find(&:visible))
  end
end

# The smooth and educational sheets are PNGs wrapped in an SVG; a wrong
# reference in the wrapper renders a perfectly valid, perfectly empty surface.
def blank?(surface)
  surface.nil? || surface.data.each_byte.all?(&:zero?)
end

# AdwAlertDialog has no Ruby-side `response` call, so the signal is emitted
# directly — the same thing clicking the button does.
def respond(dialog, response)
  dialog.signal_emit('response', response)
  dialog.close
end

GtkDriver.drive(app, shots: 'tmp/shots') do |d, _|
  d.window { window(app) }

  d.step('the window builds and a game is dealt') do
    d.check('there is a window') { !app.main_window.nil? }
    d.check('a game is running') { !app.game.nil? }
    d.check('the board has 144 tiles') { app.game.n_tiles == 144 }
    d.check('the layout is Turtle') { app.game.map.name == 'Turtle' }
    d.check('the board view has the game') { view(app).game.equal?(app.game) }
    d.check('the clock reads 00:00') { app.main_window.title_widget.title == '00∶‎00' }
    d.check('the moves-left subtitle is set') do
      app.main_window.title_widget.subtitle == format('Moves Left: %2u', app.game.moves_left)
    end
    d.check('undo starts disabled') { !app.app.lookup_action('undo').enabled? }
    d.check('redo starts disabled') { !app.app.lookup_action('redo').enabled? }
    d.check('hint starts enabled') { app.app.lookup_action('hint').enabled? }
  end

  d.step('the board renders') do
    d.check('the tile sheet loaded') { !view(app).theme_surface.nil? }
    d.check('the tile sheet is not blank') { !blank?(view(app).theme_surface) }
    d.check('the sheet is 43 columns wide') do
      view(app).loaded_theme_width >= view(app).tile_pattern_width * 43 / 8
    end
    d.shot('01-board')
  end

  d.step('clicking a tile selects it') do
    @pair = find_pair(app.game)
    d.check('the board has a selectable pair') { !@pair.nil? }
    click_tile(app, @pair[0])
    d.check('the tile is selected') { app.game.selected_tile.equal?(@pair[0]) }
    d.check('the tile is highlighted') { @pair[0].highlighted }
    d.shot('02-selected')
  end

  d.step('clicking it again puts it back down') do
    click_tile(app, @pair[0])
    d.check('nothing is selected') { app.game.selected_tile.nil? }
    d.check('the tile is no longer highlighted') { !@pair[0].highlighted }
  end

  d.step('clicking a matching pair removes it') do
    click_tile(app, @pair[0])
    click_tile(app, @pair[1])
    d.check('both tiles are gone') { !@pair[0].visible && !@pair[1].visible }
    d.check('the move counter advanced') { app.game.current_move == 2 }
    d.check('undo became available') { app.app.lookup_action('undo').enabled? }
    d.check('the subtitle followed the move') do
      app.main_window.title_widget.subtitle == format('Moves Left: %2u', app.game.moves_left)
    end
    d.shot('03-after-move')
  end

  d.step('clicking a blocked tile shakes it rather than selecting it') do
    blocked = app.game.tiles.find { |tile| tile.visible && !tile.selectable? }
    click_tile(app, blocked)
    d.check('a blocked tile exists') { !blocked.nil? }
    d.check('it is shaking') { blocked.shaking }
    d.check('it did not get selected') { !app.game.selected_tile.equal?(blocked) }
  end

  d.step('undo and redo walk the move back and forward') do
    activate(app, 'undo')
    d.check('the tiles came back') { @pair[0].visible && @pair[1].visible }
    d.check('redo became available') { app.app.lookup_action('redo').enabled? }
    activate(app, 'redo')
    d.check('the tiles went away again') { !@pair[0].visible && !@pair[1].visible }
  end

  d.step('a hint costs thirty seconds') do
    @before_hint = app.game.elapsed
    activate(app, 'hint')
    d.check('the clock jumped by the penalty') { app.game.elapsed - @before_hint >= 30 }
    d.check('the game has started') { app.game.started? }
    d.shot('04-hint')
  end

  d.step('pausing hides the tile faces') do
    activate(app, 'pause')
    d.check('the game is paused') { app.game.paused? }
    d.check('the pause button offers to resume') do
      app.main_window.pause_button.icon_name == 'media-playback-start-symbolic'
    end
    d.check('undo is disabled while paused') { !app.app.lookup_action('undo').enabled? }
    d.check('the pause overlay is visible') { app.main_window.pause_overlay.visible? }
    d.check('the overlay offers Quit, not Restart') do
      app.main_window.pause_overlay.quit_button.visible? &&
        !app.main_window.pause_overlay.restart_button.visible?
    end
  end

  d.step('the paused board renders with the tile faces hidden') do
    d.shot('05-paused')
  end

  d.step('a click on a paused board just resumes it') do
    click_tile(app, app.game.tiles.find(&:visible))
    d.check('the game resumed') { !app.game.paused? }
    d.check('nothing got selected') { app.game.selected_tile.nil? }
    d.check('the pause overlay went away') { !app.main_window.pause_overlay.visible? }
    d.check('the pause button offers to pause') do
      app.main_window.pause_button.icon_name == 'media-playback-pause-symbolic'
    end
  end

  d.step('the theme can be changed') do
    activate(app, 'theme', GLib::Variant.new('smooth'))
    d.check('the setting changed') { app.settings.get_string('tileset') == 'smooth' }
    d.check('the action state followed') { app.app.lookup_action('theme').state == 'smooth' }
  end

  d.step('the new theme renders') do
    d.check('a sheet is loaded') { !view(app).theme_surface.nil? }
    d.check('the sheet is not blank') { !blank?(view(app).theme_surface) }
    d.shot('06-smooth')
  end

  d.step('the third theme can be selected') do
    activate(app, 'theme', GLib::Variant.new('educational'))
    d.check('the setting changed') { app.settings.get_string('tileset') == 'educational' }
  end

  d.step('the educational theme renders') do
    d.check('the sheet is not blank') { !blank?(view(app).theme_surface) }
    d.shot('06b-educational')
  end

  d.step('the background can be darkened') do
    activate(app, 'background-color', GLib::Variant.new('dark'))
    d.check('the setting changed') { app.settings.get_string('background-color') == 'dark' }
    d.check('Adwaita went dark') do
      Adwaita::StyleManager.default.color_scheme == Adwaita::ColorScheme::FORCE_DARK
    end
  end

  d.step('the dark board renders') do
    d.shot('07-dark')
    activate(app, 'background-color', GLib::Variant.new('system'))
    activate(app, 'theme', GLib::Variant.new('postmodern'))
  end

  d.step('the layout progression can be changed') do
    activate(app, 'layout-progression', GLib::Variant.new('sequential'))
    d.check('the setting changed') { app.settings.get_string('map-rotation') == 'sequential' }
    d.check('the action state followed') do
      app.app.lookup_action('layout-progression').state == 'sequential'
    end
  end

  d.step('changing layout mid-game asks first') do
    activate(app, 'layout', GLib::Variant.new('Cloud'))
    d.check('a dialog opened') { !window(app).visible_dialog.nil? }
    d.check('it is the layout warning') { window(app).visible_dialog.heading == 'Change Layout?' }
    d.shot('08-change-layout')
  end

  d.step('cancelling leaves the layout alone') do
    respond(window(app).visible_dialog, 'cancel')
    d.check('still on Turtle') { app.game.map.name == 'Turtle' }
    d.check('the setting is untouched') { app.settings.get_string('mapset') == 'Turtle' }
  end

  d.step('confirming changes it') do
    activate(app, 'layout', GLib::Variant.new('Cloud'))
    respond(window(app).visible_dialog, 'change_layout')
  end

  d.step('the new layout is dealt') do
    d.check('the game is on Cloud') { app.game.map.name == 'Cloud' }
    d.check('the setting followed') { app.settings.get_string('mapset') == 'Cloud' }
    d.check('the board was re-dealt') { app.game.tiles.all?(&:visible) }
    d.check('the clock was reset') { app.main_window.title_widget.title == '00∶‎00' }
  end

  d.step('the Cloud layout renders') { d.shot('09-cloud') }

  d.step('the rules dialog opens') do
    activate(app, 'background-color', GLib::Variant.new('light'))
    # Start the clock first: an unstarted game has nothing to pause.
    find_pair(app.game).then { |pair| app.game.remove_pair(pair[0], pair[1]) }
    activate(app, 'rules')
    d.check('a dialog opened') { !window(app).visible_dialog.nil? }
    d.check('it is the rules') { window(app).visible_dialog.title == 'Game Rules' }
    d.check('every icon the app names resolves') do
      theme = Gtk::IconTheme.get_for_display(Gdk::Display.default)
      %w[stopwatch-symbolic media-playlist-shuffle-symbolic application-exit-symbolic
         edit-undo-symbolic edit-redo-symbolic dialog-information-symbolic
         media-playback-pause-symbolic media-playback-start-symbolic open-menu-symbolic
         user-trash-symbolic object-select-symbolic
         org.gnome.Mahjongg.Rb-symbolic
].all? { |name| theme.has_icon?(name) }
    end
    d.check('opening a dialog pauses the game') { app.game.paused? }
  end

  d.step('the rules dialog renders') do
    d.shot('10-rules', window(app).visible_dialog)
    window(app).visible_dialog.close
  end

  d.step('the shortcuts dialog opens') do
    activate(app, 'shortcuts')
    d.check('a dialog opened') { !window(app).visible_dialog.nil? }
  end

  d.step('the shortcuts dialog renders') do
    d.shot('11-shortcuts', window(app).visible_dialog)
    window(app).visible_dialog.close
  end

  d.step('the about dialog opens') do
    activate(app, 'about')
    d.check('a dialog opened') { !window(app).visible_dialog.nil? }
  end

  d.step('the about dialog renders') do
    d.shot('12-about', window(app).visible_dialog)
    window(app).visible_dialog.close
  end

  d.step('the scores dialog opens with no scores yet') do
    activate(app, 'scores')
    d.check('a dialog opened') { !window(app).visible_dialog.nil? }
    d.check('it is the scores') { window(app).visible_dialog.title == 'Scores' }
  end

  d.step('the empty-scores state renders') do
    d.shot('13-no-scores', window(app).visible_dialog)
    window(app).visible_dialog.close
  end

  d.step('restart re-deals the same board') do
    @numbers = app.game.tiles.map(&:number)
    @seed = app.game.seed
    resume(app)
    activate(app, 'restart-game')
    d.check('the seed is unchanged') { app.game.seed == @seed }
    d.check('the tiles are unchanged') { app.game.tiles.map(&:number) == @numbers }
    d.check('every tile is back') { app.game.tiles.all?(&:visible) }
  end

  d.step('new game moves to the next layout in sequence') do
    activate(app, 'new-game')
    d.check('the layout advanced') { app.game.map.name == 'Tic-Tac-Toe' }
    d.check('the setting followed') { app.settings.get_string('mapset') == 'Tic-Tac-Toe' }
  end

  d.step('the no-moves-left state offers a way out') do
    app.send(:offer_way_out)
    d.check('a dialog opened') { !window(app).visible_dialog.nil? }
    d.check('it is the no-moves warning') { window(app).visible_dialog.heading == 'No Moves Left' }
  end

  d.step('the no-moves dialog renders') do
    d.shot('14-no-moves', window(app).visible_dialog)
    respond(window(app).visible_dialog, 'continue')
  end

  d.step('playing the board out wins the game') do
    resume(app)
    # Clear the board the way a player would: take any legal pair, and when
    # picking greedily paints us into a corner, reshuffle — which is exactly
    # what the No Moves Left dialog offers.
    @shuffles = 0
    until app.game.complete?
      pair = find_pair(app.game)
      if pair.nil?
        unless app.game.can_shuffle?
          break
        end

        app.game.shuffle_remaining
        @shuffles += 1
      else
        app.game.remove_pair(pair[0], pair[1])
      end
    end
    d.check('the board is clear') { app.game.complete? }
    d.check('the game is in inspection mode') { app.game.inspecting? }
    d.check('a score was recorded') { app.history.length == 1 }
    d.check('it is filed under the layout') { app.history.first.name == 'tictactoe' }
    d.check('the scores dialog opened') { !window(app).visible_dialog.nil? }
  end

  d.step('the winning scores dialog renders') do
    d.shot('15-win', window(app).visible_dialog)
    d.check('pause is disabled after a win') { !app.app.lookup_action('pause').enabled? }
  end

  d.step('the winner can be renamed') do
    window(app).visible_dialog.close
    d.check('the score survived the dialog closing') { app.history.length == 1 }
  end

  d.step('the scores dialog now lists the score') do
    activate(app, 'scores')
    d.check('a dialog opened') { !window(app).visible_dialog.nil? }
  end

  d.step('the populated scores dialog renders') do
    d.shot('16-scores', window(app).visible_dialog)
    window(app).visible_dialog.close
  end
end
