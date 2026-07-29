{ self, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    let
      revision =
        if self ? shortRev then
          self.shortRev
        else if self ? dirtyShortRev then
          self.dirtyShortRev
        else
          "dirty";

      # simplification: Reuse nixpkgs' native runtime until koreader-base's
      # vendored dependency graph has reproducible Nix source derivations.
      koreader = pkgs.koreader.overrideAttrs (old: {
        version = "${old.version}-${revision}";
        __intentionallyOverridingVersion = true;

        postInstall = (old.postInstall or "") + ''
          payload="$out/lib/koreader"
          chmod -R u+w "$payload"

          rm -rf "$payload/frontend" "$payload/plugins" "$payload/resources" "$payload/tools"
          cp -R ${self}/frontend "$payload/frontend"
          cp -R ${self}/plugins "$payload/plugins"
          cp -R ${self}/resources "$payload/resources"

          install -Dm644 ${self}/tools/trace_require.lua "$payload/tools/trace_require.lua"
          install -Dm644 ${self}/tools/wbuilder.lua "$payload/tools/wbuilder.lua"
          install -m755 ${self}/reader.lua "$payload/reader.lua"
          install -m644 \
            ${self}/setupkoenv.lua \
            ${self}/defaults.lua \
            ${self}/datastorage.lua \
            "$payload/"
          printf '%s\n' ${lib.escapeShellArg revision} > "$payload/git-rev"
        '';

        passthru = (old.passthru or { }) // {
          upstreamRuntime = pkgs.koreader;
        };
      });
    in
    {
      packages = {
        inherit koreader;
        default = koreader;
      };

      apps.default = {
        type = "app";
        program = "${koreader}/bin/koreader";
      };
    };
}
