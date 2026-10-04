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
        EDITS_VIM_TREE = ../../packages/vim;
        LANG = "C.UTF-8";
      } ''
        # Keep the real import relationship for both fixture and product.
        cp -r "$EDITS_VIM_TREE" vim-tree
        chmod -R u+w vim-tree
        export EDITS_SURFACE_SOURCE="$PWD/vim-tree/tests/surface.vim"
        export EDITS_COMPLETION_SOURCE="$PWD/vim-tree/tests/candidates.json"
        cat > vim-tree/tests/check.vim <<'VIM'
        set nomore hidden
        call setline(1, ["existing modified", "multiline buffer"])
        file owned-import-buffer
        let s:global = [&g:completeopt, &g:completefunc]
        let s:initial = getline(1, "$")
        let s:undo = undotree()
        let s:before_buffers = len(getbufinfo())
        import "../surface.vim" as surface
        call assert_equal(s:initial, getline(1, "$"))
        call assert_equal(s:undo, undotree())
        call assert_equal(s:before_buffers, len(getbufinfo()))
        call s:surface.Attach()
        call assert_equal(s:initial, getline(1, "$"))
        call assert_equal(s:undo, undotree())
        let s:NoProvider = eval(&l:completefunc)
        call assert_equal(-3, call(s:NoProvider, [1, ""]))
        call assert_equal(s:initial, getline(1, "$"))
        enew
        execute "source " . fnameescape($EDITS_SURFACE_SOURCE)
        let s:buffers = filter(getbufinfo(), 'has_key(v:val.variables, "surface_context")')
        call assert_equal(2, len(s:buffers))
        let g:View = json_decode(join(readfile($EDITS_COMPLETION_SOURCE), "\n"))
        for s:group in g:View.contexts
          let s:group.current = {"generation": [s:group.current]}
          let s:group.context = {"goal": {"text": [s:group.context]}}
        endfor
        let s:original = deepcopy(g:View)
        let g:Inputs = []
        let g:Fault = ""
        function g:Query(raw)
          if g:Fault == "querythrow"
            throw "query failure"
          elseif g:Fault == "queryshape"
            return {"start": 0}
          elseif g:Fault == "querytype"
            return 0
          elseif g:Fault == "querystart"
            return {"start": -1, "input": 0}
          elseif g:Fault == "querybyte"
            return {"start": 1, "input": 0}
          elseif g:Fault == "queryworking"
            call setline(1, "query changed Working")
          elseif g:Fault == "queryswap"
            let b:surface_query = function("g:OtherQuery")
          endif
          let l:input = {"opaque": [deepcopy(a:raw.working)]}
          let a:raw.working[0] = "changed query argument"
          let a:raw.current.generation[0] = "changed query argument"
          let a:raw.context.goal.text[0] = "changed query argument"
          return {"start": a:raw.cursor.column - 1, "input": l:input}
        endfunction
        function g:OtherQuery(raw)
          return {"start": a:raw.cursor.column - 1, "input": 0}
        endfunction
        function g:Acquire(raw)
          call add(g:Inputs, deepcopy(a:raw))
          if g:Fault == "throw"
            throw "acquisition failure"
          elseif g:Fault == "invalid"
            return {"schema": "unsupported", "contexts": []}
          elseif g:Fault == "wrongtype"
            return 0
          elseif g:Fault == "source"
            let b:surface_source = {"changed": []}
          elseif g:Fault == "current"
            let b:surface_current = {"changed": []}
          elseif g:Fault == "context"
            let b:surface_context = {"changed": []}
          elseif g:Fault == "working"
            call setline(1, "changed Working")
          elseif g:Fault == "buffer"
            execute "buffer " . g:Other
          elseif g:Fault == "acquire"
            let b:surface_acquire = function("g:OtherAcquire")
          endif
          let a:raw.working[0] = "changed argument"
          let a:raw.input.opaque[0][0] = "changed argument"
          return g:View
        endfunction
        function g:OtherAcquire(raw)
          return g:View
        endfunction
        function s:Run()
          let l:Complete = eval(&l:completefunc)
          let l:start = call(l:Complete, [1, ""])
          if l:start < 0
            return []
          endif
          return call(l:Complete, [0, ""])
        endfunction
        let s:phases = []
        for s:index in range(2)
          execute "buffer " . s:buffers[s:index].bufnr
          let s:group = g:View.contexts[s:index]
          let b:surface_source = {"binding": [s:index]}
          let b:surface_current = deepcopy(s:group.current)
          let b:surface_context = deepcopy(s:group.context)
          let b:surface_query = function("g:Query")
          let b:surface_acquire = function("g:Acquire")
          for s:working in [["first Working"], ["次のWorking", "全行も渡す"]]
            call deletebufline(bufnr(), 1, "$")
            call setline(1, s:working)
            call cursor(1, 1)
            let s:items = s:Run()
            call assert_equal(s:working, g:Inputs[-1].working)
            call assert_equal(s:working, b:surface_base.working)
            call assert_equal({"opaque": [s:working]}, g:Inputs[-1].input)
            call assert_equal(b:surface_current, g:Inputs[-1].current)
            call assert_equal(b:surface_context, g:Inputs[-1].context)
            call assert_equal(map(copy(s:group.items), "v:val.handle"), map(copy(s:items), "v:val.user_data"))
            call assert_equal(map(copy(s:group.items), 'join(v:val.text, "\n")'), map(copy(s:items), "v:val.word"))
            call assert_equal(s:original, g:View)
            call assert_equal([], call(eval(&l:completefunc), [0, ""]), "pending consumed once")
          endfor
        endfor
        call add(s:phases, "two contexts/full Working")
        let s:SameItems = s:Run()
        let b:surface_acquire = function("g:OtherAcquire")
        call assert_equal(s:SameItems, s:Run(), "provider swap/order unchanged")
        let b:surface_acquire = function("g:Acquire")
        let s:owner = bufnr()
        let g:Other = s:buffers[0].bufnr
        let s:group = g:View.contexts[-1]
        let s:prior = {"handle": {"origin": "previous selection"}, "base": {"working": ["earlier"]}}
        let b:surface_selection = deepcopy(s:prior)
        for g:Fault in ["source", "current", "context", "working", "buffer", "acquire", "throw", "invalid", "wrongtype", "setting", "querythrow", "queryshape", "querytype", "querystart", "querybyte", "queryworking", "queryswap"]
          execute "buffer " . s:owner
          let b:surface_source = {"binding": [1]}
          let b:surface_current = deepcopy(s:group.current)
          let b:surface_context = deepcopy(s:group.context)
          let b:surface_query = function("g:Query")
          let b:surface_acquire = g:Fault == "setting" ? 0 : function("g:Acquire")
          call deletebufline(bufnr(), 1, "$")
          call setline(1, "あ second Working")
          call cursor(1, 1)
          if g:Fault == "querybyte"
            call cursor(1, 4)
          endif
          let s:before = len(g:Inputs)
          call assert_equal([], s:Run(), g:Fault)
          call assert_equal(s:before + (index(["setting", "querythrow", "queryshape", "querytype", "querystart", "querybyte", "queryworking", "queryswap"], g:Fault) < 0), len(g:Inputs), g:Fault . " reached")
          call assert_equal({}, getbufvar(s:owner, "surface_base"), g:Fault . " inactive")
          call assert_equal(s:prior, getbufvar(s:owner, "surface_selection"), g:Fault . " origin")
          call assert_equal([g:Fault == "working" ? "changed Working" : g:Fault == "queryworking" ? "query changed Working" : "あ second Working"], getbufline(s:owner, 1, "$"), g:Fault . " Working")
          call add(s:phases, g:Fault)
        endfor
        execute "buffer " . s:owner
        let g:Fault = ""
        let b:surface_query = function("g:Query")
        let b:surface_acquire = function("g:Acquire")
        call deletebufline(bufnr(), 1, "$")
        call setline(1, ["named dirty", "multiline Working"])
        execute "file owned-existing-buffer"
        let s:body = getline(1, "$")
        let s:undo = undotree()
        let s:origin = deepcopy(b:surface_selection)
        call s:surface.Attach()
        call s:surface.Attach()
        call assert_equal(s:body, getline(1, "$"))
        call assert_equal(s:undo, undotree())
        call assert_equal(s:origin, b:surface_selection)
        call assert_equal(1, len(autocmd_get({"group": "edits_surface", "event": "CompleteDonePre", "pattern": "<buffer=" . bufnr() . ">"})))
        call assert_equal(s:global, [&g:completeopt, &g:completefunc])
        call assert_equal(s:original, g:View)
        call add(s:phases, "attach named dirty/repeat")
        call assert_equal(["two contexts/full Working", "source", "current", "context", "working", "buffer", "acquire", "throw", "invalid", "wrongtype", "setting", "querythrow", "queryshape", "querytype", "querystart", "querybyte", "queryworking", "queryswap", "attach named dirty/repeat"], s:phases)
        call assert_equal("", v:errmsg)
        if !empty(v:errors)
          call writefile(v:errors, "/dev/stderr")
          cquit 1
        endif
        call writefile(["product and fixture loaded"], $out)
        qa!
        VIM
        vim -Nu NONE -i NONE -n -es -S vim-tree/tests/check.vim
        test "$(cat "$out")" = "product and fixture loaded"

        printf '%s\n' '{"schema":"unsupported","contexts":[]}' > invalid.json
        cat > reject.vim <<'VIM'
        try
          execute 'source ' . fnameescape($EDITS_SURFACE_SOURCE)
        catch /invalid decision-completion.view\/1/
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
