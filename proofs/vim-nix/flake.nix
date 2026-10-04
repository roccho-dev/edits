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

        let s:view = json_decode(join(readfile($EDITS_COMPLETION_SOURCE), "\n"))
        for s:group in s:view.contexts
          let s:group.current = {"generation": [s:group.current]}
          let s:group.context = {"goal": {"text": [s:group.context]}}
        endfor
        let s:original = deepcopy(s:view)
        let s:inputs = []
        let s:fault = ""
        function s:Acquire(base)
          call add(s:inputs, deepcopy(a:base))
          if s:fault == "throw"
            throw "controlled acquisition failure"
          elseif s:fault == "invalid"
            return {"schema": "unsupported", "contexts": []}
          elseif s:fault == "wrongtype"
            return 0
          elseif s:fault == "source"
            let $EDITS_COMPLETION_SOURCE = "changed-source"
          elseif s:fault == "current"
            let b:surface_current = {"changed": []}
          elseif s:fault == "context"
            let b:surface_context = {"changed": []}
          elseif s:fault == "working"
            call setline(1, "changed Working")
          elseif s:fault == "buffer"
            execute "buffer " . s:other
          elseif s:fault == "acquire"
            let b:surface_acquire = function("s:Other")
          endif
          let a:base.working[0] = "changed argument"
          let a:base.current.generation[0] = "changed argument"
          let a:base.context.goal.text[0] = "changed argument"
          return s:view
        endfunction
        function s:Other(base)
          return s:view
        endfunction
        let s:source = $EDITS_COMPLETION_SOURCE
        let s:phases = []
        for s:index in range(len(s:buffers))
          execute "buffer " . s:buffers[s:index].bufnr
          let b:surface_current = deepcopy(s:view.contexts[s:index].current)
          let b:surface_context = deepcopy(s:view.contexts[s:index].context)
          let b:surface_acquire = function("s:Acquire")
          let s:Complete = eval(&l:completefunc)
          for s:working in [["first Working"], ["次のWorking", "全行も渡す"]]
            call deletebufline(bufnr(), 2, "$")
            call setline(1, s:working)
            let s:items = call(s:Complete, [0, ""])
            call assert_equal(s:working, s:inputs[-1].working)
            call assert_equal(s:working, b:surface_base.working)
            call assert_equal(b:surface_current, s:inputs[-1].current)
            call assert_equal(b:surface_context, s:inputs[-1].context)
            call assert_equal(b:surface_current, b:surface_base.current)
            call assert_equal(b:surface_context, b:surface_base.context)
            call assert_equal(map(copy(s:expected[s:index].items), "v:val.handle"), map(copy(s:items), "v:val.user_data"))
            call assert_equal(map(copy(s:expected[s:index].items), 'join(v:val.text, "\n")'), map(copy(s:items), "v:val.word"))
            call assert_equal(s:original, s:view)
          endfor
        endfor
        call add(s:phases, "two contexts/two Working inputs")
        let s:owner = bufnr()
        let s:group = s:view.contexts[-1]
        let s:prior = {"handle": {"origin": "previous selection"}, "base": {"working": ["earlier Working"]}}
        let b:surface_selection = deepcopy(s:prior)
        let s:other = s:buffers[0].bufnr
        for s:fault in ["source", "current", "context", "working", "buffer", "acquire", "throw", "invalid", "wrongtype", "setting"]
          execute "buffer " . s:owner
          let $EDITS_COMPLETION_SOURCE = s:source
          let b:surface_current = deepcopy(s:group.current)
          let b:surface_context = deepcopy(s:group.context)
          let b:surface_acquire = s:fault == "setting" ? 0 : function("s:Acquire")
          call deletebufline(bufnr(), 2, "$")
          call setline(1, "second Working")
          let s:before = len(s:inputs)
          let s:items = call(s:Complete, [0, ""])
          call assert_equal([], s:items, s:fault)
          call assert_equal(s:before + (s:fault != "setting"), len(s:inputs), s:fault . " reached")
          call assert_equal({}, getbufvar(s:owner, "surface_base"), s:fault . " inactive")
          call assert_equal(s:prior, getbufvar(s:owner, "surface_selection"), s:fault . " origin")
          call assert_equal([s:fault == "working" ? "changed Working" : "second Working"], getbufline(s:owner, 1, "$"), s:fault . " Working")
          call add(s:phases, s:fault)
        endfor
        execute "buffer " . s:owner
        let $EDITS_COMPLETION_SOURCE = s:source
        unlet b:surface_acquire
        let b:surface_current = deepcopy(s:expected[-1].current)
        let b:surface_context = deepcopy(s:expected[-1].context)
        call assert_equal(len(s:group.items), len(call(s:Complete, [0, ""])))
        call assert_equal(["two contexts/two Working inputs", "source", "current", "context", "working", "buffer", "acquire", "throw", "invalid", "wrongtype", "setting"], s:phases)
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
