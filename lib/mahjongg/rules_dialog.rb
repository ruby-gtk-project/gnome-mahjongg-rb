# frozen_string_literal: true

require 'adwaita'

require_relative 'i18n'

module Mahjongg
  # The seven rules of the game, one row each.
  class RulesDialog
    include I18n

    def build
      dialog.tap do |dlg|
        dlg.add(page)

        page.tap do |pg|
          pg.add(group)

          group.tap do |grp|
            rules.each { |row| grp.add(row) }
          end
        end
      end
    end

    def dialog
      @dialog ||= Adwaita::PreferencesDialog.new.tap do |dlg|
        dlg.title = _('Game Rules')
        dlg.content_width = 600
      end
    end

    def page = @page ||= Adwaita::PreferencesPage.new
    def group = @group ||= Adwaita::PreferencesGroup.new

    def rules
      @rules ||= [
        rule(
          "#{Application::APP_ID}-symbolic",
          rules_text('Clear the board by matching pairs of identical tiles'),
        ),
        rule(
          'object-select-symbolic',
          rules_text('Only uncovered tiles with a free long edge can be selected'),
        ),
        rule(
          'stopwatch-symbolic',
          rules_text('Rounds are scored based on completion time'),
        ),
        rule(
          'media-playback-pause-symbolic',
          rules_text('You can pause the game'),
          rules_text('Tile faces will be hidden'),
        ),
        rule(
          'edit-undo-symbolic',
          rules_text('You can undo or redo a move'),
          rules_text('No time penalty is added'),
        ),
        rule(
          'dialog-information-symbolic',
          rules_text('You can use hints to reveal matching tiles'),
          rules_text('Adds a 30-second time penalty'),
        ),
        rule(
          'media-playlist-shuffle-symbolic',
          rules_text('You can shuffle tiles when no moves are left'),
          rules_text('Adds a 60-second time penalty'),
        ),
      ]
    end

    private

      def rules_text(message) = p_('game rules', message)

      def rule(icon_name, title, subtitle = nil)
        Adwaita::ActionRow.new.tap do |row|
          row.title = title
          unless subtitle.nil?
            row.subtitle = subtitle
          end
          row.add_prefix(Gtk::Image.new.tap { |image| image.icon_name = icon_name })
        end
      end
  end
end
