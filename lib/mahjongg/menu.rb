# frozen_string_literal: true

require 'gtk4'

require_relative 'i18n'

module Mahjongg
  # The primary menu. The layout submenu is filled from the layout catalogue;
  # everything else is fixed.
  module Menu
    include I18n
    extend I18n

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
        section.append(_('_New Game'), 'app.new-game')
        section.append(_('_Restart Game'), 'app.restart-game')
        section.append(_('_Scores'), 'app.scores')
      end
    end

    def settings_section(maps)
      Gio::Menu.new.tap do |section|
        section.append_submenu(_('_Layout'), layout_menu(maps))
        section.append_submenu(
          _('Layout _Progression'),
          radio_menu('app.layout-progression', LAYOUT_PROGRESSIONS, 'layout progression'),
        )
        section.append_submenu(_('_Appearance'), appearance_menu)
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
        menu.append_section(_('Background'), radio_section('app.background-color', BACKGROUNDS, 'background color'))
        menu.append_section(_('Theme'), radio_section('app.theme', THEMES, 'mahjongg theme name'))
      end
    end

    def radio_menu(action, entries, context)
      Gio::Menu.new.tap do |menu|
        menu.append_section(nil, radio_section(action, entries, context))
      end
    end

    def radio_section(action, entries, context)
      Gio::Menu.new.tap do |section|
        entries.each do |label, target|
          section.append_item(target_item(p_(context, label), action, target))
        end
      end
    end

    def help_section
      Gio::Menu.new.tap do |section|
        section.append(_('Game R_ules'), 'app.rules')
        section.append(_('_Keyboard Shortcuts'), 'app.shortcuts')
        section.append(_('_About Mahjongg'), 'app.about')
      end
    end

    def target_item(label, action, target)
      Gio::MenuItem.new(label, nil).tap do |item|
        item.set_action_and_target_value(action, GLib::Variant.new(target))
      end
    end
  end
end
