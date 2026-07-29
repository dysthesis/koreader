{ pkgs, src }:
# `--header-filter` because crengine's .clang-tidy sets none, so header
# diagnostics are otherwise dropped.
pkgs.runCommand "kp-clang-tidy" { nativeBuildInputs = [ pkgs.clang-tools ]; } ''
  clang-tidy \
    --config-file="${src}/.clang-tidy" \
    --header-filter='lvkplinebreak\.h$' \
    --warnings-as-errors='*' \
    --quiet \
    "${src}/crengine/src/lvkplinebreak.cpp" \
    -- -std=c++17 -I"${src}/crengine/include"
  touch $out
''
