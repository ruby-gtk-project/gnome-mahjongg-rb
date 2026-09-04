# frozen_string_literal: true

require 'adwaita'

require_relative 'version'

module Mahjongg
  # Upstream builds this with `Adw.AboutDialog.from_appdata`, which reads the
  # metainfo out of the GResource bundle. The Ruby bindings expose no such
  # constructor, so the same fields are set by hand.
  class AboutDialog
    DEVELOPERS = [
      'Francisco Bustamante',
      'Max Watson',
      'Heinz Hempe',
      'Michael Meeks',
      'Philippe Chavin',
      'Callum McKenzie',
      'Robert Ancell',
      'Michael Catanzaro',
      'Mario Wenzel',
      'Arnaud Bonatti',
      'Jeremy Bicha',
      'Alberto Ruiz',
      'Günther Wagner',
      'Mathias Bonn',
      'K Davis',
      'François Godin',
    ].freeze

    ARTISTS = [
      'Jonathan Buzzard',
      'Jaye Evins',
      'Richard Hoelscher',
      'Gonzalo Odiard',
      'Max Watson',
      'Jakub Steiner',
      'Rossano Rossi',
      'Tobias Bernard',
    ].freeze

    DOCUMENTERS = [
      'Tiffany Antopolski',
      'Chris Beiser',
      'Andre Klapper',
    ].freeze

    LAYOUT_AUTHORS = [
      'Rexford Newbould',
      'Krzysztof Foltman',
      'Sapphire Becker',
    ].freeze

    COPYRIGHT = "Copyright © 1998–2026 Mahjongg Contributors\n" \
                'Copyright © 1998–2008 Free Software Foundation, Inc.'

    def build
      dialog.tap do |about|
        about.add_credit_section('Layouts by', LAYOUT_AUTHORS)
      end
    end

    def dialog
      @dialog ||= Adwaita::AboutDialog.new.tap do |about|
        about.application_name = 'Mahjongg'
        about.application_icon = Application::APP_ID
        about.developer_name = 'The Mahjongg Team'
        about.version = VERSION
        about.copyright = COPYRIGHT
        about.license_type = Gtk::License::GPL_2_0
        about.comments = 'Match tiles and clear the board'
        about.website = 'https://apps.gnome.org/Mahjongg/'
        about.issue_url = 'https://gitlab.gnome.org/GNOME/gnome-mahjongg/issues'
        about.developers = DEVELOPERS
        about.artists = ARTISTS
        about.documenters = DOCUMENTERS
      end
    end
  end
end
