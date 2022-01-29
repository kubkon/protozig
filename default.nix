with (import (fetchTarball https://github.com/nixos/nixpkgs/archive/nixpkgs-unstable.tar.gz) {});
let
  inherit (pkgs) stdenv fetchFromGitHub;
in stdenv.mkDerivation (rec {
  name = "protozig";
  buildInputs = with pkgs; [
    protobuf
    nanopb
    gdb
    zig
    zls
  ];
})
