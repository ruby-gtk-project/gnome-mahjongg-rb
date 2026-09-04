# frozen_string_literal: true

require 'etc'
require 'fileutils'
require 'glib2'
require 'time'

module Mahjongg
  # One completed game. `name` is the layout's score name, `rank` is filled in
  # by the score dialog when it sorts a layout's entries.
  #
  # A GLib::Object because the score dialog puts these straight into a
  # Gio::ListStore, which only takes GObjects.
  class HistoryEntry < GLib::Object
    type_register

    attr_reader :date, :name, :duration
    attr_accessor :player, :rank

    def initialize(date, name, duration, player)
      super()
      @date = date
      @name = name
      @duration = duration
      @player = player
      @rank = 0
    end
  end

  # The score file: one completed game per line, oldest first.
  class History
    include Enumerable

    attr_reader :filename

    def initialize(filename)
      @filename = filename
      @entries = []
    end

    def length = @entries.length

    def each(&) = @entries.each(&)

    def load
      @entries = []
      if File.exist?(@filename)
        read_entries
      end
    rescue SystemCallError => e
      warn "Failed to load history: #{e.message}"
    end

    def save
      FileUtils.mkdir_p(File.dirname(@filename), mode: 0o775)
      File.write(@filename, @entries.map { |entry| line_for(entry) }.join)
    rescue SystemCallError => e
      warn "Failed to save history: #{e.message}"
    end

    def add(date, name, duration, player)
      HistoryEntry.new(
        date,
        name,
        duration,
        player,
      ).tap do |entry|
        @entries << entry
        save
      end
    end

    def clear
      @entries = []
      save
    end

    # The player's name as the desktop knows it, used when a score line
    # predates the player column and as the fallback for an empty name field.
    def self.real_name
      Etc.getpwnam(Etc.getlogin || ENV.fetch('USER', 'player')).gecos.split(',').first.to_s
    rescue StandardError
      ''
    end

    private

      def read_entries
        File.read(@filename).split("\n").each do |line|
          tokens = line.split(' ', 4)
          unless tokens.length < 3
            add_parsed(tokens)
          end
        end
      end

      def add_parsed(tokens)
        date = Time.iso8601(tokens[0])
        player = tokens[3]
        if player.nil?
          player = History.real_name
        end
        @entries << HistoryEntry.new(
          date,
          tokens[1],
          tokens[2].to_i,
          player,
        )
      rescue ArgumentError
        # A line with an unreadable date is skipped, as upstream does.
        nil
      end

      def line_for(entry)
        "#{entry.date.iso8601} #{entry.name} #{entry.duration} #{entry.player}\n"
      end
  end
end
