package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"hq/internal/pty"
	"hq/internal/rsc"
)

type completionResponse struct {
	Context     rsc.CursorContext `json:"context"`
	Suggestions []rsc.Suggestion  `json:"suggestions"`
}

func cmdRSCModel(args []string) error {
	fs := flag.NewFlagSet("rsc-model", flag.ContinueOnError)
	worldPath := fs.String("world", "examples/tree_world.jsonl", "append-only tree world jsonl")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	world, err := rsc.LoadWorld(*worldPath)
	if err != nil {
		return err
	}
	return writeJSON(*out, world)
}

func cmdRSCComplete(args []string) error {
	fs := flag.NewFlagSet("rsc-complete", flag.ContinueOnError)
	worldPath := fs.String("world", "examples/tree_world.jsonl", "append-only tree world jsonl")
	buffer := fs.String("buffer", "", "current one-line JSON buffer")
	cursorArg := fs.String("cursor", "end", "cursor byte/rune position or end")
	version := fs.Int("version", 1, "buffer version")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	world, err := rsc.LoadWorld(*worldPath)
	if err != nil {
		return err
	}
	cursor := len([]rune(*buffer))
	if *cursorArg != "end" {
		if _, err := fmt.Sscanf(*cursorArg, "%d", &cursor); err != nil {
			return fmt.Errorf("bad --cursor: %s", *cursorArg)
		}
	}
	ctx := rsc.BuildContext(world, *buffer, cursor, *version)
	res := completionResponse{Context: ctx, Suggestions: rsc.Suggest(world, ctx)}
	return writeJSON(*out, res)
}

func cmdRSCIntake(args []string) error {
	fs := flag.NewFlagSet("rsc-intake", flag.ContinueOnError)
	worldPath := fs.String("world", "examples/tree_world.jsonl", "append-only tree world jsonl")
	input := fs.String("input", "", "loose string or JSON object input from Vim")
	version := fs.Int("version", 1, "buffer version")
	strict := fs.Bool("strict", false, "return non-zero when strict validation has errors")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	world, err := rsc.LoadWorld(*worldPath)
	if err != nil {
		return err
	}
	res := rsc.Intake(world, *input, *version)
	if *strict {
		res.Validation = rsc.ValidateDraft(world, res.Draft, "strict")
	}
	if err := writeJSON(*out, res); err != nil {
		return err
	}
	if *strict && rsc.HasBlockingValidation(res.Validation) {
		return fmt.Errorf("strict draft validation failed")
	}
	return nil
}

func cmdRSCAccept(args []string) error {
	fs := flag.NewFlagSet("rsc-accept", flag.ContinueOnError)
	suggestionPath := fs.String("suggestion", "", "suggestion json path, completion response json, or '-' for stdin")
	index := fs.Int("index", 0, "suggestion index when --suggestion is a completion response")
	queuePath := fs.String("queue", "cache/instruction.jsonl", "instruction jsonl queue path")
	out := fs.String("out", "", "optional instruction output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *suggestionPath == "" {
		return fmt.Errorf("--suggestion required")
	}
	var data []byte
	var err error
	if *suggestionPath == "-" {
		data, err = io.ReadAll(os.Stdin)
	} else {
		data, err = os.ReadFile(*suggestionPath)
	}
	if err != nil {
		return err
	}
	var sug rsc.Suggestion
	if err := json.Unmarshal(data, &sug); err != nil || sug.ID == "" {
		var resp completionResponse
		if err2 := json.Unmarshal(data, &resp); err2 != nil {
			return fmt.Errorf("not a suggestion or completion response: %v / %v", err, err2)
		}
		if *index < 0 || *index >= len(resp.Suggestions) {
			return fmt.Errorf("suggestion index %d out of range", *index)
		}
		sug = resp.Suggestions[*index]
	}
	ins, err := rsc.Accept(rsc.Acceptance{Suggestion: sug, SuggestionID: sug.ID, SuggestionHash: sug.Hash, BufferVersion: sug.BufferVersion})
	if err != nil {
		return err
	}
	if err := rsc.AppendInstruction(*queuePath, ins); err != nil {
		return err
	}
	return writeJSON(*out, ins)
}

