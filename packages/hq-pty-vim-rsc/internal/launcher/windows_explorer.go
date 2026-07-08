package launcher

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"sort"
	"strings"
)

type Target struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Kind string `json:"kind"`
}

type ExplorerPlan struct {
	Kind            string   `json:"kind"`
	Target          string   `json:"target,omitempty"`
	Path            string   `json:"path"`
	Mode            string   `json:"mode"`
	Executable      string   `json:"executable"`
	Args            []string `json:"args"`
	SideEffect      bool     `json:"side_effect"`
	RequiresConfirm bool     `json:"requires_confirm"`
}

type SmokeResult struct {
	Kind                  string         `json:"kind"`
	Home                  string         `json:"home"`
	Targets               []Target       `json:"targets"`
	Plans                 []ExplorerPlan `json:"plans"`
	PreviewSideEffectFree bool           `json:"preview_side_effect_free"`
	RemoteMappingGuardOK  bool           `json:"remote_mapping_guard_ok"`
	OK                    bool           `json:"ok"`
}

func DefaultTargets(home string) []Target {
	home = strings.TrimRight(home, `\/`)
	return []Target{
		{Name: "home", Path: home, Kind: "dir"},
		{Name: "codex", Path: winJoin(home, "Codex"), Kind: "dir"},
		{Name: "repos", Path: winJoin(home, "Codex", "repos"), Kind: "dir"},
		{Name: "edits", Path: winJoin(home, "Codex", "repos", "edits"), Kind: "dir"},
	}
}

func CompleteTargets(home, base string) []Target {
	base = strings.ToLower(strings.TrimSpace(base))
	targets := DefaultTargets(home)
	out := make([]Target, 0, len(targets))
	for _, t := range targets {
		if base == "" || strings.HasPrefix(strings.ToLower(t.Name), base) {
			out = append(out, t)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func ResolveTarget(home, name string) (Target, error) {
	for _, t := range DefaultTargets(home) {
		if t.Name == name {
			return t, nil
		}
	}
	return Target{}, fmt.Errorf("unknown explorer target %q", name)
}

func PreviewOpen(target Target) (ExplorerPlan, error) {
	if err := validateLocalWindowsPath(target.Path); err != nil {
		return ExplorerPlan{}, err
	}
	return ExplorerPlan{Kind: "windows.explorer.preview", Target: target.Name, Path: target.Path, Mode: "open", Executable: "explorer.exe", Args: []string{target.Path}, SideEffect: false, RequiresConfirm: true}, nil
}

func PreviewSelect(path string) (ExplorerPlan, error) {
	if err := validateLocalWindowsPath(path); err != nil {
		return ExplorerPlan{}, err
	}
	return ExplorerPlan{Kind: "windows.explorer.preview", Path: path, Mode: "select", Executable: "explorer.exe", Args: []string{"/select," + path}, SideEffect: false, RequiresConfirm: true}, nil
}

func Execute(plan ExplorerPlan) error {
	if plan.SideEffect {
		return errors.New("refusing to execute a plan already marked side_effect=true")
	}
	if plan.Executable != "explorer.exe" {
		return fmt.Errorf("unexpected executable %q", plan.Executable)
	}
	if runtime.GOOS != "windows" {
		return fmt.Errorf("explorer.exe execution requires windows; preview was %v", plan.Args)
	}
	cmd := exec.Command(plan.Executable, plan.Args...)
	return cmd.Start()
}

func Smoke(home string) (SmokeResult, error) {
	targets := DefaultTargets(home)
	result := SmokeResult{Kind: "windows.explorer.smoke", Home: home, Targets: targets, PreviewSideEffectFree: true, RemoteMappingGuardOK: true}
	want := map[string]string{
		"home":  strings.TrimRight(home, `\/`),
		"codex": winJoin(home, "Codex"),
		"repos": winJoin(home, "Codex", "repos"),
		"edits": winJoin(home, "Codex", "repos", "edits"),
	}
	for _, t := range targets {
		if t.Path != want[t.Name] {
			return result, fmt.Errorf("target %s path got %q want %q", t.Name, t.Path, want[t.Name])
		}
		plan, err := PreviewOpen(t)
		if err != nil {
			return result, err
		}
		if plan.SideEffect {
			result.PreviewSideEffectFree = false
		}
		result.Plans = append(result.Plans, plan)
	}
	selectPlan, err := PreviewSelect(winJoin(want["edits"], "README.md"))
	if err != nil {
		return result, err
	}
	result.Plans = append(result.Plans, selectPlan)
	if _, err := PreviewOpen(Target{Name: "kite", Path: "ssh://kite/home/repo", Kind: "remote"}); err == nil {
		result.RemoteMappingGuardOK = false
		return result, fmt.Errorf("remote path was not blocked")
	}
	result.OK = result.PreviewSideEffectFree && result.RemoteMappingGuardOK
	return result, nil
}

func HomeFromEnvOrDefault(explicit string) string {
	if explicit != "" {
		return explicit
	}
	if v := os.Getenv("USERPROFILE"); v != "" {
		return v
	}
	if v := os.Getenv("HOME"); v != "" {
		return v
	}
	return `C:\Users\resta`
}

func validateLocalWindowsPath(path string) error {
	p := strings.TrimSpace(path)
	if p == "" {
		return errors.New("empty path")
	}
	lower := strings.ToLower(p)
	if strings.Contains(lower, "://") || strings.HasPrefix(lower, "ssh:") || strings.HasPrefix(lower, "kite:") || strings.HasPrefix(lower, "ssot:") {
		return fmt.Errorf("remote path requires explicit local mapping: %s", path)
	}
	return nil
}

func MarshalPretty(v any) []byte {
	b, _ := json.MarshalIndent(v, "", "  ")
	return append(b, '\n')
}

func winJoin(base string, parts ...string) string {
	out := strings.TrimRight(base, `\/`)
	for _, part := range parts {
		part = strings.Trim(part, `\/`)
		if part == "" {
			continue
		}
		out += `\` + part
	}
	return out
}
