package launcher

import (
	"strings"
	"testing"
)

func TestExplorerTargetsAndPreviewAreSideEffectFree(t *testing.T) {
	home := `C:\Users\resta`
	got, err := Smoke(home)
	if err != nil {
		t.Fatal(err)
	}
	if !got.OK || !got.PreviewSideEffectFree || !got.RemoteMappingGuardOK {
		t.Fatalf("unexpected smoke: %+v", got)
	}
	labels := map[string]bool{}
	for _, t := range got.Targets {
		labels[t.Name] = true
	}
	for _, name := range []string{"home", "codex", "repos", "edits"} {
		if !labels[name] {
			t.Fatalf("missing target %s in %+v", name, got.Targets)
		}
	}
	foundSelect := false
	for _, plan := range got.Plans {
		if plan.SideEffect {
			t.Fatalf("preview had side effect: %+v", plan)
		}
		if plan.Executable != "explorer.exe" {
			t.Fatalf("unexpected executable: %+v", plan)
		}
		if plan.Mode == "select" && len(plan.Args) == 1 && strings.HasPrefix(plan.Args[0], "/select,") {
			foundSelect = true
		}
	}
	if !foundSelect {
		t.Fatalf("select preview missing: %+v", got.Plans)
	}
}

func TestRemotePathRequiresMapping(t *testing.T) {
	if _, err := PreviewOpen(Target{Name: "kite", Path: "ssh://kite/home/repo", Kind: "remote"}); err == nil {
		t.Fatalf("expected remote path to be rejected")
	}
}

func TestCompleteTargets(t *testing.T) {
	got := CompleteTargets(`C:\Users\resta`, "re")
	if len(got) != 1 || got[0].Name != "repos" {
		t.Fatalf("unexpected completion: %+v", got)
	}
}