func cmdPTYVimRSCProof(args []string) error {
	fs := flag.NewFlagSet("pty-vim-rsc-proof", flag.ContinueOnError)
	worldPath := fs.String("world", "examples/tree_world.jsonl", "append-only tree world jsonl")
	chars := fs.String("chars", "{\"kind\":\"project\",\"tasks\":[", "characters to feed to Vim one by one")
	out := fs.String("out", "cache/pty-vim-proof.json", "proof summary json")
	tracePath := fs.String("trace", "cache/pty-vim-slot-autocmp.jsonl", "slot completion trace jsonl")
	if err := fs.Parse(args); err != nil {
		return err
	}
	hqBin, err := os.Executable()
	if err != nil {
		return err
	}
	vim, err := lookupVim()
	if err != nil {
		return err
	}
	world, err := rsc.LoadWorld(*worldPath)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(*tracePath), 0o755); err != nil {
		return err
	}
	_ = os.Remove(*tracePath)

	script, err := writeProofVimscript(hqBin, *worldPath, *tracePath)
	if err != nil {
		return err
	}
	defer os.Remove(script)
	bufFile := filepath.Join(os.TempDir(), fmt.Sprintf("hq-rsc-%d.jsonl", time.Now().UnixNano()))
	if err := os.WriteFile(bufFile, []byte(""), 0o644); err != nil {
		return err
	}
	defer os.Remove(bufFile)

	argv := []string{vim, "-Nu", "NONE", "-n", "-i", "NONE", "-S", script, bufFile}
	sess, err := pty.Start(argv, []string{"TERM=xterm-256color"})
	if err != nil {
		return err
	}
	defer sess.Close()
	pid := sess.PID()
	cmdline := procCmdline(pid)
	readerDone := make(chan struct{})
	var captured bytes.Buffer
	go func() { _, _ = io.Copy(&captured, sess.Master); close(readerDone) }()
	// Wait for Vim to enter insert mode, then send every byte through the PTY master.
	time.Sleep(500 * time.Millisecond)
	line := ""
	version := 0
	for _, r := range *chars {
		if _, err := sess.Master.Write([]byte(string(r))); err != nil {
			return err
		}
		line += string(r)
		version++
		ctx := rsc.BuildContext(world, line, len([]rune(line)), version)
		suggestions := rsc.Suggest(world, ctx)
		labels := make([]string, 0, len(suggestions))
		for _, item := range suggestions {
			labels = append(labels, item.Label)
		}
		_ = appendTraceRow(*tracePath, map[string]any{"kind": "master.slot.autocomplete", "line": line, "cursor": len([]rune(line)), "slot_kind": ctx.Slot.Kind, "slot_path": ctx.Slot.Path, "suggestion_count": len(suggestions), "labels": labels})
		time.Sleep(25 * time.Millisecond)
	}
	time.Sleep(250 * time.Millisecond)
	// Leave insert mode and save+quit without shell mediation.
	_, _ = sess.Master.Write([]byte("\x1b:wq!\r"))
	_ = sess.Wait()
	select {
	case <-readerDone:
	case <-time.After(500 * time.Millisecond):
	}

	traceRows, err := readJSONL(*tracePath)
	if err != nil {
		return err
	}
	finalOK := false
	var final map[string]any
	if len(traceRows) > 0 {
		final = traceRows[len(traceRows)-1]
	}
	for _, row := range traceRows {
		if row["slot_kind"] == "array.item" && containsStringSlice(row["labels"], "task:t1") && containsStringSlice(row["labels"], "task:t2") && containsStringSlice(row["labels"], "task:t3") {
			finalOK = true
			final = row
		}
	}
	if *out != "" {
		_ = os.WriteFile(*out+".screen", captured.Bytes(), 0o644)
	}
	savedBuffer, _ := os.ReadFile(bufFile)
	vimBufferOK := strings.TrimRight(string(savedBuffer), "\n") == *chars
	result := map[string]any{
		"kind":                  "proof.pty-vim-rsc",
		"direct_vim_no_shell":   strings.Contains(cmdline, "vim") && !strings.Contains(cmdline, "sh\x00"),
		"argv":                  argv,
		"proc_cmdline":          cmdline,
		"pid":                   pid,
		"typed_chars":           *chars,
		"vim_buffer_saved":      vimBufferOK,
		"vim_buffer":            strings.TrimRight(string(savedBuffer), "\n"),
		"trace":                 *tracePath,
		"trace_rows":            len(traceRows),
		"slot_autocomplete_ok":  finalOK,
		"final_slot_sample":     final,
		"captured_screen_bytes": captured.Len(),
	}
	if !finalOK || !vimBufferOK {
		_ = writeJSON(*out, result)
		return fmt.Errorf("slot autocomplete proof failed; result=%v", result)
	}
	return writeJSON(*out, result)
}

