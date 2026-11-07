# Component parity — gnome-mahjongg-rb

Upstream: `origin/main` @ `f61be5e`. Port: `ruby` @ `9a07c96`.
Built on `.reports/component-inventory.md` (the `component-identification`
skill's output, generated earlier on this branch). This document re-verifies a
sample of that inventory's claims against source and adds what identification
alone cannot show: whether each component *behaves* the same, not just
whether it exists.

## Verdict

**Structurally at parity: all 17 components upstream has, the port has.**
Spot-checks below confirm the inventory's claims rather than merely repeating
them. Three findings do not change the verdict but are real and are recorded
so they are not lost:

1. One drive-run screenshot (`15-win`, the winning scores dialog) failed to
   render (`widget produced no render node`) even though the run still
   reported `87 of 87 checks passed` and `DRIVE OK` — the screenshot is not
   itself a counted check, so a rendering failure on that one dialog state
   does not fail the suite. That state is visually unverified this run. See
   `test-parity.md` and `accountability-ensurance.md`.
2. `app.shortcuts` is installed by the port but is dead code upstream (no
   `add_action`/`install_action` registers it in any `.vala`) — a deliberate,
   documented divergence in the port's favour, not a gap.
3. The `devel` CSS class on `Adw.ApplicationWindow` upstream never applies in
   the port, because the port ships one app id with no `.Devel` variant — out
   of scope, not a gap.

## Spot-checks performed

| Component | Check | Result |
|---|---|---|
| `shortcuts_dialog.rb` vs `data/ui/shortcuts-dialog.ui` | Item-by-item: 2 sections, 6 + 5 items, same titles, same action names, F10 spelled out identically | matches exactly, including build order |
| `menu.rb` | `p_(context, label)` calls reach the 4 msgctxt groups (`mahjongg map name`, `layout progression`, `background color`, `mahjongg theme name`) with the same msgids as `data/ui/menu.ui`'s 3 sections | matches |
| Component count (17) | Re-derived from `git ls-tree -r --name-only origin/main` + the 5 `<template>` roots + `menu.ui` + `shortcuts-dialog.ui`, cross-checked against `lib/mahjongg/*.rb` (17 files) | matches the inventory's count |
| `test/ui_test.rb` 87-check run | Re-ran live (`nix develop --command xvfb-run -a ruby test/ui_test.rb`), not trusted from the gate alone | **87 of 87 checks passed, `DRIVE OK`** — confirmed, with the one screenshot caveat above |

## Reused-string check (surfaced by the translation census, logged here because it is a component question)

Three upstream messages are reused a different number of times in the port.
Per `translation-parity`'s own rule, this is a component finding, not a
translation one:

| Message | Upstream uses | Port uses | Accounted for? |
|---|---|---|---|
| `Mahjongg` | 3 (`.desktop`, metainfo, `gnome-mahjongg.vala:438` window title) | 5 (`.desktop`, metainfo, `about_dialog.rb:68`, `application.rb:159`, `window.rb:138`) | yes — the about dialog and the app's `application_name`/window-title fallback are two more call sites for the same app name, nothing invented |
| `Pause Game` | 1 (`window.vala:196`) | 2 (`window.rb:200`, `window.rb:289`) | yes — the port's pause button and its second code path (the overlay's own resume affordance reusing the same label) both read it |
| `Match tiles and clear the board` | 2 (`.desktop`, metainfo) | 3 (`.desktop`, metainfo, `about_dialog.rb:74`) | yes — the about dialog's comment field is a third legitimate call site |

All three are accounted for by reading the files; none indicates a missing or
duplicated component.

## What this document does not re-derive

It does not re-walk every widget, CSS class and signal in all 17 components —
`.reports/component-inventory.md` already did that at the required depth (type
+ CSS + signals + owner for every row, repeaters and conditionals called out).
Re-reading it here would not find anything a second read of the same evidence
cannot find twice. What this document adds is independent verification on a
sample, the live re-run of the drive suite, and the three findings above that
the identification pass had no reason to surface.
