# frozen_string_literal: true

require 'gtk4'
require 'rsvg2'

module Mahjongg
  # The board. Tiles are cut out of a single SVG sprite sheet — 43 faces
  # across, two rows deep (plain on top, highlighted underneath) — which is
  # re-rendered whenever the tile size changes so the artwork stays crisp.
  #
  # Upstream is a Gtk.Widget subclass with a `snapshot` override that pushes
  # the sheet through a Gsk texture node, and falls back to Cairo when
  # GSK_RENDERER=cairo. Registering a Ruby GType to override `snapshot` buys
  # nothing here, so this is the Cairo path in a Gtk::DrawingArea.
  class GameView
    THEME_COLUMNS = 43
    THEME_ROWS = 2
    BLANK_TILE_COLUMN = 42

    TILE_SHAKE_DURATION_MS = 250
    TILE_SHAKE_FREQUENCY = 6
    MIN_TILE_SHAKE_AMPLITUDE = 3
    TILE_SHAKE_SCALE_FACTOR = 0.04

    attr_reader :game,
      :theme_handle,
      :theme_surface,
      :initial_theme_width,
      :initial_theme_height,
      :loaded_theme_width,
      :loaded_theme_height,
      :tile_width,
      :tile_height,
      :tile_pattern_width,
      :tile_pattern_height

    def initialize
      @x_offset = 0
      @y_offset = 0
      @tile_width = 0
      @tile_height = 0
      @tile_layer_offset_x = 0
      @tile_layer_offset_y = 0
      @tile_pattern_width = 0
      @tile_pattern_height = 0
      @rendered_theme_width = 0
      @rendered_theme_height = 0
      @initial_theme_width = 0
      @initial_theme_height = 0
      @loaded_theme_width = 0
      @loaded_theme_height = 0
      @theme_aspect = 1.0
      @using_vector = false
      @tick_id = nil
    end

    def build
      area.tap do |a|
        a.set_draw_func { |_widget, context, _width, _height| draw(context) }

        click_controller.tap do |controller|
          controller.signal_connect('pressed') do |_controller, n_press, x, y|
            click(n_press, x, y)
          end
        end
        a.add_controller(click_controller)
      end
    end

    def widget = area

    def game=(value)
      remove_tick_callback

      @game = value
      unless value.nil?
        value.on(:redraw_tile) { |tile| redraw_tile(tile) }
        value.on(:paused_changed) { area.queue_draw }
        update_dimensions
        resize_theme
        area.queue_draw
      end
    end

    # `source_view` shares an already-loaded sheet with the outgoing view, so
    # switching layouts does not re-parse and re-render the SVG.
    def set_theme(theme_path, source_view = nil, fallback_path = nil)
      @theme_surface = nil

      if theme_path.nil?
        @theme_handle = nil
      else
        adopt_theme(theme_path, source_view, fallback_path)
        resize_theme
      end
    end

    def area
      @area ||= Gtk::DrawingArea.new.tap do |a|
        a.hexpand = true
        a.vexpand = true
      end
    end

    def click_controller = @click_controller ||= Gtk::GestureClick.new

    # The topmost visible tile under a point, or nil. Tiles are in draw order,
    # so the last hit wins.
    def find_tile(x, y)
      @game.tiles.select { |tile| tile.visible && covers?(tile, x, y) }.last
    end

    # The centre of a tile in view coordinates.
    def tile_centre(tile)
      x, y = tile_position(tile)
      [x + (@tile_pattern_width / 2), y + (@tile_pattern_height / 2)]
    end

    # The gesture handler, called directly by the tests so the same path runs.
    def click(n_press, x, y)
      unless @game.nil? || click_blocked?
        handle_click(n_press, x, y)
      end
    end

    def draw(context)
      unless @game.nil?
        # The first frame is what tells us how big the board is, so the sheet
        # cannot be rendered before it: measure, render, and paint whatever we
        # have — `resize_theme` queues another frame once the sheet is ready.
        update_dimensions
        resize_theme

        unless @theme_surface.nil?
          paint(context)
        end
      end
    end

    private

      def adopt_theme(theme_path, source_view, fallback_path)
        if source_view.nil?
          load_theme(theme_path, fallback_path)
        else
          @theme_handle = source_view.theme_handle
          @theme_surface = source_view.theme_surface
          @initial_theme_width = source_view.initial_theme_width
          @initial_theme_height = source_view.initial_theme_height
          @loaded_theme_width = source_view.loaded_theme_width
          @loaded_theme_height = source_view.loaded_theme_height
        end

        # Only the vector theme may be scaled past its natural size.
        @using_vector = theme_path.end_with?('postmodern.svg')
        @theme_aspect = (@initial_theme_height / 2.0) / (@initial_theme_width / THEME_COLUMNS.to_f)
        @theme = theme_path
      end

      def load_theme(theme_path, fallback_path)
        @theme_handle = open_handle(theme_path, fallback_path)
        unless @theme_handle.nil?
          @initial_theme_width, @initial_theme_height =
            @theme_handle.intrinsic_size_in_pixels[1, 2].map(&:to_i)
          @loaded_theme_width = 0
          @loaded_theme_height = 0
        end
      end

      def open_handle(theme_path, fallback_path)
        RSVG::Handle.new(file: theme_path)
      rescue StandardError => e
        warn "Could not load theme #{theme_path}: #{e.message}"
        begin
          RSVG::Handle.new(file: fallback_path)
        rescue StandardError
          nil
        end
      end

      # Pick a rendering size for the sheet: a clean fraction of its natural
      # size when the tiles are small, a whole multiple of it when they are
      # large. Snapping to those steps keeps the re-render off the resize path.
      def theme_size
        width = 0
        height = 0

        [8, 4, 2].each do |factor|
          scaled_width = @initial_theme_width / factor
          if width.zero? && @rendered_theme_width < scaled_width
            width = scaled_width
            height = @initial_theme_height / factor
          end
        end

        if width.zero?
          while width < @rendered_theme_width
            if !@using_vector && width > @initial_theme_width
              width = @initial_theme_width
              height = @initial_theme_height
              break
            end
            width += @initial_theme_width
            height += @initial_theme_height
          end
        end

        # Finally, honour the display's scale factor so the sheet is sharp on
        # a HiDPI screen.
        [width * surface_scale, height * surface_scale]
      end

      def surface_scale = area.native&.surface&.scale || 1

      def resize_theme
        unless @game.nil? || @theme.nil? || @rendered_theme_width.zero?
          new_width, new_height = theme_size.map(&:to_i)

          # Re-rendering is the expensive part; skip it when nothing moved.
          unless new_width == @loaded_theme_width || new_width.zero?
            render_theme(new_width, new_height)
          end
        end
      end

      def render_theme(new_width, new_height)
        @loaded_theme_width = new_width
        @loaded_theme_height = new_height

        @theme_surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32, new_width, new_height)
        rectangle = RSVG::Rectangle.new
        rectangle.x = 0.0
        rectangle.y = 0.0
        rectangle.width = new_width.to_f
        rectangle.height = new_height.to_f
        @theme_handle.render_document(Cairo::Context.new(@theme_surface), rectangle)
        area.queue_draw
      rescue StandardError => e
        @theme_surface = nil
        warn "Could not render theme #{@theme}: #{e.message}"
      end

      def paint(context)
        # The sheet is rendered at `loaded` pixels but laid out as though it
        # were `rendered` pixels, so one cell lands exactly on one tile.
        scale = @rendered_theme_width.to_f / @loaded_theme_width

        @game.tiles.each do |tile|
          if tile.visible
            paint_tile(context, tile, scale)
          end
        end
      end

      def paint_tile(context, tile, scale)
        # A paused board shows the backs of the tiles.
        if @game.paused?
          number = -1
        else
          number = tile.number
        end
        texture_x = image_offset(number) * @tile_pattern_width
        if tile.highlighted
          texture_y = @tile_pattern_height
        else
          texture_y = 0
        end
        x, y = tile_position(tile)

        if tile.shaking
          x += tile.shake_offset
        end

        context.save do
          context.rectangle(
            x,
            y,
            @tile_pattern_width,
            @tile_pattern_height,
          )
          context.clip
          context.translate(x - texture_x, y - texture_y)
          context.scale(scale, scale)
          context.set_source(@theme_surface, 0, 0)
          context.source.filter = Cairo::FILTER_BILINEAR # Faster than the default
          context.paint
        end
      end

      def update_dimensions
        unless @theme.nil?
          width = area.width
          height = area.height

          # Shrink the border on a small (mobile) window.
          h_border = width / 220.0
          v_border = height / 560.0
          map_width = @game.map.width + (@game.map.h_overhang / 4) + h_border
          map_height = (@game.map.height + (@game.map.v_overhang / 4) + v_border) * @theme_aspect

          # Scale the layout to fit.
          unit_width = [width / map_width, height / map_height].min.to_i
          unit_height = (unit_width * @theme_aspect).to_i

          # A tile is two units wide, at the sheet's aspect ratio.
          @tile_width = unit_width * 2
          @tile_height = unit_height * 2

          # Tiles on a higher layer are offset up and to the right; the themes
          # are drawn to these fixed ratios.
          @tile_layer_offset_x = @tile_width / 7
          @tile_layer_offset_y = @tile_height / 10

          @x_offset = ((width - ((@game.map.width + (@game.map.h_overhang / 4)) * unit_width)) / 2.0).to_i
          @y_offset = ((height - ((@game.map.height * unit_height) -
                                  ((@game.map.v_overhang * unit_height) / 8))) / 2.0).to_i

          # The images are bigger than the tile itself: they carry the
          # isometric extension along the z axis.
          @tile_pattern_width = @tile_width + @tile_layer_offset_x
          @tile_pattern_height = @tile_height + @tile_layer_offset_y

          @rendered_theme_width = @tile_pattern_width * THEME_COLUMNS
          @rendered_theme_height = @tile_pattern_height * THEME_ROWS
        end
      end

      def tile_position(tile)
        [
          @x_offset + (tile.slot.x * @tile_width / 2) + (tile.slot.layer * @tile_layer_offset_x),
          @y_offset + (tile.slot.y * @tile_height / 2) - (tile.slot.layer * @tile_layer_offset_y),
        ]
      end

      def covers?(tile, x, y)
        tile_x, tile_y = tile_position(tile)
        x >= tile_x && x <= tile_x + @tile_pattern_width &&
          y >= tile_y && y <= tile_y + @tile_pattern_height
      end

      # Which column of the sheet shows this tile's face.
      def image_offset(number)
        set = number / 4

        if number.negative? || set >= 36
          BLANK_TILE_COLUMN
        elsif set == 33
          # The two bonus sets have a different image per tile...
          33 + (number % 4)
        elsif set == 35
          38 + (number % 4)
        elsif set == 34
          # ...and the white dragons sit between them, just to be confusing.
          37
        else
          set
        end
      end

      def redraw_tile(tile)
        if tile.shaking && @tick_id.nil?
          @tick_id = area.add_tick_callback { |_widget, clock| shake_step(clock) }
        end
        area.queue_draw
      end

      def shake_step(clock)
        animating = false

        @game.tiles.each do |tile|
          if tile.shaking
            elapsed_ms = (clock.frame_time - tile.shake_start_time) / 1000.0

            if elapsed_ms > TILE_SHAKE_DURATION_MS
              tile.shaking = false
              tile.shake_offset = 0
              tile.shake_start_time = 0.0
            else
              amplitude = [MIN_TILE_SHAKE_AMPLITUDE, @tile_width * TILE_SHAKE_SCALE_FACTOR].max
              tile.shake_offset =
                (amplitude * Math.sin(2 * Math::PI * TILE_SHAKE_FREQUENCY * (elapsed_ms / 1000.0))).to_i
              animating = true
            end
          end
        end

        unless animating
          @tick_id = nil
        end

        area.queue_draw
        animating
      end

      def remove_tick_callback
        unless @tick_id.nil?
          area.remove_tick_callback(@tick_id)
          @tick_id = nil
        end
      end

      def click_blocked?
        # A click on a paused board just resumes it; the application answers
        # :attempt_move to say so.
        @game.inspecting? || @game.emit(:attempt_move).include?(false) || @game.paused?
      end

      def handle_click(n_press, x, y)
        tile = find_tile(x, y)

        if tile.nil?
          # Double-clicking the background when nothing is blocked any more
          # plays the rest of the game out.
          if n_press == 2 && @game.all_tiles_unblocked?
            @game.autoplay_end_game
          end
        elsif !tile.selectable?
          @game.shake_tile(tile, area.frame_clock.frame_time)
        else
          select_tile(tile)
        end

        area.queue_draw
      end

      def select_tile(tile)
        if @game.selected_tile.nil?
          @game.selected_tile = tile
        elsif tile.equal?(@game.selected_tile)
          # Clicking the selected tile again puts it back down.
          @game.selected_tile = nil
        elsif tile.matches?(@game.selected_tile)
          @game.remove_pair(@game.selected_tile, tile)
        else
          @game.selected_tile = tile
        end
      end
  end
end
