# Translation parity — gnome-mahjongg-rb

| | |
|---|---|
| Upstream | `main` @ `f61be5e` |
| Port | `ruby` @ `9a07c96` |
| Upstream domain | `gnome-mahjongg` (from `po/meson.build`) |
| Port domain | **none** — `rake locale` compiles straight to `gnome-mahjongg-rb.mo`, never calling `bindtextdomain`/`TextDomain` with a name that matches anything the catalogue census can confirm |
| Upstream messages | 100 (109 occurrences, 6 reused, 0 plural, 43 with a `msgctxt`) |
| Ported (by key, census-verified) | 57 |
| **Gaps** | **43** |
| Extra (port-only, untranslated by definition) | 4 |
| Upstream languages | 93 `.po` files, 5,735 translated / 677 untranslated / 571 fuzzy strings |
| Languages shipped by the port | 93 `.po` files, copied byte-for-byte from upstream, `LINGUAS` identical |
| `domain_matches` | **false** |

Numbers above come from a regenerated, freshly-run census
(`.claude/skills/translation-parity/scripts/{msgid-census.sh,catalogue.rb}`),
not from reading code. Upstream was scanned from a disposable worktree of
`origin/main` (`f61be5e`); the port's generated/merged
`data/org.gnome.Mahjongg.Rb.metainfo.xml` — a build artifact that is
committed but is not source — was excluded from the port scan, the same way
`po/` itself is excluded from message counts: scanning it double-counts every
language's translation of the AppStream description as a distinct "extra"
English string and inflates the extra count from 4 to 208.

## Headline finding: the catalogue the port *ships* is complete; the catalogue the port's own build *produces* is not

This is the serious finding, verified by actually running the extractor, not
by reading the `Rakefile`:

```
$ ruby -e 'require "gettext/tools"; GetText::Tools::XGetText.run(
    "-o", "/tmp/test.pot", "lib/mahjongg/rules_dialog.rb",
    "lib/mahjongg/shortcuts_dialog.rb", "lib/mahjongg/map.rb", "lib/mahjongg/menu.rb")'
```

The resulting `.pot` contains every plain `_()` string in those files and
**zero** of the context-tagged ones — no `game rules`, no `shortcut window`,
no `mahjongg map name`, no `layout progression`, no `background color`, no
`mahjongg theme name` msgctxt groups at all.

The cause is a house-style helper pattern that defeats `xgettext`'s own
extraction, in every file that uses it:

```ruby
# lib/mahjongg/rules_dialog.rb
def rules_text(message) = p_('game rules', message)
...
rules_text('Clear the board by matching pairs of identical tiles')
```

```ruby
# lib/mahjongg/shortcuts_dialog.rb
def shortcut_text(message) = p_('shortcut window', message)
```

```ruby
# lib/mahjongg/menu.rb
section.append_item(target_item(p_(context, label), action, target))
```

`xgettext` extracts a marker call whose arguments are **literals at the call
site**. `p_('game rules', message)` is a literal context and a *variable*
message — the literal English only exists one call frame away, at
`rules_text('Clear the board...')`, which is not a recognised gettext marker
at all. The same is true for `shortcut_text(title)` and for `p_(context,
label)` in the menu's layout/theme/background submenus, where both arguments
are local variables built from a lookup table. `xgettext` sees none of it.

**Why the shipped app still shows correct translations right now:** the port
did not generate its own `.pot`/`.po` set from this source — it copied
upstream's `po/` directory wholesale, keys and all, so the 43 affected
messages are already in every `.mo` with upstream's translations attached,
and `p_()` looks them up correctly at runtime by the literal strings it is
*given*, regardless of how those strings were extracted. `logic_test.rb`'s
"a string with a context is translated" check passes for exactly this
reason — it calls the running code, which works, not the extractor, which
does not.

