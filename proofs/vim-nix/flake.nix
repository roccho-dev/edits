{
  description = "Locked Herdr, Vim, HQ, and OCI proof composition";

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
      imageName = "vim-nix-herdr-hq";
      imageTag = "d83bf4c4860e";

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
        patches = [ ./hq-vim-native-popup-proof.patch ];
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
          install -Dm755 "$TMPDIR/hq-vim.test" "$out/bin/hq-vim.test"
          install -Dm755 "$TMPDIR/hq-vim-smoke" "$out/bin/hq-vim-smoke"
          runHook postInstall
        '';
      };

      proof-runner = pkgs.writeShellApplication {
        name = "run-vim-nix-proof";
        runtimeInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.jq
        ];
        text = ''
          export PROOF_SOURCE_DIR=${./run-proof}
          ${builtins.readFile ./run-proof.sh}
        '';
      };

      composed = pkgs.runCommand "herdr-vim-hq-proof" { } ''
        mkdir -p "$out/bin" "$out/share/proof"
        ln -s ${herdr}/bin/herdr "$out/bin/herdr"
        ln -s ${vim}/bin/vim "$out/bin/vim"
        ln -s ${hq-binaries}/bin/hq "$out/bin/hq"
        ln -s ${hq-binaries}/bin/hq-worker "$out/bin/hq-worker"
        ln -s ${hq-binaries}/bin/hq-worker-proof-provider "$out/bin/hq-worker-proof-provider"
        cp ${hq-binaries}/bin/hq-worker-proof-provider "$out/bin/proof-sh"
        test -f "$out/bin/proof-sh"
        test ! -L "$out/bin/proof-sh"
        ln -s ${hq-vim-proof-runner}/bin/hq-vim.test "$out/bin/hq-vim.test"
        ln -s ${hq-vim-proof-runner}/bin/hq-vim-smoke "$out/bin/hq-vim-smoke"
        ln -s ${proof-runner}/bin/run-vim-nix-proof "$out/bin/run-vim-nix-proof"
        ln -s ${hq-vim} "$out/share/hq-vim"
        ln -s ${yegappan-lsp-runtime} "$out/share/yegappan-lsp"
        ln -s ${herdr-proof-config} "$out/share/proof/herdr.toml"
      '';

      shell-root = pkgs.runCommand "vim-nix-proof-shell-root" { } ''
        mkdir -p "$out/bin"
        ln -s ${pkgs.bash}/bin/bash "$out/bin/sh"
      '';

      image-root = pkgs.buildEnv {
        name = "vim-nix-herdr-hq-image-root";
        paths = [ composed shell-root pkgs.dockerTools.fakeNss ];
        pathsToLink = [ "/bin" "/share" "/etc" ];
      };

      docker-image = pkgs.dockerTools.buildImage {
        name = imageName;
        tag = imageTag;
        created = "1970-01-01T00:00:01Z";
        copyToRoot = image-root;
        extraCommands = ''
          mkdir -m 1777 tmp
          mkdir -m 0777 evidence
        '';
        config = {
          Entrypoint = [
            "${composed}/bin/run-vim-nix-proof"
            "--proof-root"
            "${composed}"
          ];
          Cmd = [ "--mode" "image" "--output" "/evidence" ];
          Env = [
            "PATH=/bin"
            "LANG=C.UTF-8"
            "LC_ALL=C.UTF-8"
            "TERM=xterm-256color"
          ];
          WorkingDir = "/tmp";
          Labels = {
            "org.opencontainers.image.title" = imageName;
            "org.opencontainers.image.revision" = "d83bf4c4860e02f37d6b41cc54fe8c881af4c779";
            "org.opencontainers.image.source" = "https://github.com/roccho-dev/edits/issues/74";
            "org.opencontainers.image.version" = imageTag;
          };
        };
      };

      oci = pkgs.runCommand "vim-nix-herdr-hq-oci-${imageTag}" {
        nativeBuildInputs = [ pkgs.coreutils pkgs.skopeo ];
        passthru = {
          inherit composed docker-image imageName imageTag;
        };
      } ''
        set -euo pipefail
        export TMPDIR="$NIX_BUILD_TOP/tmp"
        mkdir -p "$TMPDIR" "$out"
        cp ${docker-image} "$out/vim-nix-herdr-hq.docker.tar"
        skopeo --tmpdir "$TMPDIR" copy --insecure-policy \
          "docker-archive:${docker-image}" \
          "oci-archive:$out/vim-nix-herdr-hq.oci.tar:${imageName}:${imageTag}"
        skopeo --tmpdir "$TMPDIR" inspect --raw \
          "oci-archive:$out/vim-nix-herdr-hq.oci.tar" > "$out/manifest.raw.json"
        skopeo --tmpdir "$TMPDIR" inspect \
          "oci-archive:$out/vim-nix-herdr-hq.oci.tar" > "$out/inspect.json"
        printf '%s\n' '${imageName}:${imageTag}' > "$out/image.ref"
        printf '%s\n' '${imageTag}' > "$out/image.tag"
        sha256sum "$out/vim-nix-herdr-hq.docker.tar" \
          "$out/vim-nix-herdr-hq.oci.tar" > "$out/SHA256SUMS"
      '';
    in
    {
      packages.${system} = {
        inherit vim herdr;
        hq = hq-binaries;
        default = composed;
        docker = docker-image;
        inherit oci;
        skopeo = pkgs.skopeo;
      };
    };
}
