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

          config.treefmt.build.wrapper
        ];

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.sdl3 ];
      };
    };
}
