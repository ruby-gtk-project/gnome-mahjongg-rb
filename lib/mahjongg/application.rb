# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'about_dialog'
require_relative 'game'
require_relative 'game_save'
require_relative 'history'
require_relative 'i18n'
require_relative 'map'
require_relative 'paths'
require_relative 'rules_dialog'
require_relative 'score_dialog'
require_relative 'shortcuts_dialog'
require_relative 'version'
require_relative 'window'

module Mahjongg
  # Owns the game, the layouts, the save file and the score file, and exposes
  # all of it to the window through GActions.
  class Application
    include I18n

    APP_ID = 'org.gnome.Mahjongg.Rb'

    ACCELS = {
      'app.new-game'     => ['<Primary>n'],
      'app.restart-game' => ['<Primary>r'],
      'app.pause'        => ['Escape', 'Pause', '<Primary>p'],
      'app.hint'         => ['<Primary>h'],
      'app.undo'         => ['<Primary>z'],
      'app.redo'         => ['<Shift><Primary>z'],
      'app.rules'        => ['F1'],
      # GTK registers these for its own automatic shortcuts action; this port
      # declares the action itself, so the accelerators come with it.
      'app.shortcuts'    => ['<Primary>question', '<Primary>F1'],
      'app.quit'         => ['<Primary>q'],
      'window.close'     => ['<Primary>w'],
    }.freeze

    # Stateful actions, as name => settings key. Their state is the current
    # value, which is what puts the tick beside the right menu item.
    RADIO_ACTIONS = {
      'layout'             => 'mapset',
      'layout-progression' => 'map-rotation',
      'background-color'   => 'background-color',
      'theme'              => 'tileset',
    }.freeze

    # Layouts and themes were renamed; a settings file written by an older
    # version still names them the old way.
    LAYOUT_MIGRATIONS = { 'Difficult' => 'Taipei' }.freeze
    THEME_MIGRATIONS = {
      'postmodern.svg'  => 'postmodern',
      'smooth.png'      => 'smooth',
      'educational.png' => 'educational',
    }.freeze

    attr_reader :game, :main_window

    def build
      app.tap do |application|
        application.add_main_option(
          'version',
          'v'.ord,
          GLib::OptionFlags::NONE,
          GLib::OptionArg::NONE,
          _('Print release version and exit'),
          nil,
        )
        application.signal_connect('handle-local-options') { |_app, options| handle_options(options) }
        application.signal_connect('startup') { start_up }
        application.signal_connect('activate') { activate }
        application.signal_connect('shutdown') { shut_down }
      end
    end

    def run(argv = []) = app.run(argv)

    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)

    def settings = @settings ||= Gio::Settings.new(APP_ID)

    def maps
      @maps ||= Maps.new.tap(&:load)
    end

    def history
      @history ||= History.new(Paths.user_data_file('history')).tap(&:load)
    end

    def game_save
      @game_save ||= GameSave.new(Paths.user_data_file('gamesave'))
    end

    # Public so tests can drive the same code path the menu does.
    def new_game(rotate_map = true, restore = false)
      map = nil

      if restore
        restore = game_save.load(maps)
        map = game_save.map
      else
        game_save.delete
      end

      if map.nil?
        map = next_map(rotate_map)
      end

      unless @game.nil?
        @game.paused = false
        @game.destroy_timers
      end

      @game = Game.new(map)
      @main_window.new_game(@game, rotate_map, restore)

      @game.on(:attempt_move) { attempt_move }
      @game.on(:moved) { moved }
      @game.on(:paused_changed) { paused_changed }

      if restore
        @game.restore(game_save)
      else
        @game.generate
      end
    end

    def show_scores(selected_layout = '', completed_entry = nil)
      ScoreDialog.new(
        history,
        maps,
        selected_layout,
        completed_entry,
      ).tap do |dialog|
        dialog.build.present(@main_window.window)
      end
    end

    private

      # Returning a non-negative value stops here with that exit status;
      # -1 carries on and activates.
      def handle_options(options)
        if options.contains?('version')
          # Deliberately untranslated, so it stays easy to parse.
          warn "gnome-mahjongg-rb #{VERSION}"
          0
        else
          -1
        end
      end

      def start_up
        # The window manager and the desktop shell read this, so it has to be
        # set before any window exists.
        GLib.application_name = _('Mahjongg')
        add_actions
        ACCELS.each { |name, accels| app.set_accels_for_action(name, accels) }
        load_style
        # Settings are written through in a batch, so a game spent flicking
        # between layouts does not rewrite dconf on every step.
        settings.delay
      end

      def activate
        if app.active_window.nil?
          create_window
        end
        app.active_window.present
      end

      def shut_down
        unless @game.nil?
          @game.destroy_timers

          # A finished game has nothing to save; advance the layout instead so
          # the next session opens on the next one.
          if !game_save.write(@game) && @game.inspecting?
            next_map
          end
        end
        settings.apply
      end

      def create_window
        migrate_settings
        @main_window = Window.new(app, settings, maps)
        @main_window.build

        RADIO_ACTIONS.each do |name, key|
          app.lookup_action(name).state = GLib::Variant.new(settings.get_string(key))
        end

        new_game(settings.get_string('map-rotation') == 'random', true)
      end

      def migrate_settings
        migrate('mapset', LAYOUT_MIGRATIONS)
        migrate('tileset', THEME_MIGRATIONS)
      end

      def migrate(key, replacements)
        replacement = replacements[settings.get_string(key)]
        unless replacement.nil?
          settings.set_string(key, replacement)
        end
      end

      def load_style
        Gtk::CssProvider.new.tap do |provider|
          provider.load_from_path(Paths.data_file('css/style.css'))
          Gtk::StyleContext.add_provider_for_display(
            Gdk::Display.default,
            provider,
            Gtk::StyleProvider::PRIORITY_APPLICATION,
          )
        end
        # The shipped action icons are a fallback: a desktop icon theme that
        # already has `stopwatch-symbolic` and friends supplies its own, which
        # is the same thing upstream gets from its GResource.
        Gtk::IconTheme.get_for_display(Gdk::Display.default).add_search_path(Paths.data_file('icons'))
      end

      def add_actions
        {
          'new-game'     => -> { new_game },
          'undo'         => -> { @game.undo },
          'redo'         => -> { @game.redo },
          'hint'         => -> { @game.show_hint },
          'pause'        => -> { @game.paused = !@game.paused? },
          'restart-game' => -> { restart_game },
          'scores'       => -> { show_scores(@game.map.score_name) },
          'rules'        => -> { RulesDialog.new.build.present(@main_window.window) },
          'shortcuts'    => -> { ShortcutsDialog.new.build.present(@main_window.window) },
          'about'        => -> { AboutDialog.new.build.present(@main_window.window) },
          'quit'         => -> { app.quit },
        }.each do |name, handler|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect('activate') { handler.call }
            app.add_action(action)
          end
        end

        RADIO_ACTIONS.each_key { |name| add_radio_action(name) }
      end

      def add_radio_action(name)
        Gio::SimpleAction.new(name, GLib::VariantType.new('s'), GLib::Variant.new('')).tap do |action|
          action.signal_connect('activate') do |simple_action, parameter|
            send(:"#{name.tr("-", "_")}_selected", simple_action, parameter)
          end
          app.add_action(action)
        end
      end

      # Changing the layout by hand ends the current game, so ask first.
      def layout_selected(action, layout)
        if settings.get_string('mapset') == layout
          action.state = GLib::Variant.new(layout)
        elsif @game.started? && !@game.inspecting?
          confirm_layout_change(action, layout)
        else
          apply_layout(action, layout)
        end
      end

      def confirm_layout_change(action, layout)
        alert(_('Change Layout?'), _('This will end your current game.')).tap do |dialog|
          dialog.add_response('cancel', _('_Cancel'))
          dialog.add_response('change_layout', _('Change _Layout'))
          dialog.set_response_appearance('change_layout', Adwaita::ResponseAppearance::DESTRUCTIVE)
          dialog.default_response = 'cancel'
          dialog.signal_connect('response') do |_dialog, response|
            if response == 'change_layout'
              apply_layout(action, layout)
            end
          end
          dialog.present(@main_window.window)
        end
      end

      def apply_layout(action, layout)
        settings.set_string('mapset', layout)
        settings.apply
        action.state = GLib::Variant.new(layout)
        # A layout picked by hand is not a rotation.
        new_game(false)
      end

      def layout_progression_selected(action, value) = store_choice(action, 'map-rotation', value)
      def background_color_selected(action, value) = store_choice(action, 'background-color', value)
      def theme_selected(action, value) = store_choice(action, 'tileset', value)

      def store_choice(action, key, value)
        action.state = GLib::Variant.new(value)

        unless settings.get_string(key) == value
          settings.set_string(key, value)
          settings.apply
        end
      end

      def restart_game
        @game.restart
        game_save.delete
      end

      # Returning false tells the board a click was consumed: the first click
      # on a paused game just resumes it.
      def attempt_move
        if @game.paused?
          @game.paused = false
          false
        else
          true
        end
      end

      def moved
        app.lookup_action('hint').enabled = @game.moves_left.positive?
        app.lookup_action('undo').enabled = @game.can_undo?
        app.lookup_action('redo').enabled = @game.can_redo?

        unless @game.inspecting?
          app.lookup_action('pause').enabled = @game.started?
          finish_move
        end
      end

      def finish_move
        if @game.complete?
          record_win
        elsif !@game.can_move?
          offer_way_out
        end
      end

      def record_win
        entry = history.add(
          Time.now,
          @game.map.score_name,
          @game.elapsed.to_i,
          History.real_name,
        )
        game_save.delete
        show_scores(entry.name, entry)
        app.lookup_action('pause').enabled = false
      end

      def offer_way_out
        can_shuffle = @game.can_shuffle?
        body = _('You can undo your moves and try to find a solution, or start a new game.')
        if can_shuffle
          body = _('You can undo your moves and try to find a solution, or reshuffle the remaining tiles.')
        end

        alert(_('No Moves Left'), body).tap do |dialog|
          dialog.add_response('quit', _('_Quit'))
          dialog.set_response_appearance('quit', Adwaita::ResponseAppearance::DESTRUCTIVE)
          dialog.add_response('new_game', _('_New Game'))
          if can_shuffle
            dialog.add_response('reshuffle', _('_Reshuffle'))
          end
          dialog.add_response('continue', _('_Continue'))
          dialog.default_response = 'continue'
          dialog.signal_connect('response') { |_dialog, response| no_moves_response(response) }
          dialog.present(@main_window.window)
        end
      end

      def no_moves_response(response)
        case response
        when 'reshuffle' then @game.shuffle_remaining
        when 'new_game' then new_game
        when 'quit'
          game_save.delete
          app.quit
        end
      end

      def paused_changed
        if @game.paused?
          %w[hint undo redo].each { |name| app.lookup_action(name).enabled = false }
        else
          app.lookup_action('hint').enabled = @game.moves_left.positive?
          app.lookup_action('undo').enabled = @game.can_undo?
          app.lookup_action('redo').enabled = @game.can_redo?
        end
      end

      def alert(heading, body) = Adwaita::AlertDialog.new(heading, body)

      # The layout for the next game: the one in settings, advanced by the
      # progression setting when this is a rotation.
      def next_map(rotate_map = true)
        map = maps.get_map_by_name(settings.get_string('mapset'))

        if map.nil?
          map = maps.get_map_at_position(0)
        end

        if rotate_map
          case settings.get_string('map-rotation')
          when 'sequential' then map = maps.get_next_map(map)
          when 'random' then map = maps.get_random_map
          end
        end

        unless settings.get_string('mapset') == map.name
          app.lookup_action('layout').state = GLib::Variant.new(map.name)
          settings.set_string('mapset', map.name)
        end
        map
      end
  end
end
