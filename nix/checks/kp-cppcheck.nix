{ pkgs, src }:
# Flags mirror CPPCHECK_FLAGS in crengine/CMakeLists.txt, minus the
# out-of-memory suppressions (they only fire on crengine's allocator).
# `style` is left off: it is mostly "prefer <algorithm>" noise.
pkgs.runCommand "kp-cppcheck" { nativeBuildInputs = [ pkgs.cppcheck ]; } ''
  cppcheck \
    --check-level=exhaustive \
    --enable=warning,performance,portability \
    --error-exitcode=2 \
    --inline-suppr \
    --platform=unix64 \
    --std=c++17 \
    --template=gcc \
    --suppress=missingIncludeSystem \
    --suppress=checkersReport \
    -I "${src}/crengine/include" \
    "${src}/crengine/src/lvkplinebreak.cpp" \
    "${src}/tests/kp_selfcheck.cpp"
  touch $out
''
