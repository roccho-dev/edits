{ root }:
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

  outputs = inputs@{ self, nixpkgs, go-nixpkgs, vim-src, hq, yegappan-lsp, edits-src, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      goPkgs = import go-nixpkgs { inherit system; };
      go123 = assert goPkgs.go_1_23.version == "1.23.12"; goPkgs.go_1_23;
      herdr = assert pkgs.herdr.version == "0.8.0"; pkgs.herdr;
      herdr-proof-config = pkgs.writeText "herdr-proof-config.toml" ''
        onboarding = false
      '';

      vim = pkgs.vim.overrideAttrs (old: {
        pname = "vim";
        version = "9.2.0478";
        src = vim-src;
        postInstall = (old.postInstall or "") + ''
          test -d "$out/share/vim/vim92"
          "$out/bin/vim" -Nu NONE -n -i NONE -es \
            '+if v:version != 902 || !has("patch-9.2.478") || !has("vim9script") || !has("channel") || !has("timers") || !has("popupwin") || !has("insert_expand") || !has("multi_byte") || !has("terminal") | cquit 1 | endif' \
            '+quitall!'
        '';
      });

      hq-binaries = pkgs.stdenvNoCC.mkDerivation {
        pname = "hq";
        version = "3118886f34ac5615e8a7732a6297bd41900e21e1";
        src = hq;
        nativeBuildInputs = [ go123 ];
        buildPhase = ''
          runHook preBuild
          export CGO_ENABLED=0 GOPROXY=off HOME="$TMPDIR" GOCACHE="$TMPDIR/go-build"
          go version | grep -Fx 'go version go1.23.12 linux/amd64'
          mkdir -p "$TMPDIR/bin"
          go test ./...
          go build -trimpath -o "$TMPDIR/bin/hq" ./cmd/hq
          go build -trimpath -o "$TMPDIR/bin/hq-worker" ./cmd/hq-worker
          go build -trimpath -o "$TMPDIR/bin/hq-worker-proof-provider" ./cmd/hq-worker-proof-provider
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          install -Dm755 "$TMPDIR/bin/hq" "$out/bin/hq"
          install -Dm755 "$TMPDIR/bin/hq-worker" "$out/bin/hq-worker"
          install -Dm755 "$TMPDIR/bin/hq-worker-proof-provider" "$out/bin/hq-worker-proof-provider"
          runHook postInstall
        '';
      };

      hq-vim = pkgs.runCommand "hq-vim" { } ''
        install -Dm644 ${builtins.path {
          name = "hq.vim";
          path = edits-src + "/packages/hq-vim/plugin/hq.vim";
        }} "$out/plugin/hq.vim"
        install -Dm644 ${builtins.path {
          name = "hq-autoload.vim";
          path = edits-src + "/packages/hq-vim/autoload/hq.vim";
        }} "$out/autoload/hq.vim"
        cp -R ${edits-src + "/packages/hq-vim/testdata"} "$out/testdata"
      '';

      yegappan-lsp-runtime = pkgs.runCommand "yegappan-lsp" { } ''
        cp -R ${yegappan-lsp} "$out"
        chmod -R u+w "$out"
      '';

      hq-vim-proof-runner = pkgs.stdenvNoCC.mkDerivation {
        pname = "hq-vim-proof-runner";
        version = "d83bf4c4860e02f37d6b41cc54fe8c881af4c779";
        src = edits-src;
        patches = [ (root + "/hq-vim-native-popup-proof.patch") ];
        nativeBuildInputs = [ go123 ];
        buildPhase = ''
          runHook preBuild
          export CGO_ENABLED=0 GOPROXY=off HOME="$TMPDIR" GOCACHE="$TMPDIR/go-build"
          cd packages/hq-vim
          VIM_EXE=${vim}/bin/vim \
            VIM9_LSP_PATH=${yegappan-lsp-runtime} \
            go test ./...
          go test -c -trimpath -o "$TMPDIR/hq-vim.test" .
          go build -trimpath -o "$TMPDIR/hq-vim-smoke" ./cmd/hq-vim-smoke
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
