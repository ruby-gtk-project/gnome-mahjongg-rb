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
          p_('game rules', 'Clear the board by matching pairs of identical tiles'),
        ),
        rule(
          'object-select-symbolic',
          p_('game rules', 'Only uncovered tiles with a free long edge can be selected'),
        ),
        rule(
          'stopwatch-symbolic',
          p_('game rules', 'Rounds are scored based on completion time'),
        ),
        rule(
          'media-playback-pause-symbolic',
          p_('game rules', 'You can pause the game'),
          p_('game rules', 'Tile faces will be hidden'),
        ),
        rule(
          'edit-undo-symbolic',
          p_('game rules', 'You can undo or redo a move'),
          p_('game rules', 'No time penalty is added'),
        ),
        rule(
          'dialog-information-symbolic',
          p_('game rules', 'You can use hints to reveal matching tiles'),
          p_('game rules', 'Adds a 30-second time penalty'),
        ),
        rule(
          'media-playlist-shuffle-symbolic',
          p_('game rules', 'You can shuffle tiles when no moves are left'),
          p_('game rules', 'Adds a 60-second time penalty'),
        ),
      ]
    end

    private

      # `xgettext` only recognises a marker call whose own arguments are
      # literals, so every `p_('game rules', '...')` call above is written
      # out in full at its call site rather than funnelled through a
      # single-argument helper that would hide the literal one call frame
      # away. See `rake pot`'s task comment and `po/POTFILES.in`.

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
