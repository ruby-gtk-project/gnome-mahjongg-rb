# frozen_string_literal: true

require 'rexml/document'

require_relative 'i18n'

module Mahjongg
  # A tile position. Coordinates are in half-tiles: a tile is 2x2 units, so
  # neighbouring tiles on the same layer differ by 2 in x or y.
  class Slot
    attr_reader :x, :y, :layer

    def initialize(x, y, layer)
      @x = x
      @y = y
      @layer = layer
    end

    def equals(other)
      x == other.x && y == other.y && layer == other.layer
    end
  end

  # One layout: a named collection of slots, kept in draw order (back to
  # front, so painting them in sequence gets the isometric overlap right).
  class Map
    attr_accessor :name, :score_name

    def initialize
      @slots = []
      @sorted = true
    end

    def slots
      unless @sorted
        # Upstream inserts each slot into a sorted GList. The comparator is a
        # total order, so sorting once on first read is equivalent and spares
        # the O(n^2) insertions.
        @slots.sort_by! { |slot| [slot.layer, slot.y - slot.x, slot.x] }
        @sorted = true
      end
      @slots
    end

    def add_slot(slot)
      @slots << slot
      @sorted = false
    end

    def get_slot(position)
      slots[position]
    end

    def n_slots = slots.length

    def each(&) = slots.each(&)

    include Enumerable

    def width
      compute_extents
      @width
    end

    def height
      compute_extents
      @height
    end

    # How far the top layer juts out to the right of the base layer, in
    # eighths of a tile: each layer is offset by tile_width / 7 horizontally.
    def h_overhang
      compute_extents
      @h_overhang
    end

    # The same, upwards.
    def v_overhang
      compute_extents
      @v_overhang
    end

    private

      def compute_extents
        unless @width
          x = 0
          h_layer = 0
          slots.each do |slot|
            if slot.x >= x && slot.layer >= h_layer
              x = slot.x
              h_layer = slot.layer
            end
          end

          y = 0
          v_layer = 0
          slots.each do |slot|
            if slot.y > y
              y = slot.y
            elsif slot.y.zero? && slot.layer > v_layer
              v_layer = slot.layer
            end
          end

          # Width and height are the far edge of the outermost tile, which
          # is itself two units wide.
          @h_overhang = h_layer
          @width = x + 2
          @v_overhang = v_layer
          @height = y + 2
        end
      end
  end

  # The layout catalogue, parsed from data/maps/mahjongg.map.
  class Maps
    include Enumerable
    include I18n

    def initialize
      @maps = []
    end

    def n_maps = @maps.length

    def each(&) = @maps.each(&)

    def load(path = Paths.data_file('maps/mahjongg.map'))
      REXML::Document.new(File.read(path)).each_element('//map') do |element|
        parse_map(element)
      end
      true
    rescue StandardError => e
      warn "Could not load map #{path}: #{e.message}"
      false
    end

    def get_map_by_name(name)
      @maps.find { |map| map.name == name }
    end

    def get_map_at_position(position)
      if position.negative? || position >= n_maps
        nil
      else
        @maps[position]
      end
    end

    def get_next_map(map)
      get_map_at_position((@maps.index(map).to_i + 1) % n_maps)
    end

    def get_random_map
      get_map_at_position(rand(n_maps))
    end

    # Scores are filed under the layout's stable score name; the menus and the
    # score dialog show the translated display name instead.
    def get_map_display_name(score_name)
      @maps.find { |map| map.score_name == score_name }.then do |map|
        if map.nil?
          score_name
        else
          p_('mahjongg map name', map.name)
        end
      end
    end

    private

      def parse_map(element)
        Map.new.tap do |map|
          map.name = element.attributes['name'].to_s
          map.score_name = element.attributes['scorename'].to_s

          element.each_element do |child|
            add_slots(map, child, 0)
          end

          if map.n_slots.positive? && map.n_slots <= 144 && (map.n_slots % 2).zero?
            @maps << map
          else
            warn "Invalid map #{map.name} with #{map.n_slots} slots"
          end
        end
      end

      def add_slots(map, element, layer_z)
        z = attr_i(element, 'z', layer_z)

        case element.name.downcase
        when 'layer'
          element.each_element { |child| add_slots(map, child, z) }
        when 'row'
          (attr_i(element, 'left')..attr_i(element, 'right')).step(2) do |x|
            map.add_slot(Slot.new(x, attr_i(element, 'y'), z))
          end
        when 'column'
          (attr_i(element, 'top')..attr_i(element, 'bottom')).step(2) do |y|
            map.add_slot(Slot.new(attr_i(element, 'x'), y, z))
          end
        when 'block'
          (attr_i(element, 'left')..attr_i(element, 'right')).step(2) do |x|
            (attr_i(element, 'top')..attr_i(element, 'bottom')).step(2) do |y|
              map.add_slot(Slot.new(x, y, z))
            end
          end
        when 'tile'
          map.add_slot(Slot.new(attr_i(element, 'x'), attr_i(element, 'y'), z))
        end
      end

      # Coordinates are written in tiles and may be fractional ("y=3.5" is the
      # half-tile offset the Turtle's tail sits on); slots count half-tiles, so
      # everything but z is doubled on the way in.
      def attr_i(element, name, default = 0)
        value = element.attributes[name]
        if value.nil?
          default
        elsif name == 'z'
          value.to_f.to_i
        else
          (value.to_f * 2).to_i
        end
      end
  end
end