func lookupVim() (string, error) {
	for _, cand := range []string{"vim", "nvim"} {
		if path, err := execLookPath(cand); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("vim/nvim not found")
}

func execLookPath(name string) (string, error) {
	paths := strings.Split(os.Getenv("PATH"), string(os.PathListSeparator))
	for _, p := range paths {
		full := filepath.Join(p, name)
		if st, err := os.Stat(full); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			return full, nil
		}
	}
	return "", os.ErrNotExist
}

func writeProofVimscript(hqBin, worldPath, tracePath string) (string, error) {
	path := filepath.Join(os.TempDir(), fmt.Sprintf("hq-rsc-proof-%d.vim", time.Now().UnixNano()))
	body := fmt.Sprintf(`
set nocompatible
set noswapfile
set shortmess+=I
set noerrorbells visualbell t_vb=
let g:hq_bin = %s
let g:hq_world = %s
let g:hq_trace = %s
call writefile([json_encode({'kind':'vim.start','line':getline(1),'cursor':col('.') - 1})], g:hq_trace, 'a')
startinsert
`, vimString(hqBin), vimString(worldPath), vimString(tracePath))
	return path, os.WriteFile(path, []byte(body), 0o644)
}

func appendTraceRow(path string, row map[string]any) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := json.Marshal(row)
	if err != nil {
		return err
	}
	_, err = f.Write(append(b, '\n'))
	return err
}

func vimString(s string) string { b, _ := json.Marshal(s); return string(b) }

func procCmdline(pid int) string {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	if err != nil {
		return ""
	}
	return string(b)
}

func containsStringSlice(v any, want string) bool {
	switch vv := v.(type) {
	case []any:
		for _, x := range vv {
			if fmt.Sprint(x) == want {
				return true
			}
		}
	case []string:
		for _, x := range vv {
			if x == want {
				return true
			}
		}
	}
	return false
}

