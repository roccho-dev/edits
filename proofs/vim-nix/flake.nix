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
      url = "github:roccho-dev/hq/3118886f34ac5615e8a7732a6297bd41900e21e1";
      flake = false;
    };
    yegappan-lsp = {
      url = "github:yegappan/lsp/989016ae2ae4cbf304a9ca29478f47fec794493f";
      flake = false;
    };
    edits-src = {
      url = "github:roccho-dev/edits/d83bf4c4860e02f37d6b41cc54fe8c881af4c779";
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
