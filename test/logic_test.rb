# frozen_string_literal: true

# Plain checks on the parts that need no widgets: layout parsing, board
# generation, undo/redo, save/restore and the score file.

require 'English'
require 'open3'
require 'set'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

ENV['LANGUAGE'] = 'de'

require 'mahjongg/game'
require 'mahjongg/game_save'
require 'mahjongg/history'
require 'mahjongg/map'
require 'mahjongg/menu'
require 'mahjongg/paths'
require 'mahjongg/version'
require 'mahjongg/pause_overlay'
require 'mahjongg/rules_dialog'

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
check('Turtle slots match the pinned snapshot exactly') do
  expected = [
    [24, 0, 0], [22, 0, 0], [28, 7, 0], [20, 0, 0], [26, 7, 0], [18, 0, 0],
    [20, 2, 0], [22, 4, 0], [24, 6, 0], [16, 0, 0], [18, 2, 0], [20, 4, 0],
    [22, 6, 0], [24, 8, 0], [14, 0, 0], [16, 2, 0], [18, 4, 0], [20, 6, 0],
    [22, 8, 0], [12, 0, 0], [14, 2, 0], [16, 4, 0], [18, 6, 0], [20, 8, 0],
    [22, 10, 0], [10, 0, 0], [12, 2, 0], [14, 4, 0], [16, 6, 0], [18, 8, 0],
    [20, 10, 0], [24, 14, 0], [8, 0, 0], [10, 2, 0], [12, 4, 0], [14, 6, 0],
    [16, 8, 0], [18, 10, 0], [20, 12, 0], [22, 14, 0], [6, 0, 0], [8, 2, 0],
    [10, 4, 0], [12, 6, 0], [14, 8, 0], [16, 10, 0], [18, 12, 0], [20, 14, 0],
    [4, 0, 0], [6, 2, 0], [8, 4, 0], [10, 6, 0], [12, 8, 0], [14, 10, 0],
    [16, 12, 0], [18, 14, 0], [2, 0, 0], [6, 4, 0], [8, 6, 0], [10, 8, 0],
    [12, 10, 0], [14, 12, 0], [16, 14, 0], [4, 4, 0], [6, 6, 0], [8, 8, 0],
    [10, 10, 0], [12, 12, 0], [14, 14, 0], [4, 6, 0], [6, 8, 0], [8, 10, 0],
    [10, 12, 0], [12, 14, 0], [2, 6, 0], [4, 8, 0], [6, 10, 0], [8, 12, 0],
    [10, 14, 0], [2, 8, 0], [4, 10, 0], [6, 12, 0], [8, 14, 0], [0, 7, 0],
    [6, 14, 0], [4, 14, 0], [2, 14, 0], [18, 2, 1], [16, 2, 1], [18, 4, 1],
    [14, 2, 1], [16, 4, 1], [18, 6, 1], [12, 2, 1], [14, 4, 1], [16, 6, 1],
    [18, 8, 1], [10, 2, 1], [12, 4, 1], [14, 6, 1], [16, 8, 1], [18, 10, 1],
    [8, 2, 1], [10, 4, 1], [12, 6, 1], [14, 8, 1], [16, 10, 1], [18, 12, 1],
    [8, 4, 1], [10, 6, 1], [12, 8, 1], [14, 10, 1], [16, 12, 1], [8, 6, 1],
    [10, 8, 1], [12, 10, 1], [14, 12, 1], [8, 8, 1], [10, 10, 1], [12, 12, 1],
    [8, 10, 1], [10, 12, 1], [8, 12, 1], [16, 4, 2], [14, 4, 2], [16, 6, 2],
    [12, 4, 2], [14, 6, 2], [16, 8, 2], [10, 4, 2], [12, 6, 2], [14, 8, 2],
    [16, 10, 2], [10, 6, 2], [12, 8, 2], [14, 10, 2], [10, 8, 2], [12, 10, 2],
    [10, 10, 2], [14, 6, 3], [12, 6, 3], [14, 8, 3], [12, 8, 3], [13, 7, 4]
  ]
  turtle = maps.get_map_by_name('Turtle')
  turtle.map { |slot| [slot.x, slot.y, slot.layer] } == expected
