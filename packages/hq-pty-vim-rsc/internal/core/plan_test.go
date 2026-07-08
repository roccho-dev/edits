package core

import "testing"

func testModel(t *testing.T) Model {
	t.Helper()
	m, err := LoadWorld("../../examples/world.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestCompletionReturnsPlanDraftWithoutSideEffect(t *testing.T) {
	m := testModel(t)
	got := Complete(m, CursorContext{Line: "pane.shell.", Prefix: "pane.shell.", BufferVersion: 7})
	if len(got) == 0 {
		t.Fatalf("expected suggestions")
	}
	found := false
	for _, s := range got {
		if s.PlanDraft.SideEffect {
			t.Fatalf("completion must not create side effects: %+v", s.PlanDraft)
		}
		if s.PlanDraft.ID == "" || s.PlanDraft.Hash == "" {
			t.Fatalf("plan identity missing: %+v", s.PlanDraft)
		}
		if s.EditText == "pane.shell.send \"git status\" enter" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected git status pane send suggestion, got %#v", got)
	}
}

func TestPlanHashDetectsMutation(t *testing.T) {
	m := testModel(t)
	plan, err := BuildPlan(m, "pane.shell.send \"git status\" enter", 3)
	if err != nil {
		t.Fatal(err)
	}
	if err := ValidatePlan(plan); err != nil {
		t.Fatal(err)
	}
	plan.CommandText = "pane.shell.send \"rm -rf /\" enter"
	if err := ValidatePlan(plan); err == nil {
		t.Fatalf("expected hash mismatch after mutation")
	}
}

func TestHTTPAndShellPlans(t *testing.T) {
	m := testModel(t)
	httpPlan, err := BuildPlan(m, "http.get http://127.0.0.1:18080/health save=health", 2)
	if err != nil {
		t.Fatal(err)
	}
	if httpPlan.Adapter != "http.request" || httpPlan.RequiresConfirm {
		t.Fatalf("unexpected http plan: %+v", httpPlan)
	}
	shellPlan, err := BuildPlan(m, "shell.exec \"printf hq-shell-ok\" timeout=2s", 2)
	if err != nil {
		t.Fatal(err)
	}
	if shellPlan.Adapter != "shell.exec" || !shellPlan.RequiresConfirm {
		t.Fatalf("shell plan must be confirmed shell adapter: %+v", shellPlan)
	}
}

func TestDiagnosticsRejectUnknownCommand(t *testing.T) {
	m := testModel(t)
	got := Diagnose(m, "pane.ghost.send \"git status\" enter", 1)
	if len(got) == 0 {
		t.Fatalf("expected diagnostic")
	}
}
