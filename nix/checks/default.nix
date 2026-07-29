{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Path literal, not `self + "…"`: lib.fileset rejects strings.
      crengine = ../../base/thirdparty/kpvcrlib/crengine;

      # The line breaker includes only <climits>, <cstdint>, <vector>, so it
      # needs no crengine build. Narrowing the source also stops unrelated
      # edits invalidating the checks.
      src = lib.fileset.toSource {
        root = crengine;
        fileset = lib.fileset.unions (
          map (f: crengine + "/${f}") [
            ".clang-tidy"
            "crengine/include/lvkplinebreak.h"
            "crengine/src/lvkplinebreak.cpp"
            "tests/kp_selfcheck.cpp"
          ]
        );
      };
    in
    {
      checks =
        # crengine is a submodule; `self` omits those unless the flake ref asks
        # for them. Guard so eval still succeeds without.
        if builtins.pathExists (crengine + "/.clang-tidy") then
          {
            kp-selfcheck = import ./kp-selfcheck.nix { inherit pkgs src; };
            kp-clang-tidy = import ./kp-clang-tidy.nix { inherit pkgs src; };
            kp-cppcheck = import ./kp-cppcheck.nix { inherit pkgs src; };
          }
        else
          {
            crengine-submodule = pkgs.runCommand "crengine-submodule-missing" { } ''
              echo "crengine submodule not in the flake source." >&2
              echo "Re-run as: nix flake check '.?submodules=1'" >&2
              exit 1
            '';
          };
    };
}
