{
  description = "Pinned Vim and native Decision Completion fixture";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0ae2bc1419c3f345984c2629e72e7a631820fa4d";
    vim-src = { url = "github:vim/vim/v9.2.0478"; flake = false; };
  };

  outputs = { nixpkgs, vim-src, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
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
    in {
      packages.${system}.vim = vim;
      checks.${system}.fixture = pkgs.runCommand "native-completion-fixture" {
        nativeBuildInputs = [ vim ];
        EDITS_SURFACE_SOURCE = ../../packages/vim/tests/surface.vim;
        EDITS_COMPLETION_SOURCE = ../../packages/vim/tests/candidates.json;
        LANG = "C.UTF-8";
      } ''
        cat > check.vim <<'VIM'
        set nomore
        let s:expected = json_decode(join(readfile($EDITS_COMPLETION_SOURCE), "\n")).contexts
        execute 'source ' . fnameescape($EDITS_SURFACE_SOURCE)
        let s:buffers = filter(getbufinfo(), 'has_key(v:val.variables, "surface_context")')
        call assert_equal(2, len(s:buffers))
        for s:index in range(len(s:buffers))
          execute 'buffer ' . s:buffers[s:index].bufnr
          let s:group = s:expected[s:index]
          call assert_equal(s:group.current, b:surface_current)
          call assert_equal(s:group.context, b:surface_context)
          let s:Complete = eval(&l:completefunc)
          let s:items = call(s:Complete, [0, ""])
          call assert_equal(map(copy(s:group.items), 'v:val.handle'), map(copy(s:items), 'v:val.user_data'))
          call assert_equal(map(copy(s:group.items), 'join(v:val.text, "\n")'), map(copy(s:items), 'v:val.word'))
          call assert_equal(map(copy(s:group.items), 'v:val.label'), map(copy(s:items), 'v:val.abbr'))
          call assert_equal(map(copy(s:group.items), 'v:val.provenance'), map(copy(s:items), 'v:val.menu'))
        endfor
        call assert_equal("", v:errmsg)
        if !empty(v:errors)
          call writefile(v:errors, '/dev/stderr')
          cquit 1
        endif
        call writefile(['fixture loaded'], $out)
        qa!
        VIM
        vim -Nu NONE -i NONE -n -es -S check.vim
        test "$(cat "$out")" = "fixture loaded"

        printf '%s\n' '{"schema":"unsupported","contexts":[]}' > invalid.json
        cat > reject.vim <<'VIM'
        try
          execute 'source ' . fnameescape($EDITS_SURFACE_SOURCE)
        catch /invalid decision-completion.view\/1 fixture/
          cquit 7
        endtry
        call writefile(['unexpected acceptance'], 'invalid-loaded')
        qa!
        VIM
        if EDITS_COMPLETION_SOURCE="$PWD/invalid.json" vim -Nu NONE -i NONE -n -es -S reject.vim; then
          echo "invalid fixture was accepted" >&2
          exit 1
        else
          test "$?" = 7
        fi
        test ! -e invalid-loaded
      '';
    };
}
