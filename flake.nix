{
  description = "Pinned Vim with installed semcmp completion";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0ae2bc1419c3f345984c2629e72e7a631820fa4d";
    ops.url = "github:roccho-dev/ops/91cdb00316602c88da217502e368f19e90647330";
    vim-src = { url = "github:vim/vim/v9.2.0478"; flake = false; };
  };

  outputs = { nixpkgs, vim-src, ops, ... }:
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
      semcmp = ops.packages.${system}.semcmp;
      edits = pkgs.runCommand "edits" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        mkdir -p "$out/share/edits/vim" "$out/bin"
        cp ${./packages/vim/surface.vim} "$out/share/edits/vim/surface.vim"
        cp ${./packages/vim/semcmp.vim} "$out/share/edits/vim/semcmp.vim"
        cp ${./packages/vim/entry.vim} "$out/share/edits/vim/entry.vim"
        makeWrapper ${vim}/bin/vim "$out/bin/edits" \
          --set EDITS_SEMCMP_BIN "${semcmp}/bin/semcmp" \
          --add-flags "-S $out/share/edits/vim/entry.vim"
      '';
    in {
      packages.${system} = { inherit vim edits; default = edits; };
      checks.${system} = {
      fixture = pkgs.runCommand "native-completion-fixture" {
        nativeBuildInputs = [ vim ];
        EDITS_VIM_TREE = ./packages/vim;
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
        let s:info_view = deepcopy(g:View)
        let s:info_view.contexts[0].items[0].info = "meaning information only"
        call assert_equal(s:info_view, s:surface.ValidateView(s:info_view))
        for s:bad in [0, ["not a string"]]
          let s:info_view.contexts[0].items[0].info = s:bad
          let s:refused = 0
          try
            call s:surface.ValidateView(s:info_view)
          catch /invalid view candidate/
            let s:refused = 1
          endtry
          call assert_equal(1, s:refused, "invalid info refused")
        endfor
        let s:info_view = deepcopy(g:View)
        let s:info_view.contexts[0].items[0].unknown = "not allowed"
        let s:refused = 0
        try
          call s:surface.ValidateView(s:info_view)
        catch /invalid view candidate/
          let s:refused = 1
        endtry
        call assert_equal(1, s:refused, "unknown key refused")
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
        function g:Acquire(raw, Deliver)
          call add(g:Inputs, deepcopy(a:raw))
          if g:Fault == "throw"
            throw "acquisition failure"
          elseif g:Fault == "invalid"
            return a:Deliver({"schema": "unsupported", "contexts": []})
          elseif g:Fault == "wrongtype"
            return a:Deliver(0)
          elseif g:Fault == "owner"
            return a:Deliver("OWNER_FAILED")
          endif
          let a:raw.working[0] = "changed argument"
          let a:raw.input.opaque[0][0] = "changed argument"
          call a:Deliver(g:View)
        endfunction
        " Explicit Ctrl-X Ctrl-U asks through the same path; delivery is deferred.
        function s:Ask()
          call assert_equal(-3, call(eval(&l:completefunc), [1, ""]))
          sleep 30m
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
            call s:Ask()
            call assert_equal(s:working, g:Inputs[-1].working)
            call assert_equal({"opaque": [s:working]}, g:Inputs[-1].input)
            call assert_equal(b:surface_current, g:Inputs[-1].current)
            call assert_equal(b:surface_context, g:Inputs[-1].context)
            call assert_equal(0, g:Inputs[-1].start)
            call assert_equal(s:original, g:View)
            call assert_equal(["", v:false], [b:surface_error, b:surface_busy], "delivered once")
          endfor
        endfor
        call add(s:phases, "two contexts/full Working")
        let s:owner = bufnr()
        let s:group = g:View.contexts[-1]
        let s:prior = {"handle": {"origin": "previous selection"}, "base": {"working": ["earlier"]}}
        let b:surface_selection = deepcopy(s:prior)
        for [g:Fault, s:code] in [["throw", "ACQUIRE"], ["invalid", "VIEW"], ["wrongtype", "VIEW"], ["owner", "OWNER_FAILED"], ["setting", "SETUP"], ["querythrow", "QUERY"], ["queryshape", "QUERY"], ["querytype", "QUERY"], ["querystart", "QUERY"], ["querybyte", "QUERY"], ["queryworking", "QUERY"], ["queryswap", "QUERY"]]
          execute "buffer " . s:owner
          let b:surface_source = {"binding": [1]}
          let b:surface_current = deepcopy(s:group.current)
          let b:surface_context = deepcopy(s:group.context)
          let b:surface_query = function("g:Query")
          let b:surface_acquire = g:Fault == "setting" ? 0 : function("g:Acquire")
          let b:surface_error = ""
          call deletebufline(bufnr(), 1, "$")
          call setline(1, "あ second Working")
          call cursor(1, 1)
          if g:Fault == "querybyte"
            call cursor(1, 4)
          endif
          let s:before = len(g:Inputs)
          call s:Ask()
          call assert_equal(s:before + (index(["throw", "invalid", "wrongtype", "owner"], g:Fault) >= 0), len(g:Inputs), g:Fault . " reached")
          call assert_equal([s:code, v:false], [b:surface_error, b:surface_busy], g:Fault . " observable")
          call assert_equal(s:prior, b:surface_selection, g:Fault . " origin")
          call assert_equal([g:Fault == "queryworking" ? "query changed Working" : "あ second Working"], getline(1, "$"), g:Fault . " Working")
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
        for s:event in ["CompleteDonePre", "CompleteDone", "TextChangedI", "TextChangedP", "InsertLeave", "BufLeave", "WinLeave"]
          call assert_equal(1, len(autocmd_get({"group": "edits_surface", "event": s:event, "pattern": "<buffer=" . bufnr() . ">"})), s:event)
        endfor
        call assert_equal(s:global, [&g:completeopt, &g:completefunc])
        call assert_equal(s:original, g:View)
        call add(s:phases, "attach named dirty/repeat")
        call assert_equal(["two contexts/full Working", "throw", "invalid", "wrongtype", "owner", "setting", "querythrow", "queryshape", "querytype", "querystart", "querybyte", "queryworking", "queryswap", "attach named dirty/repeat"], s:phases)
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
      semcmp-installed = pkgs.runCommand "edits-semcmp-package-connection" {
        nativeBuildInputs = [ edits vim ];
        EDITS_PROPOSALS = ./packages/vim/tests/proposals.json;
        JEV_API_KEY = "test-only-placeholder";
        JEV_API_URL = "https://invalid.test/never-contacted";
        SEMCMP_TEST_CASE = "ok";
        LANG = "C.UTF-8";
      } ''
        export SEMCMP_TEST_TRACE="$PWD/trace.json" EDITS_TEST_DIR="$PWD" EDITS_TEST_LOG="$PWD/requests.log"
        cat > preload.mjs <<'JS'
        import "${ops}/packages/semcmp/tests/cli.mjs";
        const original = process.stdout.write.bind(process.stdout);
        process.stdout.write = (chunk, ...args) => {
          const fault = process.env.EDITS_TEST_FAULT;
          if (!fault) return original(chunk, ...args);
          if (fault === "json") return original("{invalid", ...args);
          const result = JSON.parse(String(chunk));
          if (fault === "query") result.query.input = "unrelated";
          if (fault === "duplicate") result.proposals[1] = result.proposals[0];
          if (fault === "evidence") result.proposals[0].evidence.noul = 2;
          if (fault === "numericstring") result.query.state.current.opaque[0] = "1";
          return original(JSON.stringify(result), ...args);
        };
        JS
        # Test-owned controlled proposer: its reply depends only on the partial input.
        cat > proposer.mjs <<'JS'
        import fs from "node:fs";
        const all = JSON.parse(fs.readFileSync(process.env.EDITS_PROPOSALS, "utf8"));
        const byId = Object.fromEntries(all.map((p) => [p.id, p]));
        export async function propose({ input }) {
          fs.appendFileSync(process.env.EDITS_TEST_LOG, JSON.stringify(input) + "\n");
          if (input === "boom") throw new Error("test proposer failure");
          if (input.endsWith("s")) await new Promise((resolve) => setTimeout(resolve, 1500));
          if (!input.startsWith("ux")) return [];
          if (input.includes("は") || input.endsWith("s")) return [byId.p3];
          if (input.endsWith("m")) return [{ ...byId.p2, representation: byId.p2.representation + "\ndepends on" }];
          if (input.endsWith("q")) return [byId.p1, byId.p3].map((p) => ({ ...p, representation: "same inserted text" }));
          if (input.endsWith("l")) return [byId.p1, byId.p3].map((p, i) => ({ ...p, representation: "same first line\n" + ["first", "second"][i] + " body" }));
          return [byId.p1, byId.p2];
        }
        JS
        export NODE_OPTIONS="--import=$PWD/preload.mjs" EDITS_SEMCMP_PROPOSER="$PWD/proposer.mjs"
        cat > check-adapter.vim <<'VIM'
        set nomore hidden
        call setline(1, ["existing dirty", "other row"])
        file owned-installed-buffer
        let s:body = getline(1, "$")
        let s:undo = undotree()
        let s:global = [&g:completeopt, &g:completefunc]
        import "${edits}/share/edits/vim/semcmp.vim" as semcmp
        call assert_equal(s:body, getline(1, "$"))
        call assert_equal(s:undo, undotree())
        let b:surface_current = {"opaque": [1.0, {"n": 2.0, "s": "1"}]}
        let b:surface_context = ["caller context"]
        call s:semcmp.Attach($EDITS_SEMCMP_BIN, $EDITS_SEMCMP_PROPOSER)
        let s:Query = b:surface_query
        call s:semcmp.Attach($EDITS_SEMCMP_BIN, $EDITS_SEMCMP_PROPOSER)
        call assert_equal(s:body, getline(1, "$"))
        call assert_equal(s:undo, undotree())
        call assert_equal(s:Query, b:surface_query)
        call assert_equal({"opaque": [1.0, {"n": 2.0, "s": "1"}]}, b:surface_current)
        call assert_equal(["caller context"], b:surface_context)
        call assert_equal(s:global, [&g:completeopt, &g:completefunc])
        call assert_equal(1, len(autocmd_get({"group": "edits_surface", "event": "TextChangedI", "pattern": "<buffer=" . bufnr() . ">"})))
        call assert_true(has("job"), "installed Vim has jobs")
        let s:prior = {"handle": {"previous": "origin"}, "base": {"working": ["earlier"]}}
        let b:surface_selection = deepcopy(s:prior)
        function g:Got(result)
          let g:Result = a:result
        endfunction
        " The configured acquisition: one semcmp process, then exactly one delivery.
        function s:Acquire(input)
          let l:raw = {"source": b:surface_source, "buffer": bufnr(), "tick": 1,
                \ "working": [a:input . " right suffix", "other row"], "current": b:surface_current,
                \ "context": b:surface_context, "cursor": {"line": 1, "column": strlen(a:input) + 1},
                \ "start": 0, "input": a:input}
          unlet! g:Result
          call delete($SEMCMP_TEST_TRACE)
          call call(b:surface_acquire, [l:raw, function("g:Got")])
          for l:i in range(500)
            if exists("g:Result")
              return g:Result
            endif
            sleep 20m
          endfor
          return "TIMEOUT"
        endfunction
        let s:phases = ["attach"]
        call assert_equal([], s:Acquire("u").contexts[0].items, "none")
        call assert_false(filereadable($SEMCMP_TEST_TRACE), "none makes no evaluator call")
        call add(s:phases, "u")
        let s:catalog = json_decode(join(readfile($EDITS_PROPOSALS), "\n"))
        for [s:input, s:ids] in [["ux", ["p2", "p1"]], ["uxは", ["p3"]]]
          let s:items = s:Acquire(s:input).contexts[0].items
          call assert_equal(s:ids, map(copy(s:items), "v:val.handle.id"), s:input)
          for s:item in s:items
            let s:original = filter(deepcopy(s:catalog), "v:val.id == s:item.handle.id")[0]
            call assert_equal([s:original.meaning, s:original.representation], [s:item.handle.meaning, s:item.handle.representation])
            call assert_equal(split(s:original.representation, "\n", 1), s:item.text)
            call assert_equal("intent-fit", s:item.handle.evidence.theme)
            call assert_equal("representation:\n" . s:original.representation . "\n\nmeaning: " . json_encode(s:item.handle.meaning) . "\nevidence: " . json_encode(s:item.handle.evidence), s:item.info)
          endfor
          let s:q = json_decode(join(readfile($SEMCMP_TEST_TRACE), "\n")).payload.state.query
          call assert_equal(s:input, s:q.input)
          call assert_equal([s:input . " right suffix", "other row"], s:q.state.working)
          call assert_equal([1, "1"], [s:q.state.current.opaque[0], s:q.state.current.opaque[1].s])
          call assert_equal(["caller context"], s:q.state.context)
          call assert_equal({"line": 1, "column": strlen(s:input) + 1, "start": 0}, s:q.focus)
          call add(s:phases, s:input)
        endfor
        " Equal text or an equal first line still keeps distinct meanings and full text readable.
        let s:items = s:Acquire("uxq").contexts[0].items
        call assert_equal([["p1", "p3"], ["same inserted text"], ["same inserted text"]], [map(copy(s:items), "v:val.handle.id"), s:items[0].text, s:items[1].text])
        call assert_notequal(s:items[0].info, s:items[1].info, "different meanings visible")
        let s:items = s:Acquire("uxl").contexts[0].items
        call assert_equal(["same first line", "same first line"], map(copy(s:items), "v:val.label"))
        call assert_equal([["same first line", "first body"], ["same first line", "second body"]], map(copy(s:items), "v:val.text"))
        call assert_notequal(s:items[0].info, s:items[1].info, "different full text visible")
        call add(s:phases, "equal text/first line")
        let s:faults = [["nokey", "ux", "JEV_API_KEY_REQUIRED"], ["http", "ux", "JEV_FAILED"], ["json", "ux", "RESULT"], ["query", "ux", "RESULT"], ["duplicate", "ux", "RESULT"], ["evidence", "ux", "RESULT"], ["numericstring", "ux", "RESULT"], ["proposer", "boom", "PROPOSE_FAILED"]]
        for [s:fault, s:input, s:code] in s:faults
          let $JEV_API_KEY = s:fault == "nokey" ? "" : "test-only-placeholder"
          let $SEMCMP_TEST_CASE = s:fault == "http" ? "http" : "ok"
          let $EDITS_TEST_FAULT = index(["nokey", "http", "proposer"], s:fault) < 0 ? s:fault : ""
          call assert_equal(s:code, s:Acquire(s:input), s:fault)
          call add(s:phases, s:fault)
        endfor
        let $JEV_API_KEY = "test-only-placeholder"
        let $SEMCMP_TEST_CASE = "ok"
        let $EDITS_TEST_FAULT = ""
        for [s:proposer, s:code] in [["/absent/proposer.mjs", "INVALID_PROPOSER"], ["proposer.mjs", "INVALID_ARGUMENTS"], ["", "NOT_CONFIGURED"]]
          call s:semcmp.Attach($EDITS_SEMCMP_BIN, s:proposer)
          call assert_equal(s:code, s:Acquire("ux"), s:code)
          call add(s:phases, s:code)
        endfor
        call assert_equal(s:prior, b:surface_selection, "acquisition never selects")
        call assert_equal(s:body, getline(1, "$"), "acquisition never edits")
        call assert_equal(["attach", "u", "ux", "uxは", "equal text/first line"] + map(copy(s:faults), "v:val[0]") + ["INVALID_PROPOSER", "INVALID_ARGUMENTS", "NOT_CONFIGURED"], s:phases)
        call assert_equal("", v:errmsg)
        if !empty(v:errors)
          call writefile(v:errors, "/dev/stderr")
          cquit 1
        endif
        call writefile(["edits semcmp installed"], $out)
        qa!
        VIM
        edits -Nu NONE -i NONE -n -es -S check-adapter.vim
        test "$(cat "$out")" = "edits semcmp installed"

        # Real typing needs a terminal: Vim's own pty drives the installed edits.
        cat > helper.vim <<'VIM'
        vim9script
        g:Outside = false
        def Outside()
          if g:Outside
            g:Outside = false
            setline(line("$"), "outside edit")
          endif
        enddef
        def g:ChangeCurrent()
          b:surface_current = "changed during flight"
        enddef
        autocmd CompleteDonePre <buffer> Outside()
        inoremap <buffer> <F9> <Cmd>call g:ChangeCurrent()<CR>
        def g:Dump(name: string)
          writefile([json_encode({lines: getline(1, "$"), mode: mode(), selection: b:surface_selection,
            error: b:surface_error, job: has("job"), reread: execute("SurfaceSelection"),
            messages: execute("messages")})], $EDITS_TEST_DIR .. "/" .. name .. ".json")
        enddef
        VIM
        cat > native.vim <<'VIM'
        vim9script
        const dir = $EDITS_TEST_DIR
        const log = $EDITS_TEST_LOG
        var buf = term_start(["edits", "-Nu", "NONE", "-i", "NONE", "-n", "-S", dir .. "/helper.vim", dir .. "/notes.txt"], {term_rows: 12, term_cols: 70})
        def Screen(): list<string>
          return range(1, 12)->mapnew((_, row) => term_getline(buf, row))
        enddef
        def Shows(text: string): bool
          return stridx(join(Screen(), "\n"), text) >= 0
        enddef
        def Menu(): bool
          return Shows("intent-fit")
        enddef
        def Line(text: string): bool
          return stridx(Screen()[0], text) == 0
        enddef
        def Requests(): list<string>
          return filereadable(log) ? readfile(log) : []
        enddef
        def Until(Ready: func(): bool, what: string)
          for _ in range(150)
            if Ready()
              return
            endif
            term_wait(buf, 100)
          endfor
          assert_report("timed out: " .. what .. " " .. string(Screen()))
        enddef
        def Keys(keys: string, settle = 600)
          term_sendkeys(buf, keys)
          term_wait(buf, settle)
        enddef
        def Dump(name: string): dict<any>
          const path = dir .. "/" .. name .. ".json"
          Keys(":call g:Dump('" .. name .. "')\r", 300)
          Until(() => filereadable(path), name)
          return filereadable(path) ? json_decode(join(readfile(path), "\n"))
            : {lines: [], mode: "", selection: {}, error: "", job: 0, reread: "", messages: ""}
        enddef
        def Picked(dump: dict<any>): list<string>
          return [get(get(dump.selection, "handle", {}), "id", ""), get(get(dump.selection, "base", {}), "input", "")]
        enddef
        term_wait(buf, 1000)

        # First partial character is eligible; none is quiet and typing goes on.
        Keys("iu")
        Until(() => Requests() == ['"u"'], "first character request")
        term_wait(buf, 800)
        assert_false(Menu(), "none is quiet")
        assert_true(Line("u right suffix"), "typing continues")
        # More input changes the candidate set.
        Keys("x")
        Until(Menu, "ux proposals")
        assert_true(Shows("API → DB") && Shows("DB → API"), "ux set")
        # Native preview and return to it are not Human queries.
        Keys("\<C-N>", 800)
        assert_true(Line("DB → API right suffix"), "preview")
        Keys("\<C-P>", 800)
        assert_true(Line("ux right suffix"), "back at original")
        assert_equal(['"u"', '"ux"'], Requests(), "preview asks nothing")
        # Japanese input replaces the stale menu with the latest set.
        Keys("は")
        Until(() => Shows("APIとDB"), "Japanese partial input")
        assert_false(Shows("DB → API"), "old menu closed")
        assert_equal('"uxは"', Requests()[-1])
        # Cancel of the own menu stays cancelled until Human input or explicit request.
        Keys("\<C-E>", 1500)
        assert_false(Menu(), "cancel is not revived")
        assert_true(Line("uxは right suffix"), "cancel keeps typing")
        assert_equal(3, len(Requests()))
        Keys("\<C-X>\<C-U>")
        Until(Menu, "explicit request")
        assert_equal(4, len(Requests()))
        Keys("\<C-E>")
        # Exact multiline + suffix selection, one Working update, reread origin.
        Keys("\<BS>")
        Until(() => Shows("DB → API"), "ux after backspace")
        Keys("m")
        Until(() => Menu() && !Shows("API → DB "), "multiline proposal")
        var asked = len(Requests())
        Keys("\<C-N>\<C-Y>", 1500)
        assert_false(Menu(), "selection is not followed by a revived menu")
        assert_equal(asked, len(Requests()), "selection asks nothing")
        Keys("\<Esc>", 1100)
        var d = Dump("select")
        assert_equal(["DB → API", "depends on right suffix", "other row"], d.lines)
        assert_equal(["p2", "uxm"], Picked(d))
        assert_equal(["n", 1], [d.mode, d.job])
        assert_true(stridx(d.reread, "選択時・未採用") >= 0 && stridx(d.reread, "representation:\nDB → API\ndepends on") >= 0, "reread")
        Keys("u")
        assert_equal([" right suffix", "other row"], Dump("undo").lines, "one Undo step")
        # Accept by typing is a native selection too.
        Keys("iux")
        Until(Menu, "implicit")
        Keys("\<C-N>z", 1000)
        Keys("\<Esc>", 1100)
        d = Dump("implicit")
        assert_equal(["DB → APIz right suffix", "p2"], [d.lines[0], Picked(d)[0]])
        Keys("u")
        # An older inflight result is refused; the latest query is asked next.
        Keys("iuxs", 300)
        Keys("!", 200)
        Until(() => Shows("API → DB"), "latest after stale")
        assert_false(Shows("APIとDB"), "stale result refused")
        assert_equal(['"uxs"', '"uxs!"'], Requests()[-2 :])
        Keys("\<C-E>\<Esc>", 1100)
        Keys("u")
        # Leaving Insert or changing current state invalidates the pending result.
        Keys("iuxs", 300)
        Keys("\<Esc>", 2500)
        assert_false(Menu(), "no menu after leaving Insert")
        d = Dump("leave")
        assert_equal(["uxs right suffix", "n"], [d.lines[0], d.mode])
        Keys("u")
        Keys("iuxs", 300)
        Keys("\<F9>", 2500)
        assert_false(Menu(), "no menu after current changed")
        Keys("\<Esc>", 1100)
        Keys("u")
        # Foreign native completion is never recorded or applied.
        Keys("2GA ot", 1500)
        Keys("\<C-N>\<C-N>", 800)
        Keys("\<C-Y>\<Esc>", 1100)
        d = Dump("foreign")
        assert_equal(["other row other", "p2"], [d.lines[1], Picked(d)[0]])
        Keys("u")
        # Changed outside lines refuse only the own insertion.
        Keys(":let g:Outside = v:true\r", 300)
        Keys("gg0iux")
        Until(Menu, "outside")
        Keys("\<C-N>\<C-Y>", 1200)
        Keys("\<Esc>", 1100)
        d = Dump("outside")
        assert_equal([["ux right suffix", "outside edit"], "p2"], [d.lines, Picked(d)[0]])
        Keys("u")
        assert_equal([" right suffix", "other row"], Dump("outside-undo").lines)
        # Failure is distinct from none, recorded once, and editing continues.
        Keys("Goboom")
        Until(() => Requests()[-1] == '"boom"', "failing request")
        term_wait(buf, 1500)
        Keys("\<Esc>", 1100)
        d = Dump("failure")
        assert_equal(["boom", "PROPOSE_FAILED", 1], [d.lines[-1], d.error, count(d.messages, "PROPOSE_FAILED")])
        Keys("a!", 1500)
        Keys("\<Esc>", 1100)
        d = Dump("recovered")
        assert_equal(["boom!", ""], [d.lines[-1], d.error])
        Keys(":qa!\r", 500)
        writefile(v:errors, dir .. "/native-errors")
        if !empty(v:errors)
          cquit 1
        endif
        writefile(["native incremental loop"], dir .. "/native-report")
        qa!
        VIM
        printf '%s\n' ' right suffix' 'other row' > notes.txt
        : > "$EDITS_TEST_LOG"
        TERM=xterm vim -Nu NONE -i NONE -n --not-a-term -S native.vim </dev/null >/dev/null 2>&1 \
          || { cat native-errors >&2 || true; exit 1; }
        test "$(cat native-report)" = "native incremental loop"
      '';
      };
    };
}
