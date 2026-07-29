{ ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          autoconf
          automake
          bash
          ccache
          cmake
          coreutils
          findutils
          gawk
          gcc
          gettext
          git
          gnumake
          gnugrep
          gnupatch
          gnused
          gnutar
          gzip
          just
          libtool
          luajit
          luajitPackages.luacheck
          meson
          nasm
          ninja
          p7zip
          perl
          pkg-config
          python3
          sdl3
          shellcheck
          shfmt
          unzip
          util-linux
          wget

          # crengine's `ninja lint` and utils/syncheck.sh.
          clang-tools
          cppcheck
          jq
          libxml2
          parallel

          config.treefmt.build.wrapper
        ];

        # Dependencies of a standalone crengine build, which is what exposes
        # its per-file lint targets: koreader-base's embedded build stubs
        # `add_lint_targets()` out.
        buildInputs = with pkgs; [
          freetype
          fribidi
          harfbuzz
          libjpeg
          libpng
          libunibreak
          libwebp
          lunasvg
          md4c
          utf8proc
          xxhash
          zlib
          zstd
        ];

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.sdl3 ];
      };
    };
}
