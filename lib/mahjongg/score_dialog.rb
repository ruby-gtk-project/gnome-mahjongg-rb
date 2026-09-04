# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'history'
require_relative 'i18n'

module Mahjongg
  # The scores for one layout, ranked fastest first. Opened from the menu it
  # shows a layout picker; opened on a win it shows the finishing time in
  # place, with the player's name editable in the row that was just added.
  class ScoreDialog
    include I18n

    def initialize(history, maps, selected_layout = '', completed_entry = nil)
      @history = history
      @maps = maps
      @selected_layout = selected_layout
      @completed_entry = completed_entry
      @player_entry = nil
      # The sorters are held here as well as on the columns: a Gtk::CustomSorter
      # collected while GTK still owns it takes the process down.
      @sorters = []
    end

    def build
      dialog.tap do |dlg|
        dlg.child = toolbar_view

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = content_stack
          view.add_bottom_bar(bottom_bar)

          header_bar.tap do |bar|
            bar.title_widget = header_stack
            bar.pack_start(clear_scores_button)

            header_stack.tap do |stack|
              stack.add_named(layout_dropdown, 'layout')
              stack.add_named(title_widget, 'title')
            end
          end

          content_stack.tap do |stack|
            stack.add_named(no_scores_page, 'no-scores')
            stack.add_named(scrolled_window, 'scores')

            scrolled_window.tap { |scrolled| scrolled.child = score_view }
          end

          bottom_bar.tap do |bar|
            bar.center_widget = new_game_button
            bar.end_widget = quit_button
          end
        end

        set_up_score_view
        set_up_layout_dropdown
        set_up_layout_menu
        clear_scores_button.sensitive = @history.length.positive?

        show_completed_entry
        clear_scores_button.signal_connect('clicked') { confirm_clear_scores }
        dlg.signal_connect('closed') { save_edited_name }
      end
    end

    def dialog
      @dialog ||= Adwaita::Dialog.new.tap do |dlg|
        dlg.title = _('Scores')
        dlg.content_width = 360
        dlg.content_height = 500
      end
    end

    def toolbar_view
      @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
        view.reveal_bottom_bars = false
      end
    end

    def header_bar = @header_bar ||= Adwaita::HeaderBar.new
    def header_stack = @header_stack ||= Gtk::Stack.new
    def content_stack = @content_stack ||= Gtk::Stack.new
    def scrolled_window = @scrolled_window ||= Gtk::ScrolledWindow.new
    def layout_model = @layout_model ||= Gtk::StringList.new([])
    def score_model = @score_model ||= Gio::ListStore.new(HistoryEntry)

    def layout_dropdown
      @layout_dropdown ||= Gtk::DropDown.new(layout_model, nil).tap do |dropdown|
        dropdown.halign = :center
      end
    end

    def title_widget = @title_widget ||= Adwaita::WindowTitle.new(_('Game Completed 🎉'), '')

    def clear_scores_button
      @clear_scores_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'user-trash-symbolic'
        button.tooltip_text = _('Clear Scores…')
      end
    end

    def no_scores_page
      @no_scores_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = _('No Scores')
        page.description = _('Finish a game to see scores')
        page.icon_name = 'stopwatch-symbolic'
      end
    end

    def score_view
      @score_view ||= Gtk::ColumnView.new.tap do |view|
        view.reorderable = false
        view.tab_behavior = :item
      end
    end

    def rank_column
      @rank_column ||= Gtk::ColumnViewColumn.new(_('Rank'), nil).tap do |column|
        column.fixed_width = 85
      end
    end

    def time_column
      @time_column ||= Gtk::ColumnViewColumn.new(_('Time'), nil).tap do |column|
        column.expand = true
        column.fixed_width = 0
      end
    end

    def player_column
      @player_column ||= Gtk::ColumnViewColumn.new(_('Player'), nil).tap do |column|
        column.expand = true
        column.fixed_width = 0
      end
    end

    def bottom_bar
      @bottom_bar ||= Gtk::CenterBox.new.tap do |bar|
        bar.hexpand = true
        bar.add_css_class('toolbar')
      end
    end

    def new_game_button
      @new_game_button ||= Gtk::Button.new(label: _('_New Game')).tap do |button|
        button.action_name = 'app.new-game'
        button.can_shrink = true
        button.use_underline = true
        button.add_css_class('pill')
        button.add_css_class('suggested-action')
      end
    end

    def quit_button
      @quit_button ||= Gtk::Button.new.tap do |button|
        button.action_name = 'app.quit'
        button.valign = :center
        button.child = Adwaita::ButtonContent.new.tap do |content|
          content.icon_name = 'application-exit-symbolic'
          content.label = _('_Quit')
          content.can_shrink = true
          content.use_underline = true
        end
      end
    end

    private

      # A win reveals the New Game / Quit bar and pins the header to the
      # layout that was just finished.
      def show_completed_entry
        if @completed_entry.nil?
          dialog.focus_widget = layout_dropdown
        else
          clear_scores_button.visible = false
          toolbar_view.reveal_bottom_bars = true
          header_stack.visible_child_name = 'title'
          title_widget.subtitle =
            format(_('Layout: %s'), @maps.get_map_display_name(@completed_entry.name))
          dialog.focus_widget = score_view
        end
      end

      def set_up_layout_dropdown
        layout_dropdown.first_child&.has_frame = false
        layout_dropdown.last_child&.halign = :center
      end

      def set_up_layout_menu
        @maps.each { |map| add_layout(map.score_name) }
        @history.each { |entry| add_layout(entry.name) }

        selected = @selected_layout
        unless @completed_entry.nil?
          selected = @completed_entry.name
        end
        if selected.empty? && layout_model.n_items.positive?
          selected = layout_model.get_string(0)
        end

        layout_dropdown.selected = layout_position(@maps.get_map_display_name(selected))
        layout_dropdown.signal_connect('notify::selected') { layout_selected }
        layout_selected
      end

      def add_layout(score_name)
        display_name = @maps.get_map_display_name(score_name)
        if layout_position(display_name).nil?
          layout_model.append(display_name)
        end
      end

      def layout_position(display_name)
        (0...layout_model.n_items).find { |i| layout_model.get_string(i) == display_name }
      end

      def set_up_score_view
        set_up_rank_column
        set_up_time_column
        set_up_player_column

        score_view.tap do |view|
          view.append_column(rank_column)
          view.append_column(time_column)
          view.append_column(player_column)
          view.model = Gtk::NoSelection.new(Gtk::SortListModel.new(score_model, view.sorter))
          view.sort_by_column(rank_column, :ascending)

          view.sorter.signal_connect('changed') do
            # Re-sorting moves the top row; follow it.
            view.scroll_to(
              0,
              nil,
              Gtk::ListScrollFlags::FOCUS,
              nil,
            )
          end
        end

        unless @completed_entry.nil?
          focus_completed_entry
        end
      end

      def focus_completed_entry
        Gtk::EventControllerFocus.new.tap do |controller|
          controller.signal_connect('enter') do
            GLib::Idle.add do
              score_view.scroll_to(
                @completed_entry.rank - 1,
                nil,
                Gtk::ListScrollFlags::FOCUS,
                nil,
              )
              @player_entry&.grab_focus
              false
            end
          end
          score_view.add_controller(controller)
        end
      end

      def sorter(*comparators)
        Gtk::MultiSorter.new.tap do |multi|
          comparators.each do |comparator|
            Gtk::CustomSorter.new(&comparator).tap do |custom|
              @sorters << custom
              multi.append(custom)
            end
          end
          @sorters << multi
        end
      end

      def by_time = ->(a, b) { a.duration <=> b.duration }
      def by_player = ->(a, b) { a.player <=> b.player }
      def by_date = ->(a, b) { b.date <=> a.date }

      def set_up_rank_column
        rank_column.factory = inscription_factory(%w[caption numeric]) { |entry| entry.rank.to_s }
        rank_column.sorter = sorter(by_time, by_date, by_player)
      end

      def set_up_time_column
        time_column.factory =
          inscription_factory(%w[numeric], highlight_completed: true) { |entry| time_label(entry) }
        # Time and Rank are the same ordering, so they share a sorter.
        time_column.sorter = rank_column.sorter
      end

      def time_label(entry)
        if entry.duration >= 60
          "#{entry.duration / 60}m #{entry.duration % 60}s"
        else
          "#{entry.duration}s"
        end
      end

      def inscription_factory(css_classes, highlight_completed: false, &text_for)
        Gtk::SignalListItemFactory.new.tap do |factory|
          factory.signal_connect('setup') do |_factory, item|
            item.child = Gtk::Inscription.new(nil).tap do |inscription|
              css_classes.each { |css_class| inscription.add_css_class(css_class) }
            end
          end
          factory.signal_connect('bind') do |_factory, item|
            if highlight_completed && item.item.equal?(@completed_entry)
              item.child.add_css_class('heading')
            end
            item.child.text = text_for.call(item.item)
          end
        end
      end

      # The player column is a stack: a label for every row, plus an entry for
      # the row just completed so the winner can type their name.
      def set_up_player_column
        player_column.factory = player_factory
        player_column.sorter = sorter(by_player, by_time, by_date)
      end

      def player_factory
        Gtk::SignalListItemFactory.new.tap do |factory|
          factory.signal_connect('setup') { |_factory, item| item.child = player_cell }
          factory.signal_connect('bind') { |_factory, item| bind_player_cell(item) }
          factory.signal_connect('unbind') { |_factory, item| unbind_player_cell(item) }
        end
      end

      def player_cell
        Gtk::Stack.new.tap do |stack|
          stack.add_named(
            Gtk::Inscription.new(nil).tap do |inscription|
              inscription.text_overflow = :ellipsize_end
              inscription.valign = :center
            end,
            'label',
          )

          unless @completed_entry.nil?
            stack.add_named(player_input, 'entry')
          end
        end
      end

      def player_input
        Gtk::Entry.new.tap do |entry|
          entry.has_frame = false
          entry.max_width_chars = 5
          entry.add_css_class('heading')
          entry.signal_connect('notify::text') { rename_winner(entry) }
          entry.signal_connect('activate') { new_game_button.activate }
        end
      end

      def rename_winner(entry)
        unless @completed_entry.nil?
          if entry.text.empty?
            @completed_entry.player = History.real_name
          else
            @completed_entry.player = entry.text
          end
        end
      end

      def bind_player_cell(item)
        if item.item.equal?(@completed_entry)
          item.child.visible_child_name = 'entry'
          @player_entry = item.child.visible_child
          @player_entry.text = item.item.player
        else
          item.child.visible_child_name = 'label'
          item.child.visible_child.text = item.item.player
          item.child.visible_child.tooltip_text =
            "#{item.item.player}\n#{item.item.date.strftime('%x')}"
        end
      end

      def unbind_player_cell(item)
        if item.item.equal?(@completed_entry)
          @player_entry = nil
        end
      end

      # Rank is per layout, so it is recomputed every time the picker moves.
      def layout_selected
        selected_name = layout_dropdown.selected_item&.string

        # Fastest first, then most recent, then by name — the same ordering
        # the Rank column sorts by.
        entries = @history
          .select { |entry| @maps.get_map_display_name(entry.name) == selected_name }
          .sort_by { |entry| [entry.duration, -entry.date.to_f, entry.player] }
        entries.each_with_index { |entry, index| entry.rank = index + 1 }

        score_model.splice(0, score_model.n_items, entries)

        if score_model.n_items.positive?
          content_stack.visible_child_name = 'scores'
          score_view.scroll_to(
            0,
            nil,
            Gtk::ListScrollFlags::FOCUS,
            nil,
          )
        else
          content_stack.visible_child_name = 'no-scores'
        end
      end

      def confirm_clear_scores
        Adwaita::AlertDialog.new(
          _('Clear All Scores?'),
          _('This will clear every score for every layout.'),
        )
          .tap do |alert|
            alert.add_response('cancel', _('_Cancel'))
            alert.add_response('clear', _('Clear All'))
            alert.set_response_appearance('clear', Adwaita::ResponseAppearance::DESTRUCTIVE)
            alert.default_response = 'cancel'
            alert.signal_connect('response') do |_alert, response|
              if response == 'clear'
                clear_scores
              end
            end
            alert.present(dialog)
          end
      end

      def clear_scores
        toolbar_view.reveal_bottom_bars = false
        content_stack.visible_child_name = 'no-scores'
        clear_scores_button.sensitive = false
        score_model.remove_all
        @completed_entry = nil
        @history.clear
      end

      def save_edited_name
        unless @completed_entry.nil?
          @history.save
        end
      end
  end
end
