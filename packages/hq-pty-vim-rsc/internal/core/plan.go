package core

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

type CursorContext struct {
	Line          string `json:"line"`
	Prefix        string `json:"prefix"`
	BufferVersion int    `json:"buffer_version"`
}

type PlanDraft struct {
	ID              string            `json:"id"`
	Hash            string            `json:"hash"`
	BufferVersion   int               `json:"buffer_version"`
	ModelDigest     string            `json:"model_digest"`
	CommandText     string            `json:"command_text"`
	EditText        string            `json:"edit_text"`
	Adapter         string            `json:"adapter"`
	Action          string            `json:"action"`
	Target          string            `json:"target,omitempty"`
	Args            map[string]string `json:"args,omitempty"`
	Meaning         string            `json:"meaning"`
	RequiresConfirm bool              `json:"requires_confirm"`
	SideEffect      bool              `json:"side_effect"`
}

type Suggestion struct {
	Label     string    `json:"label"`
	Detail    string    `json:"detail"`
	EditText  string    `json:"edit_text"`
	Meaning   string    `json:"meaning"`
	PlanDraft PlanDraft `json:"plan_draft"`
}

type Diagnostic struct {
	Severity string `json:"severity"`
	Message  string `json:"message"`
	Start    int    `json:"start"`
	End      int    `json:"end"`
}

func Complete(m Model, ctx CursorContext) []Suggestion {
	prefix := strings.TrimSpace(ctx.Prefix)
	if prefix == "" {
		prefix = strings.TrimSpace(ctx.Line)
	}
	var out []Suggestion
	for _, tmpl := range m.Templates {
		if !matchesTemplate(prefix, tmpl) {
			continue
		}
		plan, err := BuildPlan(m, tmpl.Insert, ctx.BufferVersion)
		if err != nil {
			continue
		}
		out = append(out, Suggestion{Label: tmpl.Label, Detail: tmpl.Description, EditText: tmpl.Insert, Meaning: plan.Meaning, PlanDraft: plan})
	}
	return out
}

func matchesTemplate(prefix string, tmpl CommandTemplate) bool {
	if prefix == "" {
		return true
	}
	p := strings.ToLower(prefix)
	return strings.HasPrefix(strings.ToLower(tmpl.Insert), p) ||
		strings.Contains(strings.ToLower(tmpl.Label), p) ||
		strings.Contains(strings.ToLower(tmpl.Adapter), p)
}

func BuildPlan(m Model, command string, bufferVersion int) (PlanDraft, error) {
	parsed, err := parseCommand(command)
	if err != nil {
		return PlanDraft{}, err
	}
	adapter, ok := m.Adapters[parsed.Adapter]
	if !ok {
		return PlanDraft{}, fmt.Errorf("unknown adapter %q", parsed.Adapter)
	}
	if parsed.Target != "" {
		if _, ok := m.Targets[parsed.Target]; !ok && !builtinTarget(parsed.Target) {
			return PlanDraft{}, fmt.Errorf("unknown target %q", parsed.Target)
		}
	}
	plan := PlanDraft{
		BufferVersion:   bufferVersion,
		ModelDigest:     m.Digest,
		CommandText:     command,
		EditText:        command,
		Adapter:         parsed.Adapter,
		Action:          parsed.Action,
		Target:          parsed.Target,
		Args:            parsed.Args,
		Meaning:         parsed.Meaning,
		RequiresConfirm: parsed.RequiresConfirm || !adapter.Safe,
		SideEffect:      false,
	}
	plan.Hash = planHash(plan)
	plan.ID = "plan_" + plan.Hash[:12]
	return plan, nil
}

func builtinTarget(t string) bool {
	switch t {
	case "mux", "http", "shell", "git", "file", "tmux":
		return true
	default:
		return strings.HasPrefix(t, "http")
	}
}

func ValidatePlan(plan PlanDraft) error {
	expected := planHash(plan)
	if plan.Hash != expected {
		return fmt.Errorf("plan hash mismatch: got %s want %s", plan.Hash, expected)
	}
	if len(plan.Hash) < 12 || plan.ID != "plan_"+plan.Hash[:12] {
		return fmt.Errorf("plan id mismatch: got %s want %s", plan.ID, "plan_"+plan.Hash[:12])
	}
	if plan.SideEffect {
		return fmt.Errorf("PlanDraft must be side_effect=false before dispatch")
	}
	return nil
}

