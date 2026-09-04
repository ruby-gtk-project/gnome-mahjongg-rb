# frozen_string_literal: true

require 'glib2'

require_relative 'signals'

module Mahjongg
  # A wall clock that can be paused, matching GLib.Timer's semantics.
  class Timer
    def initialize
      @started_at = monotonic
      @accumulated = 0.0
      @active = true
    end

    def active? = @active

    def elapsed
      if @active
        @accumulated + (monotonic - @started_at)
      else
        @accumulated
      end
    end

    def stop
      if @active
        @accumulated += monotonic - @started_at
        @active = false
      end
    end

    def continue
      unless @active
        @started_at = monotonic
        @active = true
      end
    end

    private

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # One tile on the board. `number` is its face: tiles 4n..4n+3 all show face
  # n, so any two tiles whose numbers share a quotient of 4 are a match.
  class Tile
    attr_reader :slot
    attr_accessor :number,
      :visible,
      :highlighted,
      :move,
      :shaking,
      :shake_offset,
      :shake_start_time

    def initialize(slot)
      @slot = slot
      @number = -1
      @visible = true
      @highlighted = false
      @move = 0
      @shaking = false
      @shake_offset = 0
      @shake_start_time = 0.0
      @left = []
      @right = []
      @above = []
    end

    def add_tile_left(tile) = @left << tile
    def add_tile_right(tile) = @right << tile
    def add_tile_above(tile) = @above << tile

    # A tile can be picked up when nothing sits on top of it and at least one
    # of its long edges is clear.
    def selectable?
      if !@visible || @above.any?(&:visible)
        false
      else
        !(@left.any?(&:visible) && @right.any?(&:visible))
      end
    end

    def matches?(tile) = number / 4 == tile.number / 4
  end

  # A pair of tiles that can legally be removed together.
  Match = Struct.new(:tile0, :tile1)

  # The board and the rules. Emits :attempt_move, :redraw_tile, :moved,
  # :paused_changed and :tick.
  class Game
    include Signals

    HINT_PENALTY_SECONDS = 30.0
    SHUFFLE_PENALTY_SECONDS = 60.0

    attr_reader :map, :seed, :current_move, :tiles

    def initialize(map)
      @map = map
      @tiles = []
      @seed = -1
      @current_move = 0
      @clock_elapsed = 0.0
      @clock = nil
      @clock_timeout = nil
      @hint_match = nil
      @hint_matches = []
      @hint_match_index = 0
      @hint_timeout = nil
      @hint_blink_counter = 0
      @autoplay_timeout = nil
      @inspecting = false
      @paused = false
      @selected_tile = nil
      @random = Random.new(0)
      create_tiles
    end

    # Deliberately not Enumerable: `Game#map` is the layout, and including it
    # would shadow that with `Enumerable#map`. Iterate `game.tiles` instead.
    def each(&) = @tiles.each(&)

    def n_tiles = @tiles.length

    def get_tile(position)
      if position.negative? || position >= n_tiles
        nil
      else
        @tiles[position]
      end
    end

    def started? = !@clock.nil?

    def inspecting? = @inspecting

    def paused? = @paused

    def elapsed
      if @clock.nil?
        0.0
      else
        @clock_elapsed + @clock.elapsed
      end
    end

    def moves_left = find_matches.length

    def complete? = @tiles.none?(&:visible)

    def can_move? = !moves_left.zero?

    def can_shuffle? = @tiles.count(&:selectable?) >= 2

    def can_undo? = @current_move > 1

    def can_redo? = @tiles.any? { |tile| tile.move >= @current_move }

    def can_save? = started? && can_move? && !inspecting?

    def all_tiles_unblocked? = @tiles.none? { |tile| tile.visible && !tile.selectable? }

    attr_reader :selected_tile

    def selected_tile=(tile)
      unless @selected_tile.nil?
        @selected_tile.highlighted = false
        emit(:redraw_tile, @selected_tile)
      end

      @selected_tile = tile
      unless @selected_tile.nil?
        @selected_tile.highlighted = true
        emit(:redraw_tile, @selected_tile)
      end

      # Hint matches depend on what is selected, so they no longer apply.
      @hint_matches = []
    end

    def paused=(value)
      if value != @paused && started? && !inspecting? && !complete?
        @paused = value
        unless @clock.nil?
          if value
            stop_clock
          else
            continue_clock
          end
        end
        self.selected_tile = nil
        set_hint(nil)
        emit(:paused_changed)
      end
    end

    # Start with a board of blank tiles, then repeatedly pick a random legal
    # match and take it off, backtracking whenever the remainder is unsolvable.
    # The order the pairs come off in is a guaranteed path to victory; faces
    # are assigned to each pair on the way back out of the recursion.
    def generate(seed = -1)
      if seed == -1
        @seed = rand(2**31 - 1)
      else
        @seed = seed
      end
      pair_numbers = Array.new(n_tiles / 2) { |i| i * 2 }

      @paused = false
      emit(:paused_changed) # Always emitted, so listeners re-sync
      reset_clock
      self.selected_tile = nil
      set_hint(nil)
      @current_move = 1
      @inspecting = false

      @random = Random.new(@seed)
      choose_tile_pairs(shuffle_pair_numbers(pair_numbers))

      # The solver has "finished" the game; hand the board back to the player.
      @tiles.each do |tile|
        tile.visible = true
        tile.move = 0
      end
      redraw_all_tiles
      emit(:moved)
    end

    def restore(save)
      @seed = save.seed
      @current_move = save.move
      @random = Random.new(@seed)

      @tiles.each do |tile|
        saved = save.tiles.find { |t| tile.slot.equals(t.slot) }
        unless saved.nil?
          tile.number = saved.number
          tile.move = saved.move
          tile.visible = saved.visible
        end
      end

      @clock = Timer.new
      @clock.stop
      @clock_elapsed = save.clock
      emit(:tick)

      redraw_all_tiles
      emit(:moved)
      # A restored game opens paused, so the player is not on the clock before
      # they have looked at the board.
      self.paused = true
    end

    def restart
      @tiles.each do |tile|
        tile.number = -1
        tile.visible = true
      end
      generate(@seed)
    end

    def destroy_timers
      remove_hint_timeout
      remove_autoplay_timeout
      stop_clock
    end

    def shake_tile(tile, start_time)
      tile.shaking = true
      tile.shake_offset = 0
      tile.shake_start_time = start_time
      emit(:redraw_tile, tile)
    end

    def remove_pair(tile0, tile1)
      if !tile0.visible || !tile1.visible || tile0.equal?(tile1) || !tile0.matches?(tile1)
        false
      else
        take_pair(tile0, tile1)
        true
      end
    end

    # Re-deal the tiles still on the board into a fresh solvable arrangement,
    # for when the player has run out of moves.
    def shuffle_remaining
      if can_shuffle?
        removed_faces = []
        pair_numbers = []
        to_shuffle = []

        @current_move = 1

        @tiles.each do |tile|
          tile.move = 0
          if tile.visible
            to_shuffle << tile
          else
            removed_faces |= [tile.number / 4]
          end
        end

        to_shuffle.each do |tile|
          face = tile.number / 4
          pair_number = tile.number - (tile.number % 2)
          tile.number = -1

          # Two pairs share each face, so one tile from each of them may have
          # been matched off, leaving two half-pairs behind. Put whatever is
          # left of that face onto a single pair number.
          if removed_faces.include?(face)
            pair_number = face * 4
          end

          pair_numbers |= [pair_number]
        end

        choose_tile_pairs(shuffle_pair_numbers(pair_numbers))
        to_shuffle.each { |tile| tile.visible = true }

        emit(:moved)
        redraw_all_tiles

        start_clock
        @clock_elapsed += SHUFFLE_PENALTY_SECONDS
        emit(:tick)
      end
    end

    def undo
      if can_undo?
        self.selected_tile = nil
        set_hint(nil)

        @current_move -= 1
        @tiles.each do |tile|
          if tile.move == @current_move
            tile.visible = true
            emit(:redraw_tile, tile)
          end
        end
        emit(:moved)
      end
    end

    def redo
      if can_redo?
        self.selected_tile = nil
        set_hint(nil)

        @tiles.each do |tile|
          if tile.move == @current_move
            tile.visible = false
            emit(:redraw_tile, tile)
          end
        end
        @current_move += 1
        emit(:moved)
      end
    end

    # Cycle through the matches available for the current selection, so asking
    # twice in a row suggests something different.
    def next_hint
      if @hint_matches.empty?
        @hint_matches = find_matches_for_tile(@selected_tile)

        # Nothing matches the selection; suggest any pair instead.
        if @hint_matches.empty?
          @hint_matches = find_matches
        end

        unless @hint_matches.empty?
          @hint_match_index = @random.rand(@hint_matches.length)
        end
      end

      if @hint_matches.empty?
        nil
      else
        @hint_match_index = (@hint_match_index + 1) % @hint_matches.length
        @hint_matches[@hint_match_index]
      end
    end

    def show_hint = set_hint(next_hint)

    # Once nothing is blocked the rest is a formality, so a double-click on
    # the background plays it out.
    def autoplay_end_game
      if all_tiles_unblocked?
        @autoplay_timeout = GLib::Timeout.add(500) { autoplay_step }
        autoplay_step
      end
    end

    private

      def take_pair(tile0, tile1)
        self.selected_tile = nil
        set_hint(nil)

        # Making a move discards the redo queue.
        @tiles.each do |tile|
          if tile.move >= @current_move
            tile.move = 0
          end
        end

        [tile0, tile1].each do |tile|
          tile.visible = false
          tile.move = @current_move
        end

        @current_move += 1

        emit(:redraw_tile, tile0)
        emit(:redraw_tile, tile1)

        if complete?
          stop_clock
        else
          start_clock
        end

        emit(:moved)

        if complete?
          @inspecting = true
        end
      end

      # Work out, for every tile, which tiles could block it: the ones beside
      # it on the same layer and the ones resting on top of it.
      def create_tiles
        @tiles = @map.slots.map { |slot| Tile.new(slot) }

        @tiles.each do |tile|
          slot = tile.slot

          @tiles.each do |other|
            s = other.slot

            # Only tiles within one half-tile vertically can be in the way.
            unless other.equal?(tile) || s.y < slot.y - 1 || s.y > slot.y + 1
              if s.layer == slot.layer
                if s.x == slot.x - 2
                  tile.add_tile_left(other)
                end
                if s.x == slot.x + 2
                  tile.add_tile_right(other)
                end
              elsif s.layer > slot.layer && s.x >= slot.x - 1 && s.x <= slot.x + 1
                tile.add_tile_above(other)
              end
            end
          end
        end
      end

      def shuffle_pair_numbers(pair_numbers)
        pair_numbers.tap do |numbers|
          # Fisher-Yates, driven by the game's own seeded generator so a
          # restart reproduces the same board.
          numbers.each_index do |i|
            n = i + @random.rand(numbers.length - i)
            numbers[i], numbers[n] = numbers[n], numbers[i]
          end
        end
      end

      def choose_tile_pairs(pair_numbers, depth = 0, check_selectable = true)
        solved = false

        if depth == pair_numbers.length
          solved = true
        else
          matches = find_matches(check_selectable)
          n_matches = matches.length
          if n_matches.zero?
            n = 0
          else
            n = @random.rand(n_matches)
          end
          i = 0

          while i < n_matches && !solved
            match = matches[(n + i) % n_matches]
            match.tile0.visible = false
            match.tile1.visible = false

            if choose_tile_pairs(pair_numbers, depth + 1, check_selectable)
              match.tile0.number = pair_numbers[depth]
              match.tile1.number = pair_numbers[depth] + 1
              solved = true
            else
              # An unsolvable arrangement — often a few tiles left in one tall
              # stack. Drop the selectable requirement rather than leave tiles
              # without faces, and retry this same match.
              if check_selectable && depth.zero? && i == n_matches - 1
                check_selectable = false
                i -= 1
              end

              match.tile0.visible = true
              match.tile1.visible = true
              i += 1
            end
          end
        end

        solved
      end

      def find_matches(check_selectable = true)
        [].tap do |matches|
          processed = []

          @tiles.each do |tile|
            find_matches_for_tile(tile, processed, check_selectable).then do |submatches|
              matches.concat(submatches)

              # Remember what has been paired up already, so the same match
              # does not come back a second time with the tiles swapped.
              unless submatches.empty?
                processed << tile
              end
            end
          end
        end
      end

      def find_matches_for_tile(tile, ignored_tiles = [], check_selectable = true)
        if tile.nil? || !tile.visible || (check_selectable && !tile.selectable?)
          []
        else
          @tiles.select do |other|
            !other.equal?(tile) && other.visible && other.matches?(tile) &&
              (!check_selectable || other.selectable?) &&
              !ignored_tiles.any? { |ignored| ignored.equal?(other) }
          end.map { |other| Match.new(other, tile) }
        end
      end

      def redraw_all_tiles
        @tiles.each do |tile|
          if tile.visible
            emit(:redraw_tile, tile)
          end
        end
      end

      def set_hint(match)
        remove_hint_timeout

        if match.nil?
          @hint_match = nil
          @hint_matches = []
        else
          @hint_match = match
          @hint_blink_counter = 6
          @hint_timeout = GLib::Timeout.add(250) { hint_blink }
          hint_blink

          unless @inspecting
            had_started = started?
            start_clock
            @clock_elapsed += HINT_PENALTY_SECONDS
            emit(:tick)

            unless had_started
              emit(:moved)
            end
          end
        end
      end

      def redraw_hint_match(match)
        unless match.nil?
          [match.tile0, match.tile1].each do |tile|
            tile.highlighted = !(@hint_blink_counter % 2).zero? || tile.equal?(@selected_tile)
            emit(:redraw_tile, tile)
          end
        end
      end

      def remove_hint_timeout
        unless @hint_timeout.nil?
          GLib::Source.remove(@hint_timeout)
        end
        @hint_timeout = nil
        @hint_blink_counter = 0

        redraw_hint_match(@hint_match)
      end

      def hint_blink
        if @hint_blink_counter.zero?
          remove_hint_timeout
          false
        else
          @hint_blink_counter -= 1
          redraw_hint_match(@hint_match)
          true
        end
      end

      def remove_autoplay_timeout
        unless @autoplay_timeout.nil?
          GLib::Source.remove(@autoplay_timeout)
        end
        @autoplay_timeout = nil
      end

      def autoplay_step
        match = next_hint
        if match.nil?
          remove_autoplay_timeout
          false
        else
          remove_pair(match.tile0, match.tile1)
          true
        end
      end

      def start_clock
        if @clock.nil?
          @clock = Timer.new
          schedule_tick
        end
      end

      def stop_clock
        unless @clock.nil?
          unless @clock_timeout.nil?
            GLib::Source.remove(@clock_timeout)
            @clock_timeout = nil
          end
          @clock.stop
        end
      end

      def continue_clock
        if @clock.nil?
          @clock = Timer.new
        else
          @clock.continue
        end
        schedule_tick
      end

      def reset_clock
        stop_clock
        @clock = nil
        @clock_elapsed = 0.0
        # Make sure the clock label is cleared too.
        emit(:tick)
      end

      # Re-arm on the next whole second of the clock, so the displayed time
      # never skips or repeats a value.
      def schedule_tick
        unless @clock.nil?
          elapsed = @clock.elapsed
          wait = ((elapsed.floor + 1) - elapsed) * 1000
          @clock_timeout = GLib::Timeout.add([wait.to_i, 1].max) { schedule_tick }
          emit(:tick)
        end
        false
      end
  end
end
