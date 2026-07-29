{ pkgs, src }:
# `-fno-sanitize-recover=all`: UBSan otherwise reports and continues, so the
# check would pass while flagging undefined behaviour.
pkgs.runCommandWith
  {
    name = "kp-selfcheck";
    stdenv = pkgs.clangStdenv;
    derivationArgs = { inherit src; };
  }
  ''
    $CXX -std=c++17 -O1 -g -Wall -Wextra -Werror \
      -fsanitize=address,undefined -fno-sanitize-recover=all \
      -fno-omit-frame-pointer \
      -I "$src/crengine/include" \
      -o kp_selfcheck "$src/tests/kp_selfcheck.cpp" "$src/crengine/src/lvkplinebreak.cpp"
    ./kp_selfcheck
    touch $out
  ''
