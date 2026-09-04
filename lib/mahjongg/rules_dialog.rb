# frozen_string_literal: true

require 'adwaita'

module Mahjongg
  # The seven rules of the game, one row each.
  class RulesDialog
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
        dlg.title = 'Game Rules'
        dlg.content_width = 600
      end
    end

    def page = @page ||= Adwaita::PreferencesPage.new
    def group = @group ||= Adwaita::PreferencesGroup.new

    def rules
      @rules ||= [
        rule("#{Application::APP_ID}-symbolic", 'Clear the board by matching pairs of identical tiles'),
        rule('object-select-symbolic', 'Only uncovered tiles with a free long edge can be selected'),
        rule('stopwatch-symbolic', 'Rounds are scored based on completion time'),
        rule(
          'media-playback-pause-symbolic',
          'You can pause the game',
          'Tile faces will be hidden',
        ),
        rule(
          'edit-undo-symbolic',
          'You can undo or redo a move',
          'No time penalty is added',
        ),
        rule(
          'dialog-information-symbolic',
          'You can use hints to reveal matching tiles',
          'Adds a 30-second time penalty',
        ),
        rule(
          'media-playlist-shuffle-symbolic',
          'You can shuffle tiles when no moves are left',
          'Adds a 60-second time penalty',
        ),
      ]
    end

    private

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
