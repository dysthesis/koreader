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
      lastModifiedDate = self.lastModifiedDate or "19700101000000";
      releaseDate = lib.concatStringsSep "-" [
        (builtins.substring 0 4 lastModifiedDate)
        (builtins.substring 4 2 lastModifiedDate)
        (builtins.substring 6 2 lastModifiedDate)
      ];
      releaseEpoch = self.lastModified or 1;
      sourceVersion = "${pkgs.koreader.version}-${revision}";
      # git-rev must be `git describe`-shaped; version.lua's pattern needs the "v".
      releaseVersion = "v${pkgs.koreader.version}-0-g${revision}";

      toolchainVersion = "2025.05";
      koboTargets = {
        kobo = {
          host = "arm-kobo-linux-gnueabihf";
          hash = "sha256-urE2gUgmMIvRou3vrH1QxPxDkKR6oCq/Y21t6uHaHyQ=";
        };
        kobov4 = {
          host = "arm-kobov4-linux-gnueabihf";
          hash = "sha256-0KOkUO6/a2eWH1tzArcd6sZNtnbKRaa4IQhU3Ot6j30=";
        };
        kobov5 = {
          host = "arm-kobov5-linux-gnueabihf";
          hash = "sha256-7VYISlLbmtcMzXokPrkBkW12a//QGwfKDXYni36Ed6I=";
        };
      };

      mkKoboToolchain =
        target:
        { host, hash }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "koxtoolchain-${target}";
          version = toolchainVersion;

          src = pkgs.fetchurl {
            url = "https://github.com/koreader/koxtoolchain/releases/download/${toolchainVersion}/${target}.tar.gz";
            inherit hash;
          };
          sourceRoot = "x-tools/${host}";

          nativeBuildInputs = with pkgs; [
            autoPatchelfHook
            file
            findutils
          ];
          buildInputs = with pkgs; [
            glibc
            stdenv.cc.cc.lib
          ];

          dontConfigure = true;
          dontBuild = true;
          dontFixup = true;

          installPhase = ''
            runHook preInstall

            mkdir -p "$out"
            cp -a . "$out/"
            chmod -R u+w "$out"

            patchShebangs "$out/bin" "$out/libexec" "$out/${host}/bin"
            while IFS= read -r -d "" executable; do
              case "$(${pkgs.file}/bin/file -b "$executable")" in
                *"ELF 64-bit LSB"*x86-64*) autoPatchelf --no-recurse "$executable" ;;
              esac
            done < <(find "$out" -type f -print0)

            runHook postInstall
          '';

          meta.platforms = [ "x86_64-linux" ];
        };

      koboToolchains = lib.mapAttrs mkKoboToolchain koboTargets;

      nativeBuildTools = with pkgs; [
        autoconf
        automake
        bash
        cacert
        cmake
        coreutils
        diffutils
        file
        findutils
        gawk
        gettext
        git
        gnumake
        gnugrep
        gnupatch
        gnused
        gnutar
        gzip
        libtool
        meson
        nasm
        ninja
        p7zip
        perl
        pkg-config
        python3
        unzip
        util-linux
        wget
        xz
      ];

      patchHostShebangs = pkgs.writeShellScript "patch-koreader-host-shebangs" ''
        set -euo pipefail

        while IFS= read -r -d "" script; do
          ${pkgs.gnused}/bin/sed -Ei \
            -e "1s|^#! ?/usr/bin/(env )?python[0-9.]*([[:space:]].*)?$|#!${pkgs.python3}/bin/python3\2|" \
            -e "1s|^#! ?/usr/bin/(env )?perl([[:space:]].*)?$|#!${pkgs.perl}/bin/perl\2|" \
            "$script"
        done < <(
          ${pkgs.findutils}/bin/find "$1" -type f -exec \
            ${pkgs.gnugrep}/bin/grep -EIlZ -m1 \
            '^#! ?/usr/bin/(env )?(python[0-9.]*|perl)([[:space:]].*)?$' {} +
        )
      '';

      crengineArmPatch = pkgs.writeText "crengine-arm-wide-integers.patch" ''
        --- a/base/thirdparty/kpvcrlib/crengine/crengine/src/lvkplinebreak.cpp
        +++ b/base/thirdparty/kpvcrlib/crengine/crengine/src/lvkplinebreak.cpp
        @@ -18,7 +18,44 @@
         namespace {

         typedef std::int64_t Demerits;
        -typedef __int128 WideInt;
        +
        +// Four limbs cover 200 * UINT32_MAX^3 without compiler-specific __int128.
        +struct WideUInt {
        +    std::uint32_t words[4];
        +
        +    explicit WideUInt(std::uint32_t value)
        +        : words{ value, 0, 0, 0 } {}
        +
        +    void multiply(std::uint32_t factor)
        +    {
        +        std::uint64_t carry = 0;
        +        for (int i = 0; i < 4; i++) {
        +            std::uint64_t product = static_cast<std::uint64_t>(words[i])
        +                    * factor + carry;
        +            words[i] = static_cast<std::uint32_t>(product);
        +            carry = product >> 32;
        +        }
        +    }
        +
        +    bool atLeast(const WideUInt & other) const
        +    {
        +        for (int i = 3; i >= 0; i--) {
        +            if (words[i] != other.words[i])
        +                return words[i] > other.words[i];
        +        }
        +        return true;
        +    }
        +};
        +
        +WideUInt cubeTimes(std::uint64_t value, std::uint32_t multiplier)
        +{
        +    std::uint32_t factor = static_cast<std::uint32_t>(value);
        +    WideUInt result(multiplier);
        +    result.multiply(factor);
        +    result.multiply(factor);
        +    result.multiply(factor);
        +    return result;
        +}

         const Demerits MAX_DEMERITS = INT64_MAX / 4;

        @@ -103,7 +140,7 @@
         {
             if (capacity == 0)
                 return negative ? INT_MIN : INT_MAX;
        -    WideInt ratio = static_cast<WideInt>(amount) * 1000 / capacity;
        +    std::int64_t ratio = amount * 1000 / capacity;
             if (ratio > INT_MAX)
                 return negative ? INT_MIN : INT_MAX;
             int result = static_cast<int>(ratio);
        @@ -117,13 +154,20 @@
             if (capacity == 0)
                 return KP_INFINITY;

        -    WideInt a = amount;
        -    WideInt c = capacity;
        -    WideInt numerator = 100 * a * a * a;
        -    WideInt denominator = c * c * c;
        -    if (numerator >= static_cast<WideInt>(KP_INFINITY) * denominator)
        -        return KP_INFINITY;
        -    return static_cast<int>((numerator + denominator / 2) / denominator);
        +    WideUInt scaled_amount_cube = cubeTimes(amount, 200);
        +    WideUInt capacity_cube = cubeTimes(capacity, 1);
        +    int lower = 0;
        +    int upper = KP_INFINITY;
        +    while (lower < upper) {
        +        int middle = lower + (upper - lower + 1) / 2;
        +        WideUInt threshold = capacity_cube;
        +        threshold.multiply(static_cast<std::uint32_t>(2 * middle - 1));
        +        if (scaled_amount_cube.atLeast(threshold))
        +            lower = middle;
        +        else
        +            upper = middle - 1;
        +    }
        +    return lower;
         }

         LineFit fitLine(std::int64_t natural, std::int64_t stretch,
      '';

      # One content-addressed cache keeps koreader-base's downloader unchanged
      # while making its URL and Git inputs available to sandboxed builds.
      thirdpartyCache = pkgs.stdenv.mkDerivation {
        pname = "koreader-kobo-thirdparty";
        version = "2026-07-30";

        src = self;
        nativeBuildInputs = nativeBuildTools ++ [ koboToolchains.kobo ];

        CI = "1";
        GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

        dontConfigure = true;
        dontFixup = true;

        buildPhase = ''
          runHook preBuild

          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"

          make \
            TARGET=kobo \
            USE_NO_CCACHE=1 \
            OUTPUT_DIR="$TMPDIR/build" \
            setup

          mapfile -t downloadTargets < <(
            ninja -C "$TMPDIR/build/cmake" -n all |
              sed -n "s/.*Downloading '\([^']*\)'.*/\1-download/p" |
              sort -u
          )
          if (( "''${#downloadTargets[@]}" == 0 )); then
            echo "No third-party download targets found." >&2
            exit 1
          fi
          ninja -C "$TMPDIR/build/cmake" -j "$NIX_BUILD_CORES" "''${downloadTargets[@]}"

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/downloads" "$out/git"
          touch "$out/git-projects"

          while IFS= read -r -d "" downloadsDir; do
            relative="''${downloadsDir#base/thirdparty/}"
            relative="''${relative%/build/downloads}"

            if [[ -d "$downloadsDir/source/.git" ]]; then
              git -C "$downloadsDir/source" sparse-checkout disable
              git -C "$downloadsDir/source" submodule foreach --recursive git sparse-checkout disable
              mkdir -p "$out/git/$relative"
              cp -a "$downloadsDir/source/." "$out/git/$relative/"
              printf '%s\n' "$relative" >> "$out/git-projects"
            fi

            while IFS= read -r -d "" archive; do
              [[ "''${archive##*/}" == source.lock ]] && continue
              install -Dm644 "$archive" "$out/downloads/$archive"
            done < <(find "$downloadsDir" -maxdepth 1 -type f -print0)
          done < <(find base/thirdparty -type d -path "*/build/downloads" -print0)

          while IFS= read -r -d "" dotGit; do
            repository="''${dotGit%/.git}"
            git -C "$repository" describe --always --tags > "$repository/VERSION"
            git -C "$repository" show -s --format=%ci > "$repository/.koreader-git-timestamp"
            git -C "$repository" show -s --format=%ct > "$repository/.koreader-git-epoch"
          done < <(find "$out/git" -name .git -prune -print0)

          while IFS= read -r -d "" dotGit; do
            rm -rf "$dotGit"
          done < <(find "$out/git" -name .git -prune -print0)
          sort -u -o "$out/git-projects" "$out/git-projects"
          [[ -s "$out/git-projects" ]]

          runHook postInstall
        '';

        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = "sha256-PVAUMu7Fdvg2k7zVjBjFe/UR48bc7QL3koOrjH6k0H8=";
      };

      mkKoboPackage =
        target:
        pkgs.multiStdenv.mkDerivation {
          pname = "koreader-${target}";
          version = sourceVersion;

          src = self;
          nativeBuildInputs = nativeBuildTools ++ [ koboToolchains.${target} ];

          CI = "1";
          dontConfigure = true;
          enableParallelBuilding = true;

          postPatch = ''
            cp -a ${thirdpartyCache}/downloads/. .
            chmod u+w .
            chmod -R u+w base
            patch -p1 < ${crengineArmPatch}

            sed -i \
              -e 's/^RELEASE_DATE :=/RELEASE_DATE ?=/' \
              -e 's/^VERSION :=/VERSION ?=/' \
              -e 's/^RELEASE_EPOCH :=/RELEASE_EPOCH ?=/' \
              Makefile

            while IFS= read -r relative; do
              cmake="base/thirdparty/$relative/CMakeLists.txt"
              perl -0pi -e '
                $count = s/\n[ \t]*DOWNLOAD GIT[ \t]+\S+[ \t\r\n]+\S+//;
                END { die "expected one DOWNLOAD GIT block\n" unless $count == 1; }
              ' "$cmake"
            done < ${thirdpartyCache}/git-projects

            perl -0pi -e '
              $count = s/\n        if\(NOT DEFINED _DOWNLOAD\)\n            message\(FATAL_ERROR "unsupported: with PATCH_FILES and\/or PATCH_COMMAND but no DOWNLOAD"\)\n        endif\(\)//;
              END { die "expected missing-download guard\n" unless $count == 1; }
            ' base/thirdparty/cmake_modules/koreader_external_project.cmake

            substituteInPlace base/thirdparty/cmake_modules/koreader_external_project.cmake \
              --replace-fail \
              '    # Patch source tree:' \
              '    list(APPEND CMD COMMAND ${patchHostShebangs} ''${SOURCE_DIR})
            # Patch source tree:'

            patchShebangs tools/mkrelease.sh base/utils
          '';

          buildPhase = ''
            runHook preBuild

            export HOME="$TMPDIR/home"
            mkdir -p "$HOME" "$TMPDIR/build/thirdparty"

            applyCachedGitMetadata() {
              local source="$1"
              local makefile

              while IFS= read -r -d "" makefile; do
                if grep -qF 'FBINK_VERSION:=$(shell git describe || git rev-parse --short HEAD || cat VERSION)' "$makefile"; then
                  substituteInPlace "$makefile" \
                    --replace-fail \
                    'FBINK_VERSION:=$(shell git describe || git rev-parse --short HEAD || cat VERSION)' \
                    'FBINK_VERSION:=$(shell cat VERSION)'
                fi
              done < <(find "$source" -type f -name Makefile -print0)

              makefile="$source/Makefile"
              [[ -f "$makefile" ]] || return 0
              if grep -qF 'USBMS_VERSION:=$(shell git describe)' "$makefile"; then
                substituteInPlace "$makefile" \
                  --replace-fail 'USBMS_VERSION:=$(shell git describe)' 'USBMS_VERSION:=$(shell cat VERSION)' \
                  --replace-fail 'USBMS_TIMESTAMP:=$(shell git show -s --format=%ci)' 'USBMS_TIMESTAMP:=$(shell cat .koreader-git-timestamp)' \
                  --replace-fail 'USBMS_EPOCH:=$(shell git show -s --format=%ct)' 'USBMS_EPOCH:=$(shell cat .koreader-git-epoch)'
              fi
              if grep -qF 'VERSION=luajson-$(shell git describe --abbrev=4 HEAD 2>/dev/null)' "$makefile"; then
                substituteInPlace "$makefile" \
                  --replace-fail \
                  'VERSION=luajson-$(shell git describe --abbrev=4 HEAD 2>/dev/null)' \
                  'VERSION=luajson-$(shell cat VERSION)'
              fi
            }

            while IFS= read -r relative; do
              name="''${relative##*/}"
              mkdir -p "$TMPDIR/build/thirdparty/$name/source"
              cp -a "${thirdpartyCache}/git/$relative/." "$TMPDIR/build/thirdparty/$name/source/"
              chmod -R u+w "$TMPDIR/build/thirdparty/$name/source"
              applyCachedGitMetadata "$TMPDIR/build/thirdparty/$name/source"
            done < ${thirdpartyCache}/git-projects

            if [[ -d ${thirdpartyCache}/git/fbink ]]; then
              for name in fbdepth libfbink_input; do
                mkdir -p "$TMPDIR/build/thirdparty/$name/source"
                cp -a ${thirdpartyCache}/git/fbink/. "$TMPDIR/build/thirdparty/$name/source/"
                chmod -R u+w "$TMPDIR/build/thirdparty/$name/source"
                applyCachedGitMetadata "$TMPDIR/build/thirdparty/$name/source"
              done
            fi

            make -j "$NIX_BUILD_CORES" \
              TARGET=${target} \
              USE_NO_CCACHE=1 \
              OUTPUT_DIR="$TMPDIR/build" \
              INSTALL_DIR="$TMPDIR/install" \
              VERSION=${lib.escapeShellArg releaseVersion} \
              RELEASE_DATE=${lib.escapeShellArg releaseDate} \
              RELEASE_EPOCH=@${toString releaseEpoch} \
              update

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p "$out"
            for extension in zip tar.xz targz; do
              artifact="koreader-${target}-${releaseVersion}.$extension"
              [[ -s "$artifact" ]]
              install -m644 "$artifact" "$out/"
            done

            runHook postInstall
          '';

          passthru = {
            inherit thirdpartyCache;
            toolchain = koboToolchains.${target};
          };

          meta = {
            description = "KOReader release archives for ${target}";
            homepage = "https://github.com/koreader/koreader";
            license = lib.licenses.agpl3Only;
            platforms = [ "x86_64-linux" ];
          };
        };

      koboPackages = lib.mapAttrs (target: _: mkKoboPackage target) koboTargets;

      # simplification: Keep the native app on nixpkgs' runtime; extend the
      # source-build pipeline when reproducible desktop builds are needed.
      koreader = pkgs.koreader.overrideAttrs (old: {
        version = sourceVersion;
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
          printf '%s\n' ${lib.escapeShellArg releaseVersion} > "$payload/git-rev"
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
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
        inherit (koboPackages) kobo kobov4 kobov5;
      };

      apps.default = {
        type = "app";
        program = "${koreader}/bin/koreader";
      };
    };
}