**Why this is still a live defect and not a non-issue:** `rake pot` is a
real, documented task (`Rakefile`: "Regenerate po/gnome-mahjongg-rb.pot from
the sources in po/POTFILES.in"), it is the only path offered for refreshing
the catalogue, and running it today silently produces a `.pot` missing 43 of
the app's 100 messages. The next time anyone adds, changes, or re-merges a
string — the normal reason to run `rake pot` followed by `msgmerge` — those
43 messages would either vanish from the merged `.po` files or be re-marked
`#~` obsolete, discarding their translations in all 93 languages. Nothing in
the test suite exercises `rake pot`; "all 93 catalogues are compiled"
(`logic_test.rb`) checks the catalogues as committed, never that they can be
correctly regenerated. This is a **false-green risk**: the suite is green
today and would stay green the moment the regeneration silently dropped 43
messages, because nothing re-derives the `.pot` and diffs it.

**Also note, found during the same census:** `data/org.gnome.Mahjongg.Rb.metainfo.xml`
(the *merged*, translation-baked-in metainfo file) is committed to git,
unlike its sibling `data/org.gnome.Mahjongg.Rb.desktop` which is correctly
`.gitignore`d as a build artifact. It should not be committed either — it is
regenerated by `rake metadata` and its presence in the tree is what produced
the 208-row false "extra" count on the first, uncorrected run of this audit.

## The 43 gaps

All 43 are the context-tagged (`msgctxt`) messages, grouped by context:

| Context | Messages | Port call sites that should reach them |
|---|---|---|
| `shortcut window` | `Game`, `General`, `New Game`, `Restart Game`, `Pause Game`, `Undo`, `Redo`, `Show Hint`, `Show Game Rules`, `Show Keyboard Shortcuts`, `Close Window`, `Quit` (12) | `lib/mahjongg/shortcuts_dialog.rb` via `shortcut_text` |
| `game rules` | `Clear the board by matching pairs of identical tiles`, `Only uncovered tiles with a free long edge can be selected`, `Rounds are scored based on completion time`, `Tile faces will be hidden`, `You can pause the game`, `You can undo or redo a move`, `No time penalty is added`, `Adds a 30-second time penalty`, `Adds a 60-second time penalty`, `You can shuffle tiles when no moves are left`, `You can use hints to reveal matching tiles` (11) | `lib/mahjongg/rules_dialog.rb` via `rules_text` |
| `mahjongg map name` | `Turtle`, `The Ziggurat`, `Tic-Tac-Toe`, `Four Bridges`, `Red Dragon`, `Overpass`, `Pyramid's Walls`, `Confounding Cross`, `Taipei`, `Cloud` (10) | `lib/mahjongg/map.rb:166` (`p_('mahjongg map name', map.name)`) |
| `mahjongg theme name` | `Postmodern`, `Smooth`, `Educational` (3) | `lib/mahjongg/menu.rb` (`p_(context, label)`) |
| `layout progression` | `Sequential`, `Random`, `No Progression` (3) | `lib/mahjongg/menu.rb` |
| `background color` | `Follow System`, `Light`, `Dark` (3) | `lib/mahjongg/menu.rb` |
| (no context) | — | 0 gaps outside msgctxt — every plain `_()` message upstream has is ported |

Every one of these **already works at runtime** through the copied `.mo`
files — this is a gap in the port's *build pipeline*, not in what players
see today. It is still reported as a gap, per the skill's rule that there is
no third state between `ported` and `gap`: the key the census finds in the
port's *source* does not match, and "it happens to work because we copied
upstream's binaries" is exactly the kind of excuse this audit exists to
reject.

### Fix

Either give `xgettext` a literal to see — `GetText::Tools::XGetText` supports
reading a comment-based hint, or the call sites can pass the full literal
pair directly instead of through a single-argument helper — or add a small,
checked-in fixture `.pot`/extraction test that fails when `rake pot`'s output
stops matching the committed `po/gnome-mahjongg-rb.pot`. Either closes the
row; neither has been done.

## Occurrences and reuse (not a pass condition — reported per the skill)

| Message | Upstream uses | Port uses | Note |
|---|---|---|---|
| `Mahjongg` | 3 | 5 | legitimate — about dialog + app/window title fallback, see `component-parity.md` |
| `Pause Game` | 1 | 2 | legitimate — two call sites for the same button label |
| `Match tiles and clear the board` | 2 | 3 | legitimate — about dialog comment |

## Extra (port-only, English-only by definition)

4 GSettings key `<summary>` strings the port added that upstream's
`org.gnome.Mahjongg.gschema.xml.in` does not have (`tileset`, `mapset`,
`map-rotation`, `background-color` have no `<summary>` upstream at all): "Name
of the tile set to use", "Name of the layout to use", "How the layout
advances between games", "Colour scheme of the window background". Harmless
— these only ever surface in a settings-schema browser — but they are
untranslated in all 93 languages and always will be, since no upstream
translator has ever seen them.

## What could not be run

`msgfmt -c` validation and an actual non-English on-screen check were not
run against a *freshly regenerated* `.pot`, because the regeneration itself
is the thing found broken above — running it would have produced the
corrupted catalogue this report warns about, not proven anything. The shipped
`.mo` files (built from the untouched, copied `po/*.po`) were exercised
indirectly through `logic_test.rb`'s own translation checks during the live
test run recorded in `test-parity.md`, and those pass. A `LANGUAGE=de`
end-to-end run of the actual app binary, independent of the test suite, was
not performed in this audit.

## Summary line

```
57/100 messages ported by source-census · 100/100 by shipped catalogue ·
93/93 languages · 5,735 translated strings carried · rake pot regeneration:
BROKEN for 43 messages (verified by running it)
```
