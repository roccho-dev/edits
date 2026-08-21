          install -Dm755 "$TMPDIR/hq-vim.test" "$out/bin/hq-vim.test"
          install -Dm755 "$TMPDIR/hq-vim-smoke" "$out/bin/hq-vim-smoke"
          runHook postInstall
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
        test ! -L "$out/bin/proof-sh"
        ln -s ${hq-vim-proof-runner}/bin/hq-vim.test "$out/bin/hq-vim.test"
        ln -s ${hq-vim-proof-runner}/bin/hq-vim-smoke "$out/bin/hq-vim-smoke"
        ln -s ${hq-vim} "$out/share/hq-vim"
        ln -s ${yegappan-lsp-runtime} "$out/share/yegappan-lsp"
        ln -s ${herdr-proof-config} "$out/share/proof/herdr.toml"
      '';

      proofRunner = pkgs.writeShellApplication {
        name = "vim-nix-proof";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
          pkgs.procps
          pkgs.util-linux
        ];
        text = builtins.concatStringsSep "" (map (p: builtins.readFile (root + p)) [ "/run-proof.parts/00.sh" "/run-proof.parts/01.sh" "/run-proof.parts/02.sh" "/run-proof.parts/03.sh" ]);
      };

      imageRoot = pkgs.buildEnv {
        name = "vim-nix-herdr-hq-image-root";
        paths = [
          composed
          proofRunner
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
          pkgs.procps
          pkgs.util-linux
        ];
        pathsToLink = [ "/bin" "/share" ];
      };

      dockerImage = pkgs.dockerTools.buildLayeredImage {
        name = "roccho/vim-nix-herdr-hq-proof";
        tag = "d83bf4c";
        contents = [ imageRoot pkgs.dockerTools.fakeNss ];
        extraCommands = ''
          mkdir -p work/evidence work/runtime tmp root
          chmod 1777 tmp
        '';
        config = {
          Entrypoint = [ "${proofRunner}/bin/vim-nix-proof" ];
          Cmd = [ "all" ];
          WorkingDir = "/work";
          Env = [
            "PATH=/bin"
            "PROOF_ROOT=${composed}"
            "PROOF_OUTPUT_DIR=/work/evidence"
            "PROOF_RUNTIME_DIR=/work/runtime"
            "HOME=/work/runtime/home"
            "XDG_CONFIG_HOME=/work/runtime/home/.config"
            "XDG_RUNTIME_DIR=/work/runtime/xdg-runtime"
            "XDG_STATE_HOME=/work/runtime/xdg-state"
            "XDG_CACHE_HOME=/work/runtime/xdg-cache"
            "SHELL=/bin/sh"
            "TERM=xterm-256color"
            "LANG=C.UTF-8"
            "LC_ALL=C.UTF-8"
          ];
        };
      };
    in
    {
      packages.${system} = {
        inherit vim;
        inherit herdr;
        inherit proofRunner;
        inherit dockerImage;
        skopeo = pkgs.skopeo;
        hq = hq-binaries;
        default = composed;
        image = dockerImage;
        runner = proofRunner;
      };
    };
}