func planHash(plan PlanDraft) string {
	payload := struct {
		BufferVersion   int               `json:"buffer_version"`
		ModelDigest     string            `json:"model_digest"`
		CommandText     string            `json:"command_text"`
		EditText        string            `json:"edit_text"`
		Adapter         string            `json:"adapter"`
		Action          string            `json:"action"`
		Target          string            `json:"target,omitempty"`
		Args            map[string]string `json:"args,omitempty"`
		Meaning         string            `json:"meaning"`
		RequiresConfirm bool              `json:"requires_confirm"`
		SideEffect      bool              `json:"side_effect"`
	}{
		BufferVersion: plan.BufferVersion, ModelDigest: plan.ModelDigest, CommandText: plan.CommandText,
		EditText: plan.EditText, Adapter: plan.Adapter, Action: plan.Action, Target: plan.Target,
		Args: plan.Args, Meaning: plan.Meaning, RequiresConfirm: plan.RequiresConfirm, SideEffect: plan.SideEffect,
	}
	b, _ := json.Marshal(payload)
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

type parsedCommand struct {
	Adapter         string
	Action          string
	Target          string
	Args            map[string]string
	Meaning         string
	RequiresConfirm bool
}

var (
	reMuxSpawn = regexp.MustCompile(`^mux\.spawn\s+(\S+)(.*)$`)
	rePaneSend = regexp.MustCompile(`^pane\.([A-Za-z0-9_-]+)\.send\s+"([^"]*)"\s*(enter)?\s*$`)
	reAgent    = regexp.MustCompile(`^agent\.([A-Za-z0-9_-]+)\.(ask|fix)\s+(.+)$`)
	reHTTP     = regexp.MustCompile(`^http\.(get|post|put|delete|patch)\s+(\S+)(.*)$`)
	reGitRun   = regexp.MustCompile(`^git\.run\s+(.+)$`)
	reFileEdit = regexp.MustCompile(`^file\.edit\s+(.+)$`)
	reShell    = regexp.MustCompile(`^shell\.exec\s+"([^"]*)"(.*)$`)
)

func parseCommand(command string) (parsedCommand, error) {
	command = strings.TrimSpace(command)
	if command == "" {
		return parsedCommand{}, fmt.Errorf("empty command")
	}
	if m := reMuxSpawn.FindStringSubmatch(command); m != nil {
		args := parseKV(m[2])
		args["app"] = m[1]
		return parsedCommand{Adapter: "mux.spawn", Action: "spawn", Target: "mux", Args: args, Meaning: "spawn new slave " + m[1], RequiresConfirm: false}, nil
	}
	if m := rePaneSend.FindStringSubmatch(command); m != nil {
		target := "pane." + m[1]
		args := map[string]string{"text": m[2]}
		if m[3] == "enter" {
			args["enter"] = "true"
		}
		return parsedCommand{Adapter: "pane.send", Action: "send", Target: target, Args: args, Meaning: "send input to " + target, RequiresConfirm: false}, nil
	}
	if m := reAgent.FindStringSubmatch(command); m != nil {
		target := "agent." + m[1]
		rest := m[3]
		args := map[string]string{"payload": rest}
		if idx := strings.Index(rest, " with="); idx >= 0 {
			args["payload"] = strings.TrimSpace(rest[:idx])
			args["with"] = strings.TrimSpace(rest[idx+6:])
		}
		return parsedCommand{Adapter: "agent.ask", Action: m[2], Target: target, Args: args, Meaning: m[2] + " " + target + " with explicit context", RequiresConfirm: false}, nil
	}
	if m := reHTTP.FindStringSubmatch(command); m != nil {
		args := parseKV(m[3])
		args["method"] = strings.ToUpper(m[1])
		args["url"] = m[2]
		return parsedCommand{Adapter: "http.request", Action: "request", Target: "http", Args: args, Meaning: strings.ToUpper(m[1]) + " " + m[2] + " through http adapter", RequiresConfirm: false}, nil
	}
	if m := reShell.FindStringSubmatch(command); m != nil {
		args := parseKV(m[2])
		args["command"] = m[1]
		return parsedCommand{Adapter: "shell.exec", Action: "exec", Target: "shell", Args: args, Meaning: "execute shell command through confirmed shell adapter", RequiresConfirm: true}, nil
	}
	if m := reGitRun.FindStringSubmatch(command); m != nil {
		return parsedCommand{Adapter: "git.run", Action: "run", Target: "git", Args: map[string]string{"argv": m[1]}, Meaning: "run git adapter command", RequiresConfirm: true}, nil
	}
	if m := reFileEdit.FindStringSubmatch(command); m != nil {
		return parsedCommand{Adapter: "file.edit", Action: "edit", Target: "file", Args: map[string]string{"request": m[1]}, Meaning: "edit file through adapter", RequiresConfirm: true}, nil
	}
	return parsedCommand{}, fmt.Errorf("unrecognized command form")
}

func parseKV(s string) map[string]string {
	out := map[string]string{}
	for _, tok := range strings.Fields(strings.TrimSpace(s)) {
		if parts := strings.SplitN(tok, "=", 2); len(parts) == 2 {
			out[parts[0]] = strings.Trim(parts[1], `"`)
		}
	}
	return out
}

func Diagnose(m Model, line string, bufferVersion int) []Diagnostic {
	s := strings.TrimSpace(line)
	if s == "" {
		return nil
	}
	if _, err := BuildPlan(m, s, bufferVersion); err == nil {
		return nil
	} else {
		if len(Complete(m, CursorContext{Line: line, Prefix: line, BufferVersion: bufferVersion})) > 0 {
			return nil
		}
		return []Diagnostic{{Severity: "error", Message: err.Error(), Start: 0, End: len(line)}}
	}
}
