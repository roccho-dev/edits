package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/roccho-dev/edits/packages/hq-vim/internal/smoke"
)

func TestMissingExplicitHQBindingFailsFast(t *testing.T) {
	cfg := smoke.Config{
		Vim:        requireVim(t),
		Vim9LSP:    requireVim9LSP(t),
		PluginRoot: mustPackageRoot(t),
		Profile:    "local",
		Buffer:     filepath.Join(t.TempDir(), "manual.hqjson"),
		Headless:   true,
		StartOnly:  true,
		OmitHQBin:  true,
	}
	if err := smoke.Run(cfg); err == nil {
		t.Fatal("expected missing explicit g:hq_bin to fail during HqStart")
	}
}

func TestRelativeHQBinaryFailsFast(t *testing.T) {
	root := mustPackageRoot(t)
	relativeDir := filepath.Join(root, ".tmp", "relative-hq-test")
	if err := os.MkdirAll(relativeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(relativeDir)
	relative := filepath.Join(".tmp", "relative-hq-test", exeName("hqstub"))
	buildHQStubAt(t, filepath.Join(root, relative))
	cfg := smoke.Config{
		HQBin:      relative,
		Vim:        requireVim(t),
		Vim9LSP:    requireVim9LSP(t),
		PluginRoot: root,
		Profile:    "local",
		Buffer:     filepath.Join(t.TempDir(), "manual.hqjson"),
		Headless:   true,
		StartOnly:  true,
	}
	if err := smoke.Run(cfg); err == nil {
		t.Fatal("expected relative g:hq_bin to fail during HqStart")
	}
}

func TestCanonicalHQVimConformance(t *testing.T) {
	hqBin := os.Getenv("HQ_CANONICAL_BIN")
	if hqBin == "" {
		t.Skip("HQ_CANONICAL_BIN is not set")
	}
	if !filepath.IsAbs(hqBin) {
		t.Fatalf("HQ_CANONICAL_BIN must be absolute: %q", hqBin)
	}
	root := mustPackageRoot(t)
	profile := prepareCanonicalProfile(t)
	assertCanonicalProfileStarts(t, hqBin, profile.Env)
	completionText := `{"op":q`
	submitText := `{"op":"queue.create","target":"ctx","payload":{"path":"demo.jsonl"}}`

	completionCfg := smoke.Config{
		HQBin:                   hqBin,
		Vim:                     requireVim(t),
		Vim9LSP:                 requireVim9LSP(t),
		PluginRoot:              root,
		Profile:                 "local",
		Buffer:                  filepath.Join(t.TempDir(), "completion-only.hqjson"),
		CompletionText:          completionText,
		ExpectedCompletionLabel: "queue.create",
		Headless:                true,
		SkipSubmit:              true,
		Env:                     profile.Env,
	}
	if err := smoke.Run(completionCfg); err != nil {
		t.Fatalf("canonical hq Vim completion-only conformance failed: %v", err)
	}
	if rows := readJSONLRows(t, profile.AcceptedPath); len(rows) != 0 {
		t.Fatalf("completion-only run wrote %d durable rows", len(rows))
	}

	var acceptedIDs []string
	for run := 1; run <= 2; run++ {
		resultPath := filepath.Join(t.TempDir(), "submit-result.json")
		cfg := smoke.Config{
			HQBin:      hqBin,
			Vim:        requireVim(t),
			Vim9LSP:    requireVim9LSP(t),
			PluginRoot: root,
			Profile:    "local",
			Buffer:     filepath.Join(t.TempDir(), "submit.hqjson"),
			BufferText: submitText,
			Headless:   true,
			Env:        profile.Env,
			ResultPath: resultPath,
		}
		if err := smoke.Run(cfg); err != nil {
			t.Fatalf("canonical hq Vim submit run %d failed: %v", run, err)
		}
		rows := readJSONLRows(t, profile.AcceptedPath)
		if len(rows) != run {
			t.Fatalf("accepted rows after run %d = %d, want %d", run, len(rows), run)
		}
		row := rows[run-1]
		if row["kind"] != "accepted.instruction" {
			t.Fatalf("accepted row kind = %v", row["kind"])
		}
		instruction, ok := row["instruction"].(map[string]any)
		if !ok {
			t.Fatalf("accepted row has no instruction object: %#v", row)
		}
		id, _ := instruction["id"].(string)
		if id == "" {
			t.Fatalf("accepted instruction has no id: %#v", instruction)
		}
		result := readJSONObject(t, resultPath)
		if result["kind"] != "hq.submitResult.v1" || result["status"] != "queued" {
			t.Fatalf("unexpected submit result: %#v", result)
		}
		if result["queueKind"] != "accepted.instruction" {
			t.Fatalf("submit queueKind = %v", result["queueKind"])
		}
		if result["queueId"] != id {
			t.Fatalf("submit queueId = %v, appended instruction id = %s", result["queueId"], id)
		}
		if result["deploymentId"] != "edits-ci" {
			t.Fatalf("submit deploymentId = %v", result["deploymentId"])
		}
		acceptedIDs = append(acceptedIDs, id)
	}
	if acceptedIDs[0] == acceptedIDs[1] {
		t.Fatalf("repeated explicit submits reused id %q", acceptedIDs[0])
	}
	writeCanonicalArtifact(t, map[string]any{
		"kind":                  "edits.hqVimConformance.v1",
		"status":                "passed",
		"hqSourceSha":           os.Getenv("HQ_CANONICAL_SOURCE_SHA"),
		"completionLabel":       "queue.create",
		"completionWrites":      0,
		"explicitSubmitRuns":    2,
		"acceptedRows":          2,
		"acceptedIDsDistinct":   true,
		"submitIdentityMatches": true,
		"pathLookupUsed":        false,
		"binding":               "explicit-absolute-g:hq_bin",
		"boundary":              "real Vim 9 -> pinned yegappan/lsp -> canonical hq lsp -> accepted.instruction",
	})
	t.Logf("canonical hq Vim conformance passed against %s", os.Getenv("HQ_CANONICAL_SOURCE_SHA"))
}

type canonicalProfile struct {
	AcceptedPath string
	Env          map[string]string
}

func prepareCanonicalProfile(t *testing.T) canonicalProfile {
	t.Helper()
	root := t.TempDir()
	configRoot := filepath.Join(root, "config")
	profileDir := filepath.Join(configRoot, "roccho", "hq", "profiles")
	workspace := filepath.Join(root, "workspace")
	eventsDir := filepath.Join(workspace, ".hq", "events")
	for _, dir := range []string{profileDir, eventsDir} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	worldPath := filepath.Join(root, "world.jsonl")
	acceptedPath := filepath.Join(root, "accepted.jsonl")
	capabilitiesPath := filepath.Join(root, "capabilities.json")
	world, err := os.ReadFile(filepath.Join(mustPackageRoot(t), "testdata", "world.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(worldPath, world, 0o600); err != nil {
		t.Fatal(err)
	}
	for path, content := range map[string]string{
		acceptedPath:     "",
		capabilitiesPath: "{}\n",
	} {
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	profile := map[string]any{
		"kind":              "hq.profile.v1",
		"name":              "local",
		"deployment_id":     "edits-ci",
		"world_path":        worldPath,
		"accepted_path":     acceptedPath,
		"workspace_root":    workspace,
		"events_path":       filepath.Join(eventsDir, "events.jsonl"),
		"capabilities_path": capabilitiesPath,
		"poll_interval_ms":  50,
		"health_timeout_ms": 500,
	}
	encoded, err := json.Marshal(profile)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(profileDir, "local.json"), encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	env := map[string]string{}
	if runtime.GOOS == "windows" {
		env["APPDATA"] = configRoot
	} else {
		env["XDG_CONFIG_HOME"] = configRoot
	}
	return canonicalProfile{AcceptedPath: acceptedPath, Env: env}
}

func assertCanonicalProfileStarts(t *testing.T, hqBin string, overrides map[string]string) {
	t.Helper()
	cmd := exec.Command(hqBin, "lsp", "--profile", "local")
	cmd.Stdin = strings.NewReader("")
	cmd.Env = mergeEnvironment(os.Environ(), overrides)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("canonical hq rejected generated profile before Vim: %v\n%s", err, output)
	}
}

func mergeEnvironment(base []string, overrides map[string]string) []string {
	result := append([]string(nil), base...)
	for key, value := range overrides {
		replaced := false
		for i, entry := range result {
			name, _, _ := strings.Cut(entry, "=")
			matches := name == key
			if runtime.GOOS == "windows" {
				matches = strings.EqualFold(name, key)
			}
			if matches {
				result[i] = key + "=" + value
				replaced = true
			}
		}
		if !replaced {
			result = append(result, key+"="+value)
		}
	}
	return result
}

func writeCanonicalArtifact(t *testing.T, proof map[string]any) {
	t.Helper()
	path := os.Getenv("HQ_CONFORMANCE_ARTIFACT")
	if path == "" {
		return
	}
	if proof["hqSourceSha"] == "" {
		t.Fatal("HQ_CANONICAL_SOURCE_SHA is required when writing conformance evidence")
	}
	encoded, err := json.MarshalIndent(proof, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, append(encoded, '\n'), 0o644); err != nil {
		t.Fatal(err)
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

func buildHQStubAt(t *testing.T, out string) {
	t.Helper()
	cmd := exec.Command("go", "build", "-o", out, "./testfixture/hqstub")
	cmd.Dir = mustPackageRoot(t)
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("build hq stub: %v\n%s", err, b)
	}
}
