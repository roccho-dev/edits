package dispatcher

import (
	"context"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"testing"

	"hq/internal/core"
)

func testPlan(t *testing.T, command string, version int) core.PlanDraft {
	t.Helper()
	m, err := core.LoadWorld("../../examples/world.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	plan, err := core.BuildPlan(m, command, version)
	if err != nil {
		t.Fatal(err)
	}
	return plan
}

func TestDispatchRequiresMatchingPlanIdentity(t *testing.T) {
	plan := testPlan(t, "pane.shell.send \"git status\" enter", 4)
	d := NewDefault()
	if _, err := d.Dispatch(Request{Plan: plan, PlanID: "wrong", PlanHash: plan.Hash, BufferVersion: 4}); err == nil {
		t.Fatalf("expected mismatched plan id to fail")
	}
	if _, err := d.Dispatch(Request{Plan: plan, PlanID: plan.ID, PlanHash: plan.Hash, BufferVersion: 4}); err != nil {
		t.Fatalf("expected dispatch to pass: %v", err)
	}
}

func TestShellExecAdapterActuallyRunsWithConfirm(t *testing.T) {
	plan := testPlan(t, "shell.exec \""+shellEchoCommand("hq-shell-ok")+"\" timeout=2s", 5)
	d := NewDefault()
	if _, err := d.Dispatch(Request{Plan: plan, PlanID: plan.ID, PlanHash: plan.Hash, BufferVersion: 5}); err == nil {
		t.Fatalf("expected shell plan to require confirmation")
	}
	receipt, err := d.Dispatch(Request{Plan: plan, PlanID: plan.ID, PlanHash: plan.Hash, BufferVersion: 5, Confirmed: true})
	if err != nil {
		t.Fatal(err)
	}
	if receipt.Adapter != "shell.exec" || !strings.Contains(receipt.Result["stdout"].(string), "hq-shell-ok") {
		t.Fatalf("unexpected shell receipt: %+v", receipt)
	}
}

func TestHTTPAdapterActuallyRequests(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/health" {
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusTeapot)
		_, _ = w.Write([]byte("hq-http-ok"))
	}))
	defer srv.Close()
	plan := testPlan(t, "http.get "+srv.URL+"/health save=health", 6)
	d := NewDefault()
	receipt, err := d.Dispatch(Request{Plan: plan, PlanID: plan.ID, PlanHash: plan.Hash, BufferVersion: 6})
	if err != nil {
		t.Fatal(err)
	}
	if !ReceiptHasStatus(receipt, http.StatusTeapot) || !strings.Contains(receipt.Result["body_preview"].(string), "hq-http-ok") {
		t.Fatalf("unexpected http receipt: %+v", receipt)
	}
}

func TestAdaptersCanBeCalledDirectly(t *testing.T) {
	plan := core.PlanDraft{Args: map[string]string{"command": shellEchoCommand("direct-shell-ok"), "timeout": "2s"}}
	got, err := ShellAdapter{}.Execute(context.Background(), plan)
	if err != nil || !strings.Contains(got["stdout"].(string), "direct-shell-ok") {
		t.Fatalf("shell adapter direct failed got=%v err=%v", got, err)
	}
}

func shellEchoCommand(text string) string {
	if runtime.GOOS == "windows" {
		return "echo " + text
	}
	return "printf " + text
}