func cmdPTYVimRSCVisualProof(args []string) error {
	fs := flag.NewFlagSet("pty-vim-rsc-visual-proof", flag.ContinueOnError)
	worldPath := fs.String("world", "examples/tree_world.jsonl", "append-only tree world jsonl")
	chars := fs.String("chars", "{\"kind\":\"project\",\"tasks\":[", "characters to feed to Vim one by one")
	out := fs.String("out", "cache/vim-visual-projection.json", "visual proof summary json")
	tracePath := fs.String("trace", "cache/vim-visual-projection.trace.jsonl", "Vim popup projection trace jsonl")
	screenTextPath := fs.String("screen-text", "cache/vim-visual-projection.screen.txt", "Vim screenstring grid captured after popup projection")
	rawPath := fs.String("raw", "cache/vim-visual-projection.pty.raw", "raw PTY transcript bytes")
	if err := fs.Parse(args); err != nil {
		return err
	}
	vim, err := lookupVim()
	if err != nil {
		return err
	}
	world, err := rsc.LoadWorld(*worldPath)
	if err != nil {
		return err
	}
	for _, path := range []string{*out, *tracePath, *screenTextPath, *rawPath} {
		if path == "" {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return err
		}
		_ = os.Remove(path)
	}
	projectionByLine := buildProjectionMap(world, *chars)
	script, err := writeLiveVisualProjectionVimscript(projectionByLine, *tracePath, *screenTextPath)
	if err != nil {
		return err
	}
	defer os.Remove(script)
	bufFile := filepath.Join(os.TempDir(), fmt.Sprintf("hq-rsc-visual-%d.jsonl", time.Now().UnixNano()))
	if err := os.WriteFile(bufFile, []byte(""), 0o644); err != nil {
		return err
	}
	defer os.Remove(bufFile)

	argv := []string{vim, "-Nu", "NONE", "-n", "-i", "NONE", "-S", script, bufFile}
	sess, err := pty.Start(argv, []string{"TERM=xterm-256color", "COLUMNS=104", "LINES=30"})
	if err != nil {
		return err
	}
	defer sess.Close()
	pid := sess.PID()
	cmdline := procCmdline(pid)
	readerDone := make(chan struct{})
	var captured bytes.Buffer
	go func() { _, _ = io.Copy(&captured, sess.Master); close(readerDone) }()

	// PTY master sends characters. Vim is the direct child line editor; no shell wrapper is used.
	time.Sleep(650 * time.Millisecond)
	line := ""
	version := 0
	for _, r := range *chars {
		if _, err := sess.Master.Write([]byte(string(r))); err != nil {
			return err
		}
		line += string(r)
		version++
		ctx := rsc.BuildContext(world, line, len([]rune(line)), version)
		suggestions := rsc.Suggest(world, ctx)
		labels := make([]string, 0, len(suggestions))
		for _, item := range suggestions {
			labels = append(labels, item.Label)
		}
		_ = appendTraceRow(*tracePath, map[string]any{"kind": "master.typed", "line": line, "cursor": len([]rune(line)), "slot_kind": ctx.Slot.Kind, "slot_path": ctx.Slot.Path, "labels": labels})
		time.Sleep(80 * time.Millisecond)
	}
	// Wait for Vim TextChangedI projection adapter to draw popup and write screenstring capture.
	time.Sleep(1100 * time.Millisecond)
	_, _ = sess.Master.Write([]byte("\x1b:q!\r"))
	_ = sess.Wait()
	select {
	case <-readerDone:
	case <-time.After(500 * time.Millisecond):
	}
	_ = os.WriteFile(*rawPath, captured.Bytes(), 0o644)

	traceRows, err := readJSONL(*tracePath)
	if err != nil {
		return err
	}
	finalPopupOK := false
	var finalPopup map[string]any
	for _, row := range traceRows {
		if row["kind"] == "vim.popup.rendered" && containsStringSlice(row["labels"], "task:t1") && containsStringSlice(row["labels"], "task:t2") && containsStringSlice(row["labels"], "task:t3") {
			finalPopupOK = true
			finalPopup = row
		}
	}
	screenBytes, _ := os.ReadFile(*screenTextPath)
	screen := string(screenBytes)
	screenHasProjection := strings.Contains(screen, "HQ SLOT PROJECTION") && strings.Contains(screen, "task:t1") && strings.Contains(screen, "task:t2") && strings.Contains(screen, "task:t3")
	directNoShell := strings.Contains(cmdline, "vim") && !strings.Contains(cmdline, "sh\x00")
	result := map[string]any{
		"kind":                  "proof.pty-vim-rsc-visual-projection",
		"direct_vim_no_shell":   directNoShell,
		"argv":                  argv,
		"proc_cmdline":          cmdline,
		"pid":                   pid,
		"typed_chars":           *chars,
		"trace":                 *tracePath,
		"screen_text":           *screenTextPath,
		"raw_pty_transcript":    *rawPath,
		"trace_rows":            len(traceRows),
		"vim_popup_trace_ok":    finalPopupOK,
		"screen_contains_popup": screenHasProjection,
		"visual_projection_ok":  directNoShell && finalPopupOK && screenHasProjection,
		"projection_source":     "pty-master-core-map",
		"vim_query_shell":       false,
		"final_popup_sample":    finalPopup,
		"captured_screen_bytes": captured.Len(),
	}
	if err := writeJSON(*out, result); err != nil {
		return err
	}
	if !directNoShell || !finalPopupOK || !screenHasProjection {
		return fmt.Errorf("visual projection proof failed; result=%v", result)
	}
	return nil
}

