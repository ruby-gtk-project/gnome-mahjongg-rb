# frozen_string_literal: true

# Plain checks on the parts that need no widgets: layout parsing, board
# generation, undo/redo, save/restore and the score file.

require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'mahjongg/game'
require 'mahjongg/game_save'
require 'mahjongg/history'
require 'mahjongg/map'
require 'mahjongg/paths'

$failures = 0

def check(name)
  if yield
    puts "  ok   #{name}"
  else
    $failures += 1
    puts "  FAIL #{name}"
  end
end

maps = Mahjongg::Maps.new
maps.load

puts '== maps'
check('ten layouts load') { maps.n_maps == 10 }
check('first layout is Turtle') { maps.get_map_at_position(0).name == 'Turtle' }
check('Turtle has 144 slots') { maps.get_map_by_name('Turtle').n_slots == 144 }
check('every layout has an even, non-zero slot count') do
  maps.all? { |map| map.n_slots.positive? && (map.n_slots % 2).zero? }
end
check('no layout has duplicate slots') do
  maps.all? do |map|
    map.map { |slot| [slot.x, slot.y, slot.layer] }.uniq.length == map.n_slots
  end
end
check('display name resolves through the score name') do
  maps.get_map_display_name('difficult') == 'Taipei'
end
check('Turtle is 30 half-tiles wide and 16 high') do
  turtle = maps.get_map_by_name('Turtle')
  turtle.width == 30 && turtle.height == 16
end
check('slots are ordered back to front') do
  turtle = maps.get_map_by_name('Turtle')
  turtle.each_cons(2).all? { |a, b| a.layer <= b.layer }
end

puts '== generation'
turtle = maps.get_map_by_name('Turtle')
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
game = Mahjongg::Game.new(turtle)
game.generate(12_345)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
puts "  (generated in #{elapsed.round(2)}s)"

check('every tile got a face') { game.tiles.all? { |tile| tile.number >= 0 } }
check('faces come in fours') do
  game.tiles.group_by { |tile| tile.number / 4 }.values.all? { |group| group.length == 4 }
end
check('every tile number is used exactly once') do
  game.tiles.map(&:number).sort == (0...game.n_tiles).to_a
end
check('all tiles start visible') { game.tiles.all?(&:visible) }
check('the board opens with moves available') { game.moves_left.positive? }
check('the board is not complete') { !game.complete? }
check('generation is reproducible from the seed') do
  other = Mahjongg::Game.new(turtle)
  other.generate(12_345)
  other.tiles.map(&:number) == game.tiles.map(&:number)
end
check('a different seed gives a different board') do
  other = Mahjongg::Game.new(turtle)
  other.generate(999)
  other.tiles.map(&:number) != game.tiles.map(&:number)
end
check('restart keeps the same board') do
  numbers = game.tiles.map(&:number)
  game.restart
  game.tiles.map(&:number) == numbers
end

puts '== moves'
pair = nil
game.tiles.each do |tile|
  unless pair.nil?
    next
  end

  partner = game.tiles.find { |t| !t.equal?(tile) && t.visible && t.selectable? && t.matches?(tile) }
  if tile.selectable? && partner
    pair = [tile, partner]
  end
end
check('a legal match exists') { !pair.nil? }
check('mismatched tiles are refused') do
  odd = game.tiles.find { |t| !t.matches?(pair[0]) }
  !game.remove_pair(pair[0], odd)
end
check('a matching pair is removed') { game.remove_pair(pair[0], pair[1]) }
check('both tiles went away') { !pair[0].visible && !pair[1].visible }
check('the move counter advanced') { game.current_move == 2 }
check('undo is available') { game.can_undo? }
check('redo is not, until we undo') { !game.can_redo? }
game.undo
check('undo brought them back') { pair[0].visible && pair[1].visible }
check('redo is available after undo') { game.can_redo? }
game.redo
check('redo took them away again') { !pair[0].visible && !pair[1].visible }
check('a hint is available') { !game.next_hint.nil? }
check('the hint is a real match') do
  match = game.next_hint
  match.tile0.matches?(match.tile1) && match.tile0.selectable? && match.tile1.selectable?
end

puts '== save round trip'
Dir.mktmpdir do |dir|
  path = File.join(dir, 'gamesave')
  save = Mahjongg::GameSave.new(path)

  check('an unstarted game is not saved') { !Mahjongg::GameSave.new(path).write(Mahjongg::Game.new(turtle)) }
  check('a started game is saved') { save.write(game) }
  check('the file is on disk') { File.exist?(path) }

  reloaded = Mahjongg::GameSave.new(path)
  check('the save loads back') { reloaded.load(maps) }
  check('the layout came back') { reloaded.map.name == 'Turtle' }
  check('the seed came back') { reloaded.seed == game.seed }
  check('the move counter came back') { reloaded.move == game.current_move }

  restored = Mahjongg::Game.new(turtle)
  restored.restore(reloaded)
  check('the board came back tile for tile') { restored.tiles.map(&:number) == game.tiles.map(&:number) }
  check('the removed tiles are still removed') { restored.tiles.count(&:visible) == game.tiles.count(&:visible) }
  check('a restored game opens paused') { restored.paused? }
  restored.destroy_timers

  save.delete
  check('delete removes the file') { !File.exist?(path) }
  check('a missing save does not load') { !Mahjongg::GameSave.new(path).load(maps) }

  wrong = Mahjongg::GameSave.new(File.join(dir, 'mismatched'))
  File.write(File.join(dir, 'mismatched'), %(<game map="Cloud" seed="1" clock="0" move="1"><tiles/></game>))
  check('a save whose tiles do not fit the layout is rejected') { !wrong.load(maps) }
end

puts '== history'
Dir.mktmpdir do |dir|
  path = File.join(dir, 'history')
  history = Mahjongg::History.new(path)
  history.load
  check('an absent history is empty') { history.length.zero? }

  history.add(
    Time.at(1_700_000_000).utc,
    'easy',
    321,
    'Ada',
  )
  history.add(
    Time.at(1_700_000_100).utc,
    'cloud',
    99,
    'Grace Hopper',
  )

  reloaded = Mahjongg::History.new(path)
  reloaded.load
  check('both scores came back') { reloaded.length == 2 }
  check('the duration came back') { reloaded.first.duration == 321 }
  check('the layout came back') { reloaded.first.name == 'easy' }
  check('a player name with a space survives') { reloaded.to_a.last.player == 'Grace Hopper' }
  check('the date came back') { reloaded.first.date.to_i == 1_700_000_000 }

  reloaded.clear
  check('clear empties the file') { File.read(path).empty? }
end

game.destroy_timers

puts($failures.zero? ? "\nall checks passed" : "\n#{$failures} check(s) failed")
exit($failures.zero? ? 0 : 1)
