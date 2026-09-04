# frozen_string_literal: true

require 'gtk4'

module Mahjongg
  # The card that slides up over a paused board. A restored game gets Restart
  # rather than Quit, since the player has just come back to it.
  class PauseOverlay
    def build
      container.tap do |box|
        box.append(revealer)

        revealer.tap do |rev|
          rev.child = content_box

          content_box.tap do |content|
            content.append(title_label)
            content.append(button_box)

            button_box.tap do |buttons|
              buttons.append(resume_button)
              buttons.append(restart_button)
              buttons.append(quit_button)
            end
          end
        end
      end
    end

    def widget = container

    def show(resuming_game = false)
      quit_button.visible = !resuming_game
      restart_button.visible = resuming_game
      container.visible = true
      revealer.reveal_child = true
      resume_button.grab_focus
    end

    def hide
      container.visible = false
      revealer.reveal_child = false
    end

    def visible? = container.visible?

    def container
      @container ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.halign = :center
        box.valign = :center
        box.visible = false
        box.add_css_class('osd')
        box.add_css_class('pause-overlay')
        box.add_css_class('toolbar')
      end
    end

    def revealer
      @revealer ||= Gtk::Revealer.new.tap do |rev|
        rev.transition_duration = 200
        rev.transition_type = :slide_up
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 24).tap do |box|
        box.margin_top = 18
        box.margin_bottom = 18
        box.margin_start = 18
        box.margin_end = 18
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new('Paused').tap do |label|
        label.add_css_class('title-1')
      end
    end

    def button_box
      @button_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.halign = :center
      end
    end

    def resume_button
      @resume_button ||= Gtk::Button.new(label: 'Re_sume Game').tap do |button|
        button.action_name = 'app.pause'
        button.use_underline = true
        button.add_css_class('pill')
        button.add_css_class('suggested-action')
      end
    end

    def restart_button
      @restart_button ||= Gtk::Button.new(label: '_Restart Game').tap do |button|
        button.action_name = 'app.restart-game'
        button.use_underline = true
        button.add_css_class('pill')
      end
    end

    def quit_button
      @quit_button ||= Gtk::Button.new(label: '_Quit').tap do |button|
        button.action_name = 'app.quit'
        button.use_underline = true
        button.add_css_class('pill')
        button.add_css_class('destructive-action')
      end
    end
  end
end
