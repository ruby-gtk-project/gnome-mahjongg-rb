# frozen_string_literal: true

require 'adwaita'

require_relative 'i18n'

module Mahjongg
  # The keyboard shortcuts window. Items given an action name pick their
  # accelerator up from the application; F10 belongs to GTK, so it is spelled
  # out.
  class ShortcutsDialog
    include I18n

    GAME_SHORTCUTS = [
      ['New Game', 'app.new-game'],
      ['Restart Game', 'app.restart-game'],
      ['Pause Game', 'app.pause'],
      ['Undo', 'app.undo'],
      ['Redo', 'app.redo'],
      ['Show Hint', 'app.hint'],
    ].freeze

    GENERAL_SHORTCUTS = [
      ['Show Keyboard Shortcuts', 'app.shortcuts'],
      ['Close Window', 'window.close'],
      ['Quit', 'app.quit'],
    ].freeze

    def build
      dialog.tap do |dlg|
        dlg.add(game_section)
        dlg.add(general_section)

        game_section.tap do |section|
          GAME_SHORTCUTS.each { |title, action| section.add(action_item(title, action)) }
        end

        general_section.tap do |section|
          section.add(action_item('Show Game Rules', 'app.rules'))
          # F10 is GTK's own menu shortcut, so there is no action to read it
          # off; it has to be spelled out.
          section.add(accelerator_item('Show Main Menu', 'F10'))
          GENERAL_SHORTCUTS.each { |title, action| section.add(action_item(title, action)) }
        end
      end
    end

    def dialog = @dialog ||= Adwaita::ShortcutsDialog.new

    def game_section
      @game_section ||= Adwaita::ShortcutsSection.new.tap do |section|
        section.title = shortcut_text('Game')
      end
    end

    def general_section
      @general_section ||= Adwaita::ShortcutsSection.new.tap do |section|
        section.title = shortcut_text('General')
      end
    end

    private

      def shortcut_text(message) = p_('shortcut window', message)

      # `Adwaita::ShortcutsItem.new(title, x)` always resolves to the
      # (title, accelerator) overload in the Ruby bindings — the keyword form
      # the introspection data advertises is rejected — so an action-driven
      # item is built with an empty accelerator and then given its action.
      def action_item(title, action_name)
        Adwaita::ShortcutsItem.new(shortcut_text(title), '').tap do |item|
          item.action_name = action_name
        end
      end

      def accelerator_item(title, accelerator)
        Adwaita::ShortcutsItem.new(shortcut_text(title), accelerator)
      end
  end
end
