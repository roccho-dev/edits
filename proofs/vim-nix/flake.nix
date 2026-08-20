let
  root = ./.;
  source = builtins.concatStringsSep "" (map builtins.readFile [
    ./flake.parts/00.nix
    ./flake.parts/01.nix
  ]);
  build = import (builtins.toFile "vim-nix-proof-flake-body.nix" source);
in
build { inherit root; }
