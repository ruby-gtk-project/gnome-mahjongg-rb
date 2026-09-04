# frozen_string_literal: true

require 'fileutils'
require 'rexml/document'

require_relative 'game'
require_relative 'map'

module Mahjongg
  # The in-progress game on disk. Only a game that is running, still has moves
  # and is not already won gets written, so quitting mid-game resumes and
  # quitting after a win does not.
  class GameSave
    attr_reader :map, :clock, :move, :seed, :tiles

    def initialize(filename)
      @filename = filename
      reset
    end

    def load(maps)
      if File.exist?(@filename)
        parse(maps)
      else
        false
      end
    end

    def write(game)
      if game.can_save?
        write_file(game)
      else
        false
      end
    end

    def delete
      if File.exist?(@filename)
        begin
          File.delete(@filename)
        rescue SystemCallError => e
          warn "Could not remove save file #{@filename}: #{e.message}"
        end
      end
      reset
    end

    private

      def parse(maps)
        document = REXML::Document.new(File.read(@filename))
        read_game(document)
        read_tiles(document)
        @map = maps.get_map_by_name(@map_name)

        if valid?(@map)
          true
        else
          warn "Saved layout '#{@map_name}' is not valid."
          reset
          false
        end
      rescue StandardError => e
        warn "Could not parse game save #{@filename}: #{e.message}"
        reset
        false
      end

      def read_game(document)
        document.each_element('//game') do |element|
          @map_name = element.attributes['map'].to_s
          @seed = attr_i(element, 'seed')
          @clock = element.attributes['clock'].to_f
          @move = attr_i(element, 'move')
        end
      end

      def read_tiles(document)
        document.each_element('//tile') do |element|
          slot = Slot.new(attr_i(element, 'x'), attr_i(element, 'y'), attr_i(element, 'z'))
          @tiles << Tile.new(slot).tap do |tile|
            tile.number = attr_i(element, 'number')
            tile.visible = element.attributes['visible'] == 'true'
            tile.move = attr_i(element, 'move')
          end
        end
      end

      def attr_i(element, name) = element.attributes[name].to_f.to_i

      def write_file(game)
        File.write(@filename, serialize(game))
        true
      rescue SystemCallError => e
        warn "Could not save game to #{@filename}: #{e.message}"
        false
      end

      def serialize(game)
        FileUtils.mkdir_p(File.dirname(@filename), mode: 0o775)

        lines = [
          format(
            %(<game map="%s" seed="%d" clock="%s" move="%d">),
            game.map.name,
            game.seed,
            game.elapsed,
            game.current_move,
          ),
          "\t<tiles>",
        ]

        game.each do |tile|
          lines << format(
            %(\t\t<tile number="%d" visible="%s" move="%d" z="%d" x="%d" y="%d"/>),
            tile.number,
            tile.visible,
            tile.move,
            tile.slot.layer,
            tile.slot.x,
            tile.slot.y,
          )
        end

        lines.push("\t</tiles>", '</game>', '').join("\n")
      end

      # A save only applies to the layout it was taken from: every slot in the
      # map has to be accounted for in the file.
      def valid?(map)
        if map.nil?
          false
        else
          map.n_slots == map.count { |slot| @tiles.any? { |tile| slot.equals(tile.slot) } }
        end
      end

      def reset
        @map = nil
        @map_name = ''
        @clock = 0.0
        @move = 0
        @seed = 0
        @tiles = []
      end
  end
end
