package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"hq/internal/pty"
	"hq/internal/rsc"
)

func main() {
	var worldPath string
	var chars string
	var vimPath string
	var out string
	var tracePath string
	var screenTextPath string
	var rawPath string
	flag.StringVar(&worldPath, "world", "examples/tree_world.jsonl", "append-only tree world jsonl")
	flag.StringVar(&chars, "chars", "{\"kind\":\"project\",\"tasks\":[", "characters to feed to Vim")
	flag.StringVar(&vimPath, "vim", "", "path to vim executable")
	flag.StringVar(&out, "out", "cache/windows-conpty-vim-visual.json", "proof summary json")
	flag.StringVar(&tracePath, "trace", "cache/windows-conpty-vim-visual.trace.jsonl", "trace jsonl")
	flag.StringVar(&screenTextPath, "screen-text", "cache/windows-conpty-vim-visual.screen.txt", "captured screen text")
	flag.StringVar(&rawPath, "raw", "cache/windows-conpty-vim-visual.pty.raw", "raw pty/conpty transcript")
	flag.Parse()
	if err := run(worldPath, chars, vimPath, out, tracePath, screenTextPath, rawPath); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	fmt.Println("CONPTY_VIM_VISUAL_PROOF_OK")
}

func run(worldPath, chars, vimPath, out, tracePath, screenTextPath, rawPath string) error {
	if vimPath == "" {
		p, err := lookupVim()
		if err != nil {
			return err
		}
		vimPath = p
	}
	world, err := rsc.LoadWorld(worldPath)
	if err != nil {
		return err
	}
	for _, p := range []string{out, tracePath, screenTextPath, rawPath} {
		if p == "" {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return err
		}
		_ = os.Remove(p)
	}
	projection := buildProjectionMap(world, chars)
	script, err := writeVimscript(projection, tracePath, screenTextPath)
	if err != nil {
		return err
	}
	defer os.Remove(script)
	bufFile := filepath.Join(os.TempDir(), fmt.Sprintf("hq-conpty-visual-%d.jsonl", time.Now().UnixNano()))
	if err := os.WriteFile(bufFile, []byte(""), 0o644); err != nil {
		return err
	}
	defer os.Remove(bufFile)

	argv := []string{vimPath, "-v", "-T", "xterm", "-Nu", "NONE", "-n", "-i", "NONE", "-S", toVimPath(script), toVimPath(bufFile)}
	sess, err := pty.Start(argv, []string{"TERM=xterm-256color", "COLUMNS=104", "LINES=30"})
	if err != nil {
		return err
	}
	defer sess.Close()

	readerDone := make(chan struct{})
	var captured bytes.Buffer
	defer func() { _ = os.WriteFile(rawPath, captured.Bytes(), 0o644) }()
	go func() { _, _ = io.Copy(&captured, sess.Master); close(readerDone) }()

	time.Sleep(900 * time.Millisecond)
	line := ""
	version := 0
	for _, r := range chars {
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
		_ = appendTrace(tracePath, map[string]any{"kind": "master.typed", "line": line, "slot_kind": ctx.Slot.Kind, "slot_path": ctx.Slot.Path, "labels": labels})
		time.Sleep(90 * time.Millisecond)
	}
	time.Sleep(1400 * time.Millisecond)
	_, _ = sess.Master.Write([]byte("\x1b:q!\r"))
	_ = sess.Wait()
	select {
	case <-readerDone:
	case <-time.After(900 * time.Millisecond):
	}
	_ = os.WriteFile(rawPath, captured.Bytes(), 0o644)

	traceRows, err := readJSONL(tracePath)
	if err != nil {
		return err
	}
	popupOK := false
	for _, row := range traceRows {
		if row["kind"] == "vim.popup.rendered" && contains(row["labels"], "task:t1") && contains(row["labels"], "task:t2") && contains(row["labels"], "task:t3") {
			popupOK = true
		}
	}
	screenBytes, _ := os.ReadFile(screenTextPath)
	screen := string(screenBytes)
	screenOK := strings.Contains(screen, "HQ SLOT PROJECTION") && strings.Contains(screen, "task:t1") && strings.Contains(screen, "task:t2") && strings.Contains(screen, "task:t3")
	result := map[string]any{
		"kind":                  "proof.conpty-vim-rsc-visual-projection",
		"argv":                  argv,
		"pid":                   sess.PID(),
		"typed_chars":           chars,
		"trace":                 tracePath,
		"screen_text":           screenTextPath,
		"raw_pty_transcript":    rawPath,
		"trace_rows":            len(traceRows),
		"vim_popup_trace_ok":    popupOK,
		"screen_contains_popup": screenOK,
		"visual_projection_ok":  popupOK && screenOK,
		"direct_vim_no_shell":   true,
		"captured_screen_bytes": captured.Len(),
	}
	if err := writeJSON(out, result); err != nil {
		return err
	}
	if !popupOK || !screenOK {
		return fmt.Errorf("ConPTY/Vim visual proof failed: popup=%v screen=%v", popupOK, screenOK)
	}
	return nil
}

func toVimPath(p string) string { return strings.ReplaceAll(p, "\\", "/") }

func lookupVim() (string, error) {
	names := []string{"vim", "vim.exe", "nvim", "nvim.exe"}
	for _, name := range names {
		if p, err := exec.LookPath(name); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("vim/nvim executable not found")
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
		projection[line] = map[string]any{"slot_kind": ctx.Slot.Kind, "slot_path": ctx.Slot.Path, "labels": labels, "rows": rows}
	}
	return projection
}

func writeVimscript(projection map[string]any, tracePath, screenTextPath string) (string, error) {
	path := filepath.Join(os.TempDir(), fmt.Sprintf("hq-conpty-rsc-visual-%d.vim", time.Now().UnixNano()))
	projectionJSON, _ := json.Marshal(projection)
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
call writefile([json_encode({'kind':'vim.script.start','cwd':getcwd()})], g:hq_trace, 'a')
let g:hq_projection_by_line = json_decode(%s)
call writefile([json_encode({'kind':'vim.script.decoded','has_popup':exists('*popup_create')})], g:hq_trace, 'a')
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
  sleep 90m
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

func appendTrace(path string, row map[string]any) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	b, _ := json.Marshal(row)
	_, err = f.Write(append(b, '\n'))
	return err
}
func readJSONL(path string) ([]map[string]any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	rows := []map[string]any{}
	for _, line := range strings.Split(strings.TrimSpace(string(b)), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		var row map[string]any
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			return nil, err
		}
		rows = append(rows, row)
	}
	return rows, nil
}
func contains(v any, want string) bool {
	switch x := v.(type) {
	case []any:
		for _, item := range x {
			if fmt.Sprint(item) == want {
				return true
			}
		}
	case []string:
		for _, item := range x {
			if item == want {
				return true
			}
		}
	}
	return false
}
func vimString(s string) string { b, _ := json.Marshal(s); return string(b) }
func writeJSON(path string, v any) error {
	b, _ := json.MarshalIndent(v, "", "  ")
	return os.WriteFile(path, append(b, '\n'), 0o644)
}
