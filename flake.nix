{
  description = "gnome-mahjongg-rb — a Ruby GTK4 port of GNOME Mahjongg";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        ruby = pkgs.ruby_3_3;

        # Shared libraries every ruby-gnome extension links against, plus the
        # ones mahjongg needs at runtime (libadwaita, librsvg for the tilesets).
        gtkStack = with pkgs; [
          glib
          gobject-introspection
          cairo
          pango
          gdk-pixbuf
          graphene
          atk
          gtk4
          libadwaita
          librsvg
          harfbuzz
        ]
        # The Ruby `pkg-config` gem resolves `Requires.private` transitively and
        # hard-fails if any .pc in the chain is missing, so gtk4's whole
        # private closure has to be on PKG_CONFIG_PATH, not just its public deps.
        ++ (with pkgs; [
          fontconfig
          freetype
          libepoxy
          libpng
          libxkbcommon
          pcre2
          util-linux
          wayland
          zlib
          fribidi
          libdatrie
          libthai
          libselinux
          libsepol
          expat
          brotli
          bzip2
          graphite2
          icu
          libffi
          libxml2
          lerc
          libdeflate
          xz
          zstd
        ])
        ++ (with pkgs; [
          libx11
          libxau
          libxcursor
          libxdmcp
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxcb
          xorgproto
        ]);

        # ruby-gnome gems build C extensions with extconf.rb + the pkg-config
        # gem; nixpkgs only ships gemConfig entries for the GTK3-era subset, so
        # the GTK4 gems get their build inputs declared here.
        rubyGnomeGem = attrs: {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack;
        };

        gemConfig = pkgs.defaultGemConfig // {
          gdk4 = rubyGnomeGem;
          gsk4 = rubyGnomeGem;
          gtk4 = rubyGnomeGem;
          graphene1 = rubyGnomeGem;
          adwaita = rubyGnomeGem;
          rsvg2 = rubyGnomeGem;
        };

        # `makeSearchPath` would take each package's *first* output, and glib's
        # first output is `bin`, which carries no typelibs — hence the explicit
        # `.out`. at-spi2-core is here for the Atk typelib.
        typelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0"
          (map (drv: drv.out or drv) (gtkStack ++ [ pkgs.at-spi2-core ]));

        gems = pkgs.bundlerEnv {
          name = "gnome-mahjongg-rb-gems";
          inherit ruby gemConfig;
          gemdir = ./.;
        };

      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "gnome-mahjongg-rb";
          version = "0.1.0";
          src = ./.;

          # Deliberately no wrapGAppsHook4 and no glib in nativeBuildInputs:
          # glib's setup hook relocates the schema during fixup, after
          # wrapGAppsHook4 has already computed its wrapper arguments, so the
          # schema ends up somewhere the wrapper never looks. Compiling the
          # schema and building the wrapper by hand keeps the two in step.
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ gems ] ++ gtkStack;

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/gnome-mahjongg-rb $out/share/glib-2.0/schemas \
              $out/share/applications $out/share/dbus-1/services
            cp -r lib data $out/share/gnome-mahjongg-rb/
            # bin/ has to sit next to lib/ for the launcher's require_relative.
            install -Dm755 bin/gnome-mahjongg-rb \
              $out/share/gnome-mahjongg-rb/bin/gnome-mahjongg-rb

            cp data/schemas/org.gnome.Mahjongg.Rb.gschema.xml $out/share/glib-2.0/schemas/
            ${pkgs.glib.dev}/bin/glib-compile-schemas $out/share/glib-2.0/schemas
            # glib's setup hook (pulled in transitively through gtk4) relocates
            # this directory to share/gsettings-schemas/$name during fixup, so
            # the wrapper below points at both the pre- and post-move paths.

            cp data/org.gnome.Mahjongg.Rb.desktop $out/share/applications/

            install -Dm644 data/org.gnome.Mahjongg.Rb.metainfo.xml -t $out/share/metainfo
            install -Dm644 data/icons/hicolor/scalable/apps/org.gnome.Mahjongg.Rb.svg \
              -t $out/share/icons/hicolor/scalable/apps
            install -Dm644 data/icons/hicolor/symbolic/apps/org.gnome.Mahjongg.Rb-symbolic.svg \
              -t $out/share/icons/hicolor/symbolic/apps

            sed "s|@BINDIR@|$out/bin|" data/org.gnome.Mahjongg.Rb.service \
              > $out/share/dbus-1/services/org.gnome.Mahjongg.Rb.service

            # -rbundler/setup puts the bundled gems on the load path, and
            # GI_TYPELIB_PATH keeps GObject-Introspection from re-registering
            # types the cairo gem's C extension has already registered.
            makeWrapper ${gems.wrappedRuby}/bin/ruby $out/bin/gnome-mahjongg-rb \
              --add-flags "-rbundler/setup" \
              --add-flags "$out/share/gnome-mahjongg-rb/bin/gnome-mahjongg-rb" \
              --set GI_TYPELIB_PATH "${typelibPath}" \
              --set MAHJONGG_RB_DATA_DIR "$out/share/gnome-mahjongg-rb/data" \
              --prefix XDG_DATA_DIRS : "$out/share" \
              --prefix XDG_DATA_DIRS : "$out/share/gsettings-schemas/$name" \
              --prefix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}" \
              --prefix XDG_DATA_DIRS : "${pkgs.adwaita-icon-theme}/share"

            runHook postInstall
          '';
        };

        apps.default = flake-utils.lib.mkApp { drv = self.packages.${system}.default; };

        devShells.default = pkgs.mkShell {
          name = "gnome-mahjongg-rb-devshell";

          packages = [
            gems
            gems.wrappedRuby
            pkgs.bundler
            pkgs.bundix
            pkgs.pkg-config
            pkgs.glib.dev            # glib-compile-schemas
            pkgs.gsettings-desktop-schemas
            pkgs.adwaita-icon-theme
          ] ++ gtkStack;

          # Icons, GSettings schemas and the GTK portal all resolve through
          # XDG_DATA_DIRS; without these the window opens with blank icons.
          shellHook = ''
            export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.adwaita-icon-theme}/share:$XDG_DATA_DIRS"
            export GSETTINGS_SCHEMA_DIR="$PWD/data/schemas"
            unset BUNDLE_GEMFILE BUNDLE_FROZEN
            echo "gnome-mahjongg-rb devshell — ruby $(ruby -e 'print RUBY_VERSION')"
            echo "  ./bin/gnome-mahjongg-rb   run the app"
            echo "  rake                      schema + tests + lint"
          '';
        };
      });
}