end
check('Slot#equals matches on x/y/layer and not otherwise') do
  slot_a = Mahjongg::Slot.new(1, 2, 3)
  slot_b = Mahjongg::Slot.new(1, 2, 3)
  slot_c = Mahjongg::Slot.new(2, 2, 3)
  slot_a.equals(slot_b) && !slot_b.equals(slot_c)
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

puts '== hint sequence, shuffle, undo/redo safety, pause edges'
# A fresh board on the same seed as the generation block above, so the hint
# cycle pinned here is reproducible without disturbing `game` itself.
hint_game = Mahjongg::Game.new(turtle)
hint_game.generate(12_345)

expected_hint_pairs = [
  [4, 5], [76, 77], [126, 127], [57, 59], [58, 59], [13, 15], [14, 15],
  [12, 15], [24, 25], [58, 57], [14, 13], [12, 13], [12, 14], [132, 133],
  [127, 125], [126, 125], [23, 21], [20, 21], [75, 73], [133, 135],
  [132, 135], [3, 1], [2, 1], [88, 89], [2, 3], [20, 23]
]
check('the hint sequence matches the pinned order, twice around') do
  (expected_hint_pairs + expected_hint_pairs).all? do |expected0, expected1|
    match = hint_game.next_hint
    match.tile0.number == expected0 && match.tile1.number == expected1
  end
end
hint_game.destroy_timers

check('undo on a fresh game with nothing to undo is a safe no-op') do
  fresh = Mahjongg::Game.new(turtle)
  fresh.generate(12_345)
  fresh.undo
  fresh.redo
  ok = !fresh.can_undo? && !fresh.can_redo? && fresh.tiles.map(&:number) == game.tiles.map(&:number)
  fresh.destroy_timers
  ok
end

check('shuffle_remaining actually changes the remaining tile numbers') do
  shuffled = Mahjongg::Game.new(turtle)
  shuffled.generate(12_345)
  before = shuffled.get_tile(0).number
  shuffled.shuffle_remaining
  after = shuffled.get_tile(0).number
  shuffled.destroy_timers
  after != before
end

check('pausing before the game has started is forbidden') do
  unstarted = Mahjongg::Game.new(turtle)
  unstarted.generate(12_345)
  unstarted.paused = true
  ok = !unstarted.paused? && unstarted.elapsed == 0.0
  unstarted.destroy_timers
  ok
end

check('pausing after the game has completed is forbidden') do
  finishing = Mahjongg::Game.new(turtle)
  finishing.generate(12_345)
  until finishing.complete?
    finishing.shuffle_remaining unless finishing.can_move?
    match = finishing.next_hint
    finishing.remove_pair(match.tile0, match.tile1)
  end
  finishing.paused = true
  ok = !finishing.paused? && finishing.elapsed.positive?
  finishing.destroy_timers
  ok
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

puts '== translations'
check('all 93 catalogues are compiled') do
  Dir[File.join(Mahjongg::Paths.locale_dir, '*/LC_MESSAGES/gnome-mahjongg-rb.mo')].length == 93
end
check('a plain string is translated') do
  Mahjongg::PauseOverlay.new.title_label.label == 'Pausiert'
end
check('a dialog title is translated') do
  Mahjongg::RulesDialog.new.dialog.title == 'Spielregeln'
end
check('a string with a context is translated') do
  Mahjongg::Menu.p_('mahjongg map name', 'Turtle') == 'Schildkröte'
end
check('layout display names come back translated') do
  maps.get_map_display_name('easy') == 'Schildkröte'
end
check('a format string keeps its placeholder') do
  Mahjongg::Menu._('Moves Left: %2u').include?('%2u')
end
check('an untranslated context is not confused with a translated one') do
  Mahjongg::Menu.p_('background color', 'Light') == 'Hell'
