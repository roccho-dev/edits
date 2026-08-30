          install -Dm755 "$TMPDIR/hq-vim.test" "$out/bin/hq-vim.test"
          install -Dm755 "$TMPDIR/hq-vim-smoke" "$out/bin/hq-vim-smoke"
          runHook postInstall
        '';
      };

      composed = pkgs.runCommand "herdr-vim-hq-proof" { } ''
        mkdir -p "$out/bin" "$out/share/proof"
        ln -s ${herdr}/bin/herdr "$out/bin/herdr"
        ln -s ${vim}/bin/vim "$out/bin/vim"
        ln -s ${vim}/share/vim "$out/share/vim"
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
        ln -s ${source-manifest} "$out/share/proof/source.json"
        install -Dm644 ${edits-src + "/proofs/vim-nix/fixtures/runtime-world.jsonl"} "$out/share/proof/runtime-world.jsonl"
        install -Dm644 ${edits-src + "/proofs/vim-nix/fixtures/runtime-accepted.jsonl"} "$out/share/proof/runtime-accepted.jsonl"
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

      historyProofRunner = pkgs.writeShellApplication {
        name = "vim-nix-history-proof";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.jq
          pkgs.procps
          pkgs.util-linux
        ];
        text = builtins.readFile (root + "/run-history-proof.sh");
      };

      editsLauncher = pkgs.writeShellApplication {
        name = "edits";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.jq
          pkgs.procps
        ];
        text = builtins.readFile (root + "/run-edits.sh");
      };

      editsSmoke = pkgs.writeShellApplication {
        name = "edits-smoke";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnugrep
          pkgs.jq
          pkgs.procps
          pkgs.util-linux
        ];
        text = builtins.readFile (root + "/run-edits-smoke.sh");
      };

      editsRoleWrappers = pkgs.runCommand "edits-role-wrappers-${editsTag}" { } ''
        install -Dm755 ${builtins.path {
          name = "edits-client";
          path = edits-src + "/cmd/edits-client/edits-client";
        }} "$out/bin/edits-client"
        install -Dm755 ${builtins.path {
          name = "edits-service";
          path = edits-src + "/cmd/edits-service/edits-service";
        }} "$out/bin/edits-service"
        install -Dm755 ${builtins.path {
          name = "edits-mux";
          path = edits-src + "/cmd/edits-mux/edits-mux";
        }} "$out/bin/edits-mux"
      '';

      editsAssets = pkgs.runCommand "edits-operator-console-assets-${editsTag}" { } ''
        install -Dm644 ${root + "/default-world.jsonl"} "$out/share/edits/default-world.jsonl"
      '';

      candidatePython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pytest ]);
      candidateCi = pkgs.writeTextFile {
        name = "edits-candidate-oci";
        executable = true;
        text = "#!${candidatePython}/bin/python\n" + builtins.readFile (root + "/candidate_ci.py");
      };

      imageRoot = pkgs.buildEnv {
        name = "vim-nix-herdr-hq-image-root";
        paths = [
          composed
          proofRunner
          historyProofRunner
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
        tag = editsTag;
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

      interactiveImageRoot = pkgs.buildEnv {
        name = "edits-operator-console-image-root-${editsTag}";
        paths = [ imageRoot editsLauncher editsSmoke editsAssets editsRoleWrappers ];
        pathsToLink = [ "/bin" "/share" ];
      };

      interactiveImage = pkgs.dockerTools.buildLayeredImage {
        name = "roccho/edits";
        tag = interactiveTag;
        contents = [ interactiveImageRoot pkgs.dockerTools.fakeNss ];
        extraCommands = ''
          mkdir -p home/dev work/repos tmp
          chown -R 1000:1000 home/dev work/repos
          chmod 0700 home/dev
          chmod 0755 work work/repos
          chmod 1777 tmp
        '';
        config = {
          Entrypoint = [ "/bin/edits" ];
          WorkingDir = "/work/repos";
          User = "1000:1000";
          Env = [
            "PATH=/bin"
            "HOME=/home/dev"
            "XDG_CONFIG_HOME=/home/dev/.config"
            "XDG_STATE_HOME=/home/dev/.local/state"
            "XDG_CACHE_HOME=/home/dev/.cache"
            "XDG_RUNTIME_DIR=/tmp"
            "PROOF_ROOT=${composed}"
            "PROOF_OUTPUT_DIR=/tmp/proof-evidence"
            "PROOF_RUNTIME_DIR=/tmp/proof-runtime"
            "PROOF_HISTORY_OUTPUT_DIR=/tmp/history-evidence"
            "PROOF_HISTORY_RUNTIME_DIR=/tmp/history-runtime"
            "HERDR_CONFIG_PATH=${composed}/share/proof/herdr.toml"
            "VIMRUNTIME=${composed}/share/vim/vim92"
            "EDITS_HERDR_BIN=/bin/herdr"
            "EDITS_VIM_BIN=/bin/vim"
            "EDITS_HQ_BIN=/bin/hq"
            "SHELL=/bin/sh"
            "TERM=xterm-256color"
            "LANG=C.UTF-8"
            "LC_ALL=C.UTF-8"
          ];
        };
      };

      interactiveOciImage = pkgs.runCommand "edits-operator-console-${interactiveTag}.oci.tar" {
        nativeBuildInputs = [ pkgs.skopeo ];
      } ''
        rm -rf "$out"
        skopeo --insecure-policy copy \
          "docker-archive:${interactiveImage}" \
          "oci-archive:$out:roccho/edits:${interactiveTag}"
      '';

      interactiveImageRef = pkgs.writeText "edits-operator-console-image-ref-${interactiveTag}" "roccho/edits:${interactiveTag}\n";

      interactiveWindowsKit = pkgs.runCommand "edits-operator-console-${interactiveTag}.windows.zip" {
        nativeBuildInputs = [ candidatePython ];
      } ''
        ${candidatePython}/bin/python ${root + "/windows_kit.py"} \
          --docker-archive ${interactiveImage} \
          --image-ref "roccho/edits:${interactiveTag}" \
          --source-revision "${editsRevision}" \
          --output "$out"
      '';
    in
    {
      packages.${system} = {
        inherit vim;
        inherit herdr;
        inherit proofRunner;
        inherit historyProofRunner;
        inherit dockerImage;
        inherit editsLauncher;
        inherit editsSmoke;
        inherit editsRoleWrappers;
        inherit interactiveImage;
        inherit interactiveOciImage;
        inherit interactiveImageRef;
        inherit interactiveWindowsKit;
        inherit candidateCi;
        skopeo = pkgs.skopeo;
        hq = hq-binaries;
        default = composed;
        image = dockerImage;
        runner = proofRunner;
        candidate = interactiveImage;
        candidateOci = interactiveOciImage;
        windowsKit = interactiveWindowsKit;
      };
      apps.${system}.candidate = {
        type = "app";
        program = "${candidateCi}";
      };
    };
}
