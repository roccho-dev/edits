package dispatcher

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"hq/internal/core"
)

type Adapter interface {
	Name() string
	Execute(ctx context.Context, plan core.PlanDraft) (map[string]any, error)
}

type MockAdapter struct{ name string }

func (m MockAdapter) Name() string { return m.name }
func (m MockAdapter) Execute(ctx context.Context, plan core.PlanDraft) (map[string]any, error) {
	return map[string]any{"adapter": m.name, "action": plan.Action, "target": plan.Target, "args": plan.Args, "dry_run": true}, nil
}

type ShellAdapter struct{}

func (ShellAdapter) Name() string { return "shell.exec" }
func (ShellAdapter) Execute(parent context.Context, plan core.PlanDraft) (map[string]any, error) {
	cmdText := plan.Args["command"]
	if strings.TrimSpace(cmdText) == "" {
		return nil, fmt.Errorf("shell.exec missing command")
	}
	timeout := 5 * time.Second
	if raw := plan.Args["timeout"]; raw != "" {
		if d, err := time.ParseDuration(raw); err == nil {
			timeout = d
		}
	}
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.CommandContext(ctx, "cmd", "/C", cmdText)
	} else {
		cmd = exec.CommandContext(ctx, "/bin/sh", "-c", cmdText)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	start := time.Now()
	err := cmd.Run()
	result := map[string]any{
		"adapter":     ShellAdapter{}.Name(),
		"command":     cmdText,
		"stdout":      stdout.String(),
		"stderr":      stderr.String(),
		"duration_ms": time.Since(start).Milliseconds(),
	}
	if ctx.Err() == context.DeadlineExceeded {
		result["timed_out"] = true
		return result, fmt.Errorf("shell command timed out after %s", timeout)
	}
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			result["exit_code"] = exitErr.ExitCode()
		}
		return result, err
	}
	result["exit_code"] = 0
	return result, nil
}

func Name(a Adapter) string { return a.Name() }

type HTTPAdapter struct {
	Client *http.Client
}

func (HTTPAdapter) Name() string { return "http.request" }
func (a HTTPAdapter) Execute(ctx context.Context, plan core.PlanDraft) (map[string]any, error) {
	method := plan.Args["method"]
	if method == "" {
		method = "GET"
	}
	url := plan.Args["url"]
	if url == "" {
		return nil, fmt.Errorf("http.request missing url")
	}
	body := strings.NewReader(plan.Args["body"])
	req, err := http.NewRequestWithContext(ctx, method, url, body)
	if err != nil {
		return nil, err
	}
	if body.Len() > 0 {
		req.Header.Set("Content-Type", plan.Args["content_type"])
		if req.Header.Get("Content-Type") == "" {
			req.Header.Set("Content-Type", "text/plain")
		}
	}
	client := a.Client
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, readErr := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if readErr != nil {
		return nil, readErr
	}
	return map[string]any{
		"adapter":      a.Name(),
		"method":       method,
		"url":          url,
		"status":       resp.StatusCode,
		"body_preview": string(data),
		"duration_ms":  time.Since(start).Milliseconds(),
	}, nil
}

type Dispatcher struct {
	adapters map[string]Adapter
	mu       sync.Mutex
}

func NewDefault() *Dispatcher {
	d := &Dispatcher{adapters: map[string]Adapter{}}
	for _, name := range []string{"mux.spawn", "pane.send", "agent.ask", "file.edit", "git.run"} {
		d.adapters[name] = MockAdapter{name: name}
	}
	d.adapters["http.request"] = HTTPAdapter{}
	d.adapters["shell.exec"] = ShellAdapter{}
	return d
}

func (d *Dispatcher) Register(adapter Adapter) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.adapters[adapter.Name()] = adapter
}

type Request struct {
	Plan          core.PlanDraft `json:"plan"`
	PlanID        string         `json:"plan_id"`
	PlanHash      string         `json:"plan_hash"`
	BufferVersion int            `json:"buffer_version"`
	Confirmed     bool           `json:"confirmed"`
}

type Receipt struct {
	Kind          string         `json:"kind"`
	ReceiptID     string         `json:"receipt_id"`
	Time          string         `json:"time"`
	PlanID        string         `json:"plan_id"`
	PlanHash      string         `json:"plan_hash"`
	BufferVersion int            `json:"buffer_version"`
	Adapter       string         `json:"adapter"`
	Action        string         `json:"action"`
	Target        string         `json:"target,omitempty"`
	Result        map[string]any `json:"result"`
}

func (d *Dispatcher) Dispatch(req Request) (Receipt, error) {
	d.mu.Lock()
	adapter, ok := d.adapters[req.Plan.Adapter]
	d.mu.Unlock()
	if err := core.ValidatePlan(req.Plan); err != nil {
		return Receipt{}, err
	}
	if req.PlanID != req.Plan.ID {
		return Receipt{}, fmt.Errorf("dispatch plan_id mismatch: got %s want %s", req.PlanID, req.Plan.ID)
	}
	if req.PlanHash != req.Plan.Hash {
		return Receipt{}, fmt.Errorf("dispatch plan_hash mismatch: got %s want %s", req.PlanHash, req.Plan.Hash)
	}
	if req.BufferVersion != req.Plan.BufferVersion {
		return Receipt{}, fmt.Errorf("dispatch buffer_version mismatch: got %d want %d", req.BufferVersion, req.Plan.BufferVersion)
	}
	if req.Plan.RequiresConfirm && !req.Confirmed {
		return Receipt{}, fmt.Errorf("plan requires confirm=true before dispatch")
	}
	if !ok {
		return Receipt{}, fmt.Errorf("no adapter registered for %q", req.Plan.Adapter)
	}
	ctx := context.Background()
	if raw := req.Plan.Args["timeout"]; raw != "" {
		if d, err := time.ParseDuration(raw); err == nil {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(ctx, d)
			defer cancel()
		}
	}
	result, err := adapter.Execute(ctx, req.Plan)
	if err != nil {
		return Receipt{}, err
	}
	ts := time.Now().UTC().Format(time.RFC3339Nano)
	receipt := Receipt{
		Kind: "dispatch.receipt", ReceiptID: "rcpt_" + req.Plan.Hash[:12], Time: ts,
		PlanID: req.Plan.ID, PlanHash: req.Plan.Hash, BufferVersion: req.Plan.BufferVersion,
		Adapter: req.Plan.Adapter, Action: req.Plan.Action, Target: req.Plan.Target, Result: result,
	}
	return receipt, nil
}

func AppendReceipt(path string, receipt Receipt) error {
	if path == "" {
		return nil
	}
	dir := filepath.Dir(path)
	if dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := json.Marshal(receipt)
	if err != nil {
		return err
	}
	_, err = f.Write(append(b, '\n'))
	return err
}

func ReceiptHasStatus(receipt Receipt, status int) bool {
	v, ok := receipt.Result["status"]
	if !ok {
		return false
	}
	switch x := v.(type) {
	case int:
		return x == status
	case float64:
		return int(x) == status
	case string:
		return x == strconv.Itoa(status)
	default:
		return false
	}
}
