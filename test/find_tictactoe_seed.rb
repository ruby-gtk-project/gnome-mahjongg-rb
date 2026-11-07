# frozen_string_literal: true

# Not run by `rake test`. A one-off used to pick the seed test/ui_test.rb
# pins the "playing the board out wins the game" step to.
#
# Game#generate's own backtracking solver (Game#choose_tile_pairs) guarantees
# every board it hands back CAN be cleared — but only by the specific removal
# order the solver found. ui_test.rb's playthrough always takes the first
# legal pair it finds instead, which is a different (and much dumber)
# strategy, and on an unlucky seed that greedy order runs itself into a dead
# board: fewer than two selectable tiles left with pairs still on it, which
# no amount of reshuffling can fix. That is a real, reachable game state, not
# a port bug — re-seeding the step is the same fix logic_test.rb already
# applies by pinning Turtle to seed 12345.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/find_tictactoe_seed.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'mahjongg/game'
require 'mahjongg/map'

def find_pair(game)
  found = nil
  game.tiles.each do |tile|
    if found.nil? && tile.visible && tile.selectable?
      partner = game.tiles.find { |t| !t.equal?(tile) && t.visible && t.selectable? && t.matches?(tile) }
      unless partner.nil?
        found = [tile, partner]
      end
    end
  end
  found
end

def greedy_clear?(map, seed)
  game = Mahjongg::Game.new(map)
  game.generate(seed)
  shuffles = 0
  cleared = true

  until game.complete?
    pair = find_pair(game)
    if pair.nil?
      unless game.can_shuffle?
        cleared = false
        break
      end

      game.shuffle_remaining
      shuffles += 1
      if shuffles > 20
        cleared = false
        break
      end
    else
      game.remove_pair(pair[0], pair[1])
    end
  end

  game.destroy_timers
  [cleared, shuffles]
end

maps = Mahjongg::Maps.new
maps.load
map = maps.get_map_by_name('Tic-Tac-Toe')

(0..20).each do |seed|
  cleared, shuffles = greedy_clear?(map, seed)
  puts "seed #{seed}: #{cleared ? "clears in #{shuffles} shuffle(s)" : 'DEAD BOARD'}"
end
