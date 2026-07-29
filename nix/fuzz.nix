{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      crengine = ../base/thirdparty/kpvcrlib/crengine;

      src = lib.fileset.toSource {
        root = crengine;
        fileset = lib.fileset.unions (
          map (f: crengine + "/${f}") [
            "crengine/include/lvkplinebreak.h"
            "crengine/src/lvkplinebreak.cpp"
            "tests/kp_fuzz.cpp"
          ]
        );
      };

      kp-fuzz =
        pkgs.runCommandWith
          {
            name = "kp-fuzz";
            stdenv = pkgs.clangStdenv;
            derivationArgs = {
              inherit src;
              meta.mainProgram = "kp-fuzz";
            };
          }
          ''
            mkdir -p $out/bin
            $CXX -std=c++17 -O2 -g -Wall -Wextra -Werror \
              -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=all \
              -fno-omit-frame-pointer \
              -I "$src/crengine/include" \
              -o $out/bin/kp-fuzz \
              "$src/tests/kp_fuzz.cpp" "$src/crengine/src/lvkplinebreak.cpp"
          '';

      kp-fuzz-run = pkgs.writeShellApplication {
        name = "kp-fuzz-run";
        runtimeInputs = [
          kp-fuzz
          pkgs.coreutils
        ];
        text = ''
          workdir="''${1:-$PWD/kp-fuzz}"
          [ $# -gt 0 ] && shift
          mkdir -p "$workdir/corpus" "$workdir/crashes"
          # -fork is what makes this a service rather than a run: workers are
          # restarted after a crash, OOM or timeout, each written to crashes/,
          # and the corpus is merged back between generations.
          exec kp-fuzz \
            -fork="$(nproc)" \
            -artifact_prefix="$workdir/crashes/" \
            -max_len=4096 \
            -rss_limit_mb=2048 \
            -timeout=30 \
            -use_value_profile=1 \
            "$@" \
            "$workdir/corpus"
        '';
      };
    in
    {
      packages = { inherit kp-fuzz kp-fuzz-run; };
      apps.kp-fuzz = {
        type = "app";
        program = lib.getExe kp-fuzz-run;
      };
    };
}
