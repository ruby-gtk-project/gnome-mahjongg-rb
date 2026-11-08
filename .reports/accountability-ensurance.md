# Accountability ensurance — gnome-mahjongg-rb

Grepped `lib/`, `exe/`, `.reports/`, `PORTING.md`, `FINDINGS.md` and
`CHANGELOG.md` for `TODO`, `FIXME`, `not implemented`, `for now`, `in a
future`, `placeholder`, `stub`, `deferred`, and for green claims resting on
something never executed.

## Excuse language: none found in source

```
grep -rniE "TODO|FIXME|not implemented|for now|in a future" lib/ exe/ .reports/*.md PORTING.md
```

returns nothing. A secondary pass for softer deferrals (`placeholder`,
`stub`, `deferred`, `skip`) found three hits in `lib/`, all genuine code
comments about runtime behaviour, not excuses:

- `game.rb:665` — "never skips or repeats a value" (describing the RNG, a
  positive claim, not a skip)
- `history.rb:110` — "A line with an unreadable date is skipped, as upstream
  does" — a documented, upstream-matching behaviour, with the upstream
  comparison stated
- `game_view.rb:219` — "skip" refers to a redraw optimisation, not test or
  feature coverage

None of these excuse missing work. This part of the audit is clean.

## Where the real gaps are hiding instead

The port does not excuse its gaps in comments — it simply has gaps that the
green gate does not surface. Found by this audit, detailed in the sibling
reports:

### 1. A green drive run that does not test what it reports (test-parity.md)

`87 of 87 checks passed` and `DRIVE OK` are both true and were independently
re-run and confirmed in this audit. But that number answers "do the port's
own tests pass", not "does the port have the upstream suite's coverage".
Censusing upstream's 17 named tests against the port's two test files finds
**8 with no equivalent or only a partial equivalent** (exact hint-sequence
regression, exact tile-snapshot regression on two layouts, the `pause`
state machine's forbidden-before-start/forbidden-after-complete edge cases,
`shuffle_remaining`'s actual effect, `undo_redo_no_moves`, `Slot#equals`, the
full `load_maps` slot snapshot). None of this is stated anywhere in the
repo's own documents — `87 of 87` is the only number anyone keeping this
score would see, and it is silent about what it does not cover. This is
exactly the "component a check does not exercise, unverified not done"
pattern the task brief warns about, found in the suite rather than named.

### 2. A test that passes for a reason other than the one it claims (translation-parity.md)

`logic_test.rb`'s "all 93 catalogues are compiled" and "a string with a
context is translated" genuinely pass. But they pass against the **copied**
`po/*.mo` files, never against a freshly regenerated `.pot`. Running the
actual extractor (`GetText::Tools::XGetText`, the same one `rake pot`
calls) on `lib/mahjongg/rules_dialog.rb`, `shortcuts_dialog.rb`, `map.rb`
and `menu.rb` shows it extracts **zero** of the 43 `msgctxt`-tagged messages
those files are responsible for — a helper-method indirection
(`rules_text(message) = p_('game rules', message)`) that `xgettext` cannot
see through. The test suite's green checkmark is real but is checking a
static asset the port happened to copy correctly, not the build step
(`rake pot`) that is supposed to produce it. **This is the false-green
pattern named explicitly in the task brief**: a claim ("all 93 catalogues
are compiled", by extension "the catalogue is intact") that rests on
something — `rake pot`'s correctness — never executed by any test, anywhere
in the suite. Running it live, in this audit, is what surfaced the defect.

### 3. A screenshot failure inside a run that reports full success — **fixed in source since the prior round, not yet re-confirmed live**

The prior round of this audit found that `ui_test.rb`'s step 36, "the
winning scores dialog renders", failed to take its screenshot
(`RuntimeError: widget produced no render node`) in the same run that
reported `87 of 87 checks passed, DRIVE OK` — logged but not wired to any
check. Commit `2f33657`, made after that round, changes `test/gtk_driver.rb`
so a failed screenshot increments `@checks`/`@failed_checks` (after one
patient retry for a dialog whose open transition hasn't settled). Read
alone, that closes this finding. This audit tried three times to re-drive
`test/ui_test.rb` live to confirm it, on this same machine, and got a fourth
data point instead: every attempt timed out or failed to register
(`Failed to register: Timeout was reached`) under heavy concurrent host load
(other repos' own Xvfb/GTK test runs were visibly competing for the CPU in
`ps` throughout). One of those attempts is useful evidence in the hardening
commit's favour even though it isn't the confirmation this finding wanted:
it printed `errored step: no checks ran — a green report here would mean
nothing was verified` and `DRIVE FAILED (2)` instead of a bare `DRIVE OK` —
which is precisely the other failure mode `2f33657` was written to close
(a failed `GApplication#register` used to leave `DRIVE OK` printed with zero
checks run). So the harness now fails loudly on the failure this audit
actually triggered. Whether it also now fails loudly on *that specific*
screenshot failure, rather than on registration, was not independently
re-confirmed by a completed run this round. Recorded as fixed-in-source,
not fixed-and-reconfirmed — the distinction the task brief asks this report
to preserve.

### 4. A stale number in the port's own setup doc (new this round)

`CLAUDE.md`'s Setup section states `rake test` runs "62 logic checks + 80 UI
checks". The live runs this audit performed (this round and the prior one)
consistently show 24 logic checks and 87 UI checks. Neither number is wrong
in a way that hides a gap — nothing here is being used to claim coverage that
doesn't exist — but it is a claim in the port's own top-level doc that does
not match what running the suite actually shows, and a reader trusting the
doc over the terminal would be misled about how big the suite is. Low
severity, flagged per the brief's instruction to grep documentation for green
claims, not just code.

## Is any of this "excused"?

No — and that is itself worth stating plainly, because it means these three
findings were not written down anywhere before this audit ran. `PORTING.md`
makes no claim about translation build correctness or about upstream test
coverage; `.reports/component-inventory.md` (written earlier on this branch,
before this audit) makes accurate, carefully-hedged claims about *components*
and does not touch tests or translation build mechanics at all. There is no
document saying "tests are good enough" or "translations are fine for now" —
the gap here is a gap in verification, not a gap papered over with a
sentence. Both are real findings; the second is the one that matters more,
because a comment that excuses a gap is at least visible to the next
reader, and a check that silently tests the wrong thing is not.

## Verdict

**Not clean.** No excuse language exists in the port's own code or
documents, but two of the five parity reports produced by this audit found
a claim resting on something never executed (`rake pot` regeneration) and
one found a counted-green suite with real, uncounted coverage gaps. Per the
task's own framing, a false green in a report is the most serious finding
this audit can make, and the translation-build defect is exactly that: a
test ("all 93 catalogues are compiled") that is true and tells you nothing
about the one build step most likely to break next.