end

puts '== pot regeneration'
check('rake pot still extracts every committed msgid/msgctxt pair') do
  # A helper wrapping p_/_ with a non-literal argument is invisible to
  # xgettext: it silently drops that message from a regenerated .pot without
  # failing anything else. This regenerates the .pot from the current
  # sources and diffs its (msgctxt, msgid) pairs against the committed one,
  # so a regression like that is caught here instead of at the next
  # `rake pot && msgmerge`, which would otherwise discard translations.
  require 'gettext/tools'

  pairs_of = lambda do |path|
    File.read(path).scan(/^msgctxt "((?:[^"\\]|\\.)*)"\nmsgid "((?:[^"\\]|\\.)*)"/).to_set
  end

  root = File.expand_path('..', __dir__)
  committed = File.join(root, 'po/gnome-mahjongg-rb.pot')
  files = File.readlines(File.join(root, 'po/POTFILES.in'))
              .map(&:strip)
              .reject { |line| line.empty? || line.start_with?('#') }
              .grep(/\.rb\z/)

  Dir.mktmpdir do |dir|
    fresh = File.join(dir, 'fresh.pot')
    Dir.chdir(root) { GetText::Tools::XGetText.run('-o', fresh, *files) }
    pairs_of.call(committed) == pairs_of.call(fresh)
  end
end

puts '== metadata'
check('the desktop entry is translated') do
  File.read(File.expand_path('../data/org.gnome.Mahjongg.Rb.desktop', __dir__))
      .include?('Comment[de]=')
end
check('the AppStream metainfo is translated') do
  File.read(File.expand_path('../data/org.gnome.Mahjongg.Rb.metainfo.xml', __dir__))
      .include?('xml:lang="de"')
end
check('every translatable desktop key is a msgid the catalogues carry') do
  # A Comment the catalogues have never heard of would ship untranslated in
  # all 93 languages without anything failing.
  catalogue = File.read(File.expand_path('../po/de.po', __dir__))
  File.readlines(File.expand_path('../data/org.gnome.Mahjongg.Rb.desktop.in', __dir__))
      .filter_map { |line| line[/\A(?:Name|Comment|Keywords)=(.+)\n/, 1] }
      .all? { |value| catalogue.include?(%(msgid "#{value}")) }
end

puts '== command line'
check('--version prints the release and exits 0') do
  # stdout and stderr are captured separately, on purpose: GTK logs a
  # libEGL warning to stderr on every run under Xvfb with no DRI3, which
  # has nothing to do with --version's own output. Merging the two streams
  # would make this check depend on that environment noise instead of on
  # what the GNU convention actually asks for — the version line on
  # stdout — which is the real regression this caught: the line was going
  # out through `warn` (stderr) rather than `puts` (stdout).
  stdout, _stderr, status = Open3.capture3(
    { 'GSETTINGS_SCHEMA_DIR' => File.expand_path('../data/schemas', __dir__) },
    File.expand_path('../bin/gnome-mahjongg-rb', __dir__),
    '--version',
  )
  stdout.strip == "gnome-mahjongg-rb #{Mahjongg::VERSION}" && status.success?
end
check('--help lists the version option, translated') do
  IO.popen(
    { 'GSETTINGS_SCHEMA_DIR' => File.expand_path('../data/schemas', __dir__) },
    [File.expand_path('../bin/gnome-mahjongg-rb', __dir__), '--help'],
    err: %i[child out],
  ) { |io| io.read }.then do |help|
    # The child inherits LANGUAGE=de from this script, so the description
    # comes back in German — which is the whole point of registering it as a
    # GApplication option rather than parsing ARGV by hand.
    help.include?('-v, --version') &&
      help.include?(Mahjongg::Menu._('Print release version and exit'))
  end
end

puts($failures.zero? ? "\nall checks passed" : "\n#{$failures} check(s) failed")
exit($failures.zero? ? 0 : 1)
