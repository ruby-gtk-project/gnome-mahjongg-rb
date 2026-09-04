# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'game_view'
require_relative 'i18n'
require_relative 'menu'
require_relative 'pause_overlay'

module Mahjongg
  # The game window: header bar, clock, and a stack of two board views that
  # the layouts slide between.
  class Window
    include I18n

    COMPACT_HEIGHT = 380

    attr_reader :game_view

    def initialize(application, settings, maps)
      @application = application
      @settings = settings
      @maps = maps
      @theme = nil
      @restore_game = false
      @unset_game_idle = nil
      @game_view = nil
      @pause_overlay_shown = false
    end

    def build
      window.tap do |win|
        win.content = toolbar_view
        win.add_breakpoint(compact_breakpoint)

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = overlay

          header_bar.tap do |bar|
            bar.title_widget = title_widget
            bar.pack_start(undo_button)
            bar.pack_start(redo_button)
            bar.pack_end(menu_button)
            bar.pack_end(pause_button)
            bar.pack_end(hint_button)

            menu_button.tap do |button|
              button.menu_model = Menu.build(@maps)
              button.signal_connect('notify::active') { pause_for_menu }
            end
          end

          overlay.tap do |over|
            over.child = stack

            stack.tap do |st|
              st.add_named(primary_view.build, 'primary')
              st.add_named(secondary_view.build, 'secondary')
            end
          end
        end

        compact_breakpoint.tap do |breakpoint|
          breakpoint.signal_connect('apply') { win.add_css_class('compact') }
          breakpoint.signal_connect('unapply') { win.remove_css_class('compact') }
        end

        # The board pauses itself whenever the player cannot see it, but not
        # when the window merely loses focus: watching the board on another
        # monitor while working elsewhere is legitimate.
        win.signal_connect('notify::visible-dialog') { pause_for_dialog }
        win.signal_connect('notify::suspended') { pause_for_suspend }

        @settings.bind(
          'window-width',
          win,
          'default-width',
          Gio::SettingsBindFlags::DEFAULT,
        )
        @settings.bind(
          'window-height',
          win,
          'default-height',
          Gio::SettingsBindFlags::DEFAULT,
        )
        @settings.bind(
          'window-is-maximized',
          win,
          'maximized',
          Gio::SettingsBindFlags::DEFAULT,
        )

        @settings.signal_connect('changed') { |_settings, key| setting_changed(key) }
        pause_overlay.build
        update_theme
      end
    end

    # Hand the window a fresh game. The two board views alternate so the old
    # layout can slide out while the new one slides in.
    def new_game(game, rotate_map = false, restore = false)
      transition_type = :none
      previous_view = @game_view

      if rotate_map
        if @settings.get_string('map-rotation') == 'single'
          transition_type = :crossfade
        else
          transition_type = :slide_left
        end
      end

      next_name = 'primary'
      @game_view = primary_view
      if stack.visible_child_name == 'primary'
        next_name = 'secondary'
        @game_view = secondary_view
      end
      @restore_game = restore
      update_theme(previous_view)
      release_previous_view(previous_view)

      @game_view.game = game
      game.on(:moved) { moved }
      game.on(:paused_changed) { paused_changed }
      game.on(:tick) { tick }

      window.visible_dialog&.force_close

      stack.transition_type = transition_type
      stack.visible_child_name = next_name
    end

    def window
      @window ||= Adwaita::ApplicationWindow.new(@application).tap do |win|
        win.title = _('Mahjongg')
        win.icon_name = Application::APP_ID
        win.set_size_request(360, 294)
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new
    def overlay = @overlay ||= Gtk::Overlay.new
    def primary_view = @primary_view ||= GameView.new
    def secondary_view = @secondary_view ||= GameView.new
    def pause_overlay = @pause_overlay ||= PauseOverlay.new

    def compact_breakpoint
      @compact_breakpoint ||=
        Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse("max-height: #{COMPACT_HEIGHT}px"))
    end

    def title_widget
      @title_widget ||= Adwaita::WindowTitle.new('', '').tap do |title|
        title.add_css_class('numeric')
      end
    end

    def stack
      @stack ||= Gtk::Stack.new.tap do |st|
        st.transition_duration = 250
        st.add_css_class('game')
        # The contrast filter is a CSS effect on the whole board, so it only
        # has to be declared once, here.
        st.add_css_class('tile-filter')
      end
    end

    def undo_button
      @undo_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'edit-undo-symbolic'
        button.action_name = 'app.undo'
        button.tooltip_text = _('Undo')
      end
    end

    def redo_button
      @redo_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'edit-redo-symbolic'
        button.action_name = 'app.redo'
        button.tooltip_text = _('Redo')
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = 'open-menu-symbolic'
        button.primary = true
        button.tooltip_text = _('Main Menu')
      end
    end

    def pause_button
      @pause_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'media-playback-pause-symbolic'
        button.action_name = 'app.pause'
        button.tooltip_text = _('Pause Game')
      end
    end

    def hint_button
      @hint_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'dialog-information-symbolic'
        button.action_name = 'app.hint'
        button.tooltip_text = _('Show Hint')
      end
    end

    private

      def release_previous_view(previous_view)
        unless previous_view.nil?
          unless @unset_game_idle.nil?
            GLib::Source.remove(@unset_game_idle)
          end

          # A moment's delay, so an unpaused board gets to redraw before its
          # view is torn down.
          @unset_game_idle = GLib::Idle.add do
            @unset_game_idle = nil
            previous_view.game = nil
            previous_view.set_theme(nil)
            false
          end
        end
      end

      def update_theme(previous_view = nil)
        color_scheme = @settings.get_enum('background-color')
        new_theme = @settings.get_string('tileset')
        style_manager = Adwaita::StyleManager.default

        unless color_scheme == style_manager.color_scheme
          style_manager.color_scheme = color_scheme
        end

        unless @game_view.nil?
          fallback = @settings.get_default_value('tileset')
          @game_view.set_theme(theme_path(new_theme), previous_view, theme_path(fallback))
        end

        unless @theme == new_theme
          unless @theme.nil?
            toolbar_view.remove_css_class(@theme)
          end
          toolbar_view.add_css_class(new_theme)
          @theme = new_theme
        end
      end

      def theme_path(name) = Paths.data_file("themes/#{name}.svg")

      def setting_changed(key)
        if %w[tileset background-color].include?(key)
          update_theme
        end
      end

      def moved
        title_widget.subtitle = format(_('Moves Left: %2u'), @game_view.game.moves_left)
      end

      def paused_changed
        if @game_view.game.paused?
          show_paused
        else
          show_running
        end
      end

      def show_paused
        pause_button.icon_name = 'media-playback-start-symbolic'
        pause_button.tooltip_text = _('Resume Game')
        stack.add_css_class('dim-label')

        if window.visible_dialog.nil? && !menu_button.active? && !@pause_overlay_shown
          overlay.add_overlay(pause_overlay.widget)
          pause_overlay.show(@restore_game)
          @pause_overlay_shown = true
        end
        @restore_game = false
      end

      def show_running
        pause_button.icon_name = 'media-playback-pause-symbolic'
        pause_button.tooltip_text = _('Pause Game')
        stack.remove_css_class('dim-label')

        if @pause_overlay_shown
          overlay.remove_overlay(pause_overlay.widget)
          pause_overlay.hide
          @pause_overlay_shown = false
        end
      end

      def tick
        elapsed = @game_view.game.elapsed.to_i
        hours = elapsed / 3600
        minutes = (elapsed - (hours * 3600)) / 60
        seconds = elapsed - (hours * 3600) - (minutes * 60)

        # U+2236 RATIO with a left-to-right mark, so the clock reads the same
        # way round in a right-to-left locale.
        if hours.positive?
          title_widget.title = format(
            "%02d∶‎%02d∶‎%02d",
            hours,
            minutes,
            seconds,
          )
        else
          title_widget.title = format("%02d∶‎%02d", minutes, seconds)
        end
      end

      def pause_for_menu
        unless pause_overlay.visible? || @game_view&.game.nil?
          @game_view.game.paused = menu_button.active?
        end
      end

      def pause_for_dialog
        unless pause_overlay.visible? || @game_view&.game.nil?
          @game_view.game.paused = !window.visible_dialog.nil?
        end
      end

      def pause_for_suspend
        if window.suspended? && !@game_view&.game.nil?
          @game_view.game.paused = true
        end
      end
  end
end
