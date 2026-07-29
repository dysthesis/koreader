{
  description = "KOReader development and package flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./nix/checks
        ./nix/shell.nix
        ./nix/formatter.nix
        ./nix/package.nix
      ];

      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
}
