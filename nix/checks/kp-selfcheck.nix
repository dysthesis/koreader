{
  pkgs,
  src,
  stdenv,
}:
# `-fno-sanitize-recover=all`: UBSan otherwise reports and continues, so the
# check would pass while flagging undefined behaviour.
# `_GLIBCXX_ASSERTIONS`: bounds-checks the breaker's raw vector indexing.
pkgs.runCommandWith
  {
    name = "kp-selfcheck-${if stdenv.cc.isClang then "clang" else "gcc"}";
    inherit stdenv;
    derivationArgs = { inherit src; };
  }
  ''
    $CXX -std=c++17 -O1 -g -Wall -Wextra -Werror \
      -D_GLIBCXX_ASSERTIONS \
      -fsanitize=address,undefined -fno-sanitize-recover=all \
      -fno-omit-frame-pointer \
      -I "$src/crengine/include" \
      -o kp_selfcheck "$src/tests/kp_selfcheck.cpp" "$src/crengine/src/lvkplinebreak.cpp"
    ./kp_selfcheck
    touch $out
  ''
