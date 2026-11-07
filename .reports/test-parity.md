# Test parity — gnome-mahjongg-rb

Upstream: `origin/main` @ `f61be5e` (`tests/test-game.vala`, `tests/test-map.vala`,
GLib `Test` framework). Port: `ruby` @ `9a07c96` (`test/logic_test.rb`,
`test/ui_test.rb`, driven by `test/gtk_driver.rb`).

## The suite does run, and was actually run for this audit

Not trusted from the stated gate. Both scripts were executed live, on a
virtual display, via the fork's own dev shell:

```
nix develop --command bash -c '
  export GSETTINGS_SCHEMA_DIR=$(pwd)/data/schemas GDK_DISABLE=gl
  xvfb-run -a ruby test/logic_test.rb
  xvfb-run -a ruby test/ui_test.rb
'
```

Result: `logic_test.rb` — "all checks passed" (24 checks). `ui_test.rb` — **87
of 87 checks passed, `DRIVE OK`**, matching the stated gate exactly. One
non-fatal issue inside that run: the screenshot for step 36 ("the winning
scores dialog renders") failed — `RuntimeError: widget produced no render
node` — logged as `shot 15-win failed:` but not counted against the 87, since
screenshots are not themselves checks. That dialog's render is therefore
unverified by this run even though the gate is green; see
`accountability-ensurance.md`.

## Upstream census

17 named GLib tests, two files:

| File | Tests |
|---|---|
| `tests/test-game.vala` | `game_init`, `game_playthrough`, `game_restart`, `next_hint`, `pause`, `remove_invalid_pair`, `remove_valid_pair`, `seed_difference`, `seed_reproducibility`, `seed_snapshot_taipei`, `seed_snapshot_turtle`, `shuffle_remaining`, `tile_highlighted`, `undo_redo`, `undo_redo_no_moves` (15) |
| `tests/test-map.vala` | `load_maps`, `slot` (2) |

## Bijection

| # | Upstream test | Port test(s) | State | Note |
|---|---|---|---|---|
| 1 | `game_init` | `logic_test.rb` `== generation` block (6 checks: faces, visibility, moves available, not complete) | ported | upstream also asserts `can_move`, `can_shuffle`, `all_tiles_unblocked`, `selected_tile == null` at init — not independently checked, but the surviving assertions pin the same property |
| 2 | `game_playthrough` | `ui_test.rb` [35] "playing the board out wins the game" | ported | drives a real game to completion through the GTK layer rather than the model directly — stronger, not weaker |
| 3 | `game_restart` | `logic_test.rb` "restart keeps the same board" + `ui_test.rb` [31] "restart re-deals the same board" | ported | |
| 4 | `next_hint` | `logic_test.rb` "a hint is available" / "the hint is a real match" | **gap** | upstream pins the *exact* 17-pair hint sequence by tile number, twice around (34 assertions) — a regression test on the hint algorithm's order. The port only checks hint existence and validity, which is a materially weaker property; a hint-ordering regression would not be caught |
| 5 | `pause` | `ui_test.rb` [10]-[12] area (pause via dialog-open, paused-board render, click-to-resume) + `logic_test.rb` "a restored game opens paused" | **gap (partial)** | upstream also asserts: pause is **forbidden** before the game has started, pause is **forbidden** after the game completes, and `elapsed` only ever increases through several pause/unpause/restart cycles. None of those three edge cases is asserted anywhere in the port |
| 6 | `remove_invalid_pair` | `logic_test.rb` "mismatched tiles are refused" | ported | |
| 7 | `remove_valid_pair` | `logic_test.rb` "a matching pair is removed" / "both tiles went away" | ported | |
| 8 | `seed_difference` | `logic_test.rb` "a different seed gives a different board" | ported | |
| 9 | `seed_reproducibility` | `logic_test.rb` "generation is reproducible from the seed" | ported | |
| 10 | `seed_snapshot_taipei` | — | **gap** | no equivalent anywhere. Upstream pins the exact tile number, selectability, x/y/layer for every one of 144 tiles on a fixed seed, for two different layouts (Turtle and Taipei) — a hard regression lock on the RNG/layout algorithm. Nothing in the port asserts an exact tile snapshot for any layout |
| 11 | `seed_snapshot_turtle` | — | **gap** | same as above, Turtle layout |
| 12 | `shuffle_remaining` | `ui_test.rb` uses `game.shuffle_remaining` internally (comment: "picking greedily paints us into a corner, reshuffle") as a *tool* to get the playthrough test unstuck | **gap** | upstream's test asserts the tile numbering actually changes after a shuffle (`get_tile(0).number != tile_number`). The port calls the method but never asserts its effect — it is exercised, not tested |
| 13 | `tile_highlighted` | `ui_test.rb` [the tile-selection block] "the tile is highlighted" / "the tile is no longer highlighted" | ported | |
| 14 | `undo_redo` | `logic_test.rb` "undo brought them back" / "redo is available after undo" / "redo took them away again" | ported (partial) | upstream additionally asserts the per-tile `move` counter resets correctly when a new move is made after an undo (tiles revert from `move == 1/2` back to `move == 0`) — not independently asserted in the port, though the port's broader undo/redo behavior is covered |
| 15 | `undo_redo_no_moves` | — | **gap** | no test anywhere calls `undo`/`redo` on a fresh game with nothing to undo and asserts it is a safe no-op |
| 16 | `load_maps` | `logic_test.rb` "ten layouts load" / "first layout is Turtle" / "display name resolves through the score name" / "Turtle is 30 half-tiles wide and 16 high" | ported (partial) | upstream also pins the exact x/y/layer of every one of Turtle's 144 slots — the port checks aggregate shape (width/height/no-duplicates) but not the per-slot snapshot |
| 17 | `slot` | — | **gap** | `Slot#equals` (or the port's `==`) and its exact semantics — same x/y/layer equal, one coordinate different not equal — has no direct test. `lib/mahjongg/map.rb`'s `Slot` is exercised only indirectly through `no layout has duplicate slots`, which does not test the equality method itself |

## Count

**17 upstream tests. 9 cleanly ported, 3 partially ported (counted as gaps per
the skill's own rule — "half a test is not half a pass"), 5 with no
equivalent at all.** Total: **9 ported, 8 gaps.**

This is materially short of parity. The `87 of 87` UI-driver number is real
and was independently re-run, but it is a different census — it counts
*assertions in the port's own test files*, not *upstream properties pinned*.
A drive run can be 100% green while 8 of upstream's 17 pinned behaviours have
no Ruby equivalent, because the gate only checks that the port's own tests
pass, never that they are the same tests upstream had.

## Gaps, with the behaviour still owed

| Gap | Behaviour still owed |
|---|---|
| `next_hint` exact sequence | The hint algorithm returns matches in a specific, reproducible order for a given seed; a person relying on hints sees the same sequence upstream does, and a regression in the hint search order is caught before release |
| `pause` forbidden cases | Pausing before a game has started, or after it has completed, is a no-op — the UI cannot be made to show a paused, unstarted or paused-but-finished game |
| `seed_snapshot_turtle` / `seed_snapshot_taipei` | For a fixed seed, every tile lands in the exact same slot with the exact same number every time, on every layout — the deterministic-replay guarantee the "same seed → same board" feature promises the player, locked down tile-by-tile rather than only spot-checked |
| `shuffle_remaining` effect | Shuffling actually changes the remaining tiles' arrangement, not just that the method can be called without error |
| `undo_redo_no_moves` | Pressing undo or redo on a fresh game does nothing and does not crash or corrupt state |
| `load_maps` exact slot snapshot | Turtle's board shape is pinned tile-for-tile, not just by aggregate width/height/no-duplicates — a layout-generation regression that preserves those aggregates but shifts individual slots would pass today |
| `Slot#equals`/`==` | Two slots are equal exactly when `x`, `y` and `layer` all match, and not otherwise — the primitive the duplicate-slot and snapshot checks are themselves built on is itself unverified |

## What is not a gap

`test/find_tictactoe_seed.rb` is a standalone seed-search utility, not a test
file, and is correctly outside this census. `spec/README.md` + `spec/spec_helper.rb`
are RSpec scaffolding with no spec files yet — Rakefile's `rake spec` task has
nothing to run; this is a tooling-readiness note, not a test-parity row, since
upstream has no RSpec equivalent to map against.
