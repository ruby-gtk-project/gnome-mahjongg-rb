# gnome-mahjongg — Ruby port

This branch holds a Ruby GTK4 / Libadwaita port of GNOME Mahjongg 49.1.1. The
Vala original is on the fork's `main` branch; `PORTING.md` maps one onto the
other and records where the port deliberately differs.

## Skills — use them

Two skills are installed in `.claude/skills/`. They are not optional reading.

- **ruby-gtk** — the house style for Ruby GTK4/Libadwaita: the declarative
  memoized-widget pattern, Adwaita binding quirks, worked examples. Load it
  before writing or reviewing ANY Ruby GTK code, including single widgets, and
  before planning a port. The bindings are quirky enough that code written from
  memory is unreliable.
- **ruby-gtk-testing** — run the app headlessly and drive its UI: click through
  dialogs, assert widget state, capture screenshots. Use it before claiming any
  GTK change works. `ruby -c` and a successful `require` prove nothing about a
  UI.

`FINDINGS.md` lists the ruby-gnome defects this port ran into, including two
that bite the testing harness itself.

## Setup

`direnv allow` (or `nix develop`) gets Ruby, GTK4, Libadwaita, librsvg and the
introspection typelibs, plus GNU gettext for the desktop/AppStream merges. Gems are built by `bundlerEnv` from `gemset.nix`; after
touching the `Gemfile`, run `nix run nixpkgs#bundix -- -l` to regenerate it (the
`.envrc` does this for you when `Gemfile.lock` moves ahead).

```sh
rake            # schema, catalogues, metadata, tests, lint
rake test       # 59 logic checks + 80 UI checks, no display needed
./bin/gnome-mahjongg-rb
```

## Style

`.rubocop.yml` plus the custom cops in `cops/` are enforced: no `return`, no
modifier `if`, no conditional assignment, `tap` where it applies, and fixed
multi-line argument/hash layout. Run `bundle exec rubocop` before committing.
