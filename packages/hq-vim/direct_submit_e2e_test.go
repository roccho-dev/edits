package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/roccho-dev/edits/packages/hq-vim/internal/smoke"
)

// TestDirectCommandSubmitE2E fixes only the explicit deterministic fallback:
// one direct command becomes one typed host instruction, and successful
// acceptance consumes only that draft while one native undo restores it.
func TestDirectCommandSubmitE2E(t *testing.T) {
	hqBin := os.Getenv("HQ_BIN")
	if hqBin == "" {
		t.Skip("HQ_BIN is required")
	}
	root := mustPackageRoot(t)
	profileEnv, accepted := prepareStrictHQProfile(t, root, "local")
	submitText := "@direct.open\npath=demo.jsonl"
	resultRoot := t.TempDir()
	resultPath := filepath.Join(resultRoot, "submit-result.json")
	bufferResult := filepath.Join(resultRoot, "buffer-after.json")
	undoResult := filepath.Join(resultRoot, "buffer-undo.json")
	messages := filepath.Join(resultRoot, "messages.txt")
	cfg := smoke.Config{
		HQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t),
		PluginRoot: root, Profile: "local", Buffer: filepath.Join(t.TempDir(), "direct-submit.hqjson"),
		BufferText: submitText, Headless: true, Env: profileEnv,
		ResultPath: resultPath, BufferResultPath: bufferResult,
		UndoResultPath: undoResult, MessagesPath: messages,
	}
	if err := smoke.Run(cfg); err != nil {
		t.Fatalf("direct command submit E2E failed: %v", err)
	}

	rows := readJSONLRows(t, accepted)
	if len(rows) != 1 || rows[0]["kind"] != "accepted.instruction" {
		t.Fatalf("accepted rows=%#v", rows)
	}
	instruction, ok := rows[0]["instruction"].(map[string]any)
	if !ok || instruction["target"] != "host" || instruction["op"] != "run" {
		t.Fatalf("direct instruction=%#v", instruction)
	}
	payload, ok := instruction["payload"].(map[string]any)
	if !ok || payload["capability"] != "host.open" || payload["path"] != "demo.jsonl" {
		t.Fatalf("direct payload=%#v", payload)
	}
	result := readJSONObject(t, resultPath)
	if result["kind"] != "hq.submitResult.v1" || result["status"] != "queued" || result["queueId"] != instruction["id"] {
		t.Fatalf("direct submit result=%#v", result)
	}
	consumption, ok := result["draftConsumption"].(map[string]any)
	if !ok || consumption["kind"] != "hq.draftConsumption.v1" {
		t.Fatalf("draft consumption=%#v", result["draftConsumption"])
	}
	if got := readVimBuffer(t, bufferResult); len(got.Lines) != 1 || got.Lines[0] != "" {
		t.Fatalf("accepted draft was not consumed: %#v", got)
	}
	if got := readVimBuffer(t, undoResult); strings.Join(got.Lines, "\n") != submitText {
		t.Fatalf("one Vim undo did not restore submitted text: %#v", got)
	}
	if got := readText(t, messages); !strings.Contains(got, "draft consumed") {
		t.Fatalf("missing consumed outcome: %s", got)
	}
}

func readJSONObject(t *testing.T, path string) map[string]any {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var value map[string]any
	if err := json.Unmarshal(content, &value); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}
	return value
}

func readJSONLRows(t *testing.T, path string) []map[string]any {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var rows []map[string]any
	for _, line := range strings.Split(string(content), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		var row map[string]any
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			t.Fatalf("decode %s: %v", path, err)
		}
		rows = append(rows, row)
	}
	return rows
}