func buildProjectionMap(world rsc.World, chars string) map[string]any {
	projection := map[string]any{}
	line := ""
	version := 0
	for _, r := range chars {
		line += string(r)
		version++
		intake := rsc.Intake(world, line, version)
		ctx := intake.Context
		suggestions := intake.Suggestions
		labels := make([]string, 0, len(suggestions))
		rows := []string{"HQ SLOT PROJECTION", "slot: " + ctx.Slot.Kind + " path: " + strings.Join(ctx.Slot.Path, ".")}
		if intake.Surface == "loose-string" {
			rows = append(rows, "draft: "+intake.Draft.Kind+" op: "+intake.Draft.Operation)
			if len(intake.Draft.Missing) > 0 {
				rows = append(rows, "missing: "+strings.Join(intake.Draft.Missing, ","))
			}
		}
		for _, item := range suggestions {
			labels = append(labels, item.Label)
			detail := item.Detail
			if detail == "" {
				detail = item.Meaning
			}
			rows = append(rows, fmt.Sprintf("> %-8s %s", item.Label, detail))
		}
		if len(suggestions) == 0 {
			rows = append(rows, "(no suggestions)")
		}
		projection[line] = map[string]any{"slot_kind": ctx.Slot.Kind, "slot_path": ctx.Slot.Path, "labels": labels, "rows": rows, "surface": intake.Surface, "draft": intake.Draft}
	}
	return projection
}

func writeLiveVisualProjectionVimscript(projectionByLine map[string]any, tracePath, screenTextPath string) (string, error) {
	path := filepath.Join(os.TempDir(), fmt.Sprintf("hq-rsc-live-visual-%d.vim", time.Now().UnixNano()))
	projectionJSON, _ := json.Marshal(projectionByLine)
	body := fmt.Sprintf(`
set nocompatible
set noswapfile
set shortmess+=I
set noerrorbells visualbell t_vb=
set noruler noshowcmd noshowmode laststatus=0 signcolumn=no
set cmdheight=1
set columns=104 lines=30
syntax off
let g:hq_trace = %s
let g:hq_screen_text = %s
let g:hq_projection_by_line = json_decode(%s)
let g:hq_popup = -1
function! s:HqCaptureScreen() abort
  let l:rows=[]
  for l:r in range(1, &lines)
    let l:row=''
    for l:c in range(1, &columns)
      let l:ch = screenstring(l:r,l:c)
      if l:ch ==# ''
        let l:ch = ' '
      endif
      let l:row .= l:ch
    endfor
    call add(l:rows, l:row)
  endfor
  call writefile(l:rows, g:hq_screen_text)
endfunction
function! s:HqRenderProjection() abort
  let l:line = getline('.')
  if !has_key(g:hq_projection_by_line, l:line)
    return
  endif
  let l:item = g:hq_projection_by_line[l:line]
  let l:labels = get(l:item, 'labels', [])
  let l:rows = get(l:item, 'rows', ['HQ SLOT PROJECTION', '(no suggestions)'])
  if g:hq_popup != -1
    silent! call popup_close(g:hq_popup)
  endif
  let g:hq_popup = popup_create(l:rows, {'line': 4, 'col': 6, 'zindex': 300, 'padding': [0,1,0,1], 'border': [], 'highlight': 'Pmenu'})
  redraw!
  sleep 70m
  call <SID>HqCaptureScreen()
  call writefile([json_encode({'kind':'vim.popup.rendered','line':l:line,'slot_kind':get(l:item, 'slot_kind', ''),'slot_path':get(l:item, 'slot_path', []),'labels':l:labels,'popup_id':g:hq_popup,'screen_text':g:hq_screen_text})], g:hq_trace, 'a')
endfunction
augroup HqRSCVisualProjection
  autocmd!
  autocmd TextChangedI * call <SID>HqRenderProjection()
augroup END
call writefile([json_encode({'kind':'vim.visual.start','line':getline(1),'cursor':col('.') - 1})], g:hq_trace, 'a')
startinsert
`, vimString(tracePath), vimString(screenTextPath), vimString(string(projectionJSON)))
	return path, os.WriteFile(path, []byte(body), 0o644)
}
