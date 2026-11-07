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

### 3. A screenshot failure inside a run that reports full success (test-parity.md / component-parity.md)

`ui_test.rb`'s step 36, "the winning scores dialog renders", fails to take
its screenshot (`RuntimeError: widget produced no render node`) in the same
run that reports `87 of 87 checks passed, DRIVE OK`. The failure is logged to
stdout (`shot 15-win failed: ...`) but is not wired to any check, so it does
not affect the pass/fail count and would not be caught by anything that only
reads the final line. The winning-dialog visual state is, right now,
unverified — not because anyone said so, but because the harness does not
count it as something that can fail.

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
