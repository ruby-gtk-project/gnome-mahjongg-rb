# frozen_string_literal: true

require 'gtk4'

module Mahjongg
  # The primary menu. The layout submenu is filled from the layout catalogue;
  # everything else is fixed.
  module Menu
    LAYOUT_PROGRESSIONS = [
      ['No Progression', 'single'],
      ['Sequential', 'sequential'],
      ['Random', 'random'],
    ].freeze

    BACKGROUNDS = [
      ['Follow System', 'system'],
      ['Light', 'light'],
      ['Dark', 'dark'],
    ].freeze

    THEMES = [
      ['Postmodern', 'postmodern'],
      ['Smooth', 'smooth'],
      ['Educational', 'educational'],
    ].freeze

    module_function

    def build(maps)
      Gio::Menu.new.tap do |menu|
        menu.append_section(nil, game_section)
        menu.append_section(nil, settings_section(maps))
        menu.append_section(nil, help_section)
      end
    end

    def game_section
      Gio::Menu.new.tap do |section|
        section.append('_New Game', 'app.new-game')
        section.append('_Restart Game', 'app.restart-game')
        section.append('_Scores', 'app.scores')
      end
    end

    def settings_section(maps)
      Gio::Menu.new.tap do |section|
        section.append_submenu('_Layout', layout_menu(maps))
        section.append_submenu('Layout _Progression', radio_menu('app.layout-progression', LAYOUT_PROGRESSIONS))
        section.append_submenu('_Appearance', appearance_menu)
      end
    end

    def layout_menu(maps)
      Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          maps.each do |map|
            section.append_item(target_item(maps.get_map_display_name(map.score_name), 'app.layout', map.name))
          end
          menu.append_section(nil, section)
        end
      end
    end

    def appearance_menu
      Gio::Menu.new.tap do |menu|
        menu.append_section('Background', radio_section('app.background-color', BACKGROUNDS))
        menu.append_section('Theme', radio_section('app.theme', THEMES))
      end
    end

    def radio_menu(action, entries)
      Gio::Menu.new.tap do |menu|
        menu.append_section(nil, radio_section(action, entries))
      end
    end

    def radio_section(action, entries)
      Gio::Menu.new.tap do |section|
        entries.each do |label, target|
          section.append_item(target_item(label, action, target))
        end
      end
    end

    def help_section
      Gio::Menu.new.tap do |section|
        section.append('Game R_ules', 'app.rules')
        section.append('_Keyboard Shortcuts', 'app.shortcuts')
        section.append('_About Mahjongg', 'app.about')
      end
    end

    def target_item(label, action, target)
      Gio::MenuItem.new(label, nil).tap do |item|
        item.set_action_and_target_value(action, GLib::Variant.new(target))
      end
    end
  end
end
