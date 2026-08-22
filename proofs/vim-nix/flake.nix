{
  description = "Locked Herdr, Vim, and HQ proof composition";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0ae2bc1419c3f345984c2629e72e7a631820fa4d";
    go-nixpkgs.url = "github:NixOS/nixpkgs/cbb826608f7d081948eeb4ea0211b0cbd867b9d1";
    vim-src = {
      url = "github:vim/vim/v9.2.0478";
      flake = false;
    };
    hq = {
      url = "github:roccho-dev/hq/779a298f4efcff8df60205aaf973cb224388a82b";
      flake = false;
    };
    yegappan-lsp = {
      url = "github:yegappan/lsp/989016ae2ae4cbf304a9ca29478f47fec794493f";
      flake = false;
    };
  };

  outputs = inputs:
    let
      root = ./.;
      source = builtins.concatStringsSep "" (map builtins.readFile [
        ./flake.parts/00.nix
        ./flake.parts/01.nix
      ]);
      build = import (builtins.toFile "vim-nix-proof-flake-body.nix" source);
    in
    (build { inherit root; }).outputs inputs;
}
