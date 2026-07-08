package rsc

import "testing"

func loadTree(t *testing.T) World {
	t.Helper()
	w, err := LoadWorld("../../examples/tree_world.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	return w
}

func TestWorldReducesOneParentManyChildren(t *testing.T) {
	w := loadTree(t)
	rels := w.Children["project:hq"]
	if len(rels) != 3 {
		t.Fatalf("expected 3 project:hq children, got %d", len(rels))
	}
	for i, want := range []string{"task:t1", "task:t2", "task:t3"} {
		if rels[i].Child != want {
			t.Fatalf("child[%d]=%s want %s", i, rels[i].Child, want)
		}
	}
}

func TestObjectKeySlotSuggestsMissingSchemaKeys(t *testing.T) {
	w := loadTree(t)
	ctx := BuildContext(w, `{"kind":"project",`, len([]rune(`{"kind":"project",`)), 9)
	if ctx.Slot.Kind != "object.key" {
		t.Fatalf("slot=%s", ctx.Slot.Kind)
	}
	got := Suggest(w, ctx)
	assertHasSuggestion(t, got, "id")
	assertHasSuggestion(t, got, "name")
	assertHasSuggestion(t, got, "tasks")
	assertNoSuggestion(t, got, "kind")
	for _, s := range got {
		if s.CompileDraft.SideEffect {
			t.Fatalf("completion must be side-effect-free: %+v", s)
		}
		if s.CompileDraft.Kind == "" {
			t.Fatalf("missing compileDraft: %+v", s)
		}
	}
}

func TestArrayItemSlotSuggestsOneByManyRelationChildren(t *testing.T) {
	w := loadTree(t)
	buf := `{"kind":"project","tasks":[`
	ctx := BuildContext(w, buf, len([]rune(buf)), 11)
	if ctx.Slot.Kind != "array.item" {
		t.Fatalf("slot=%s context=%+v", ctx.Slot.Kind, ctx)
	}
	got := Suggest(w, ctx)
	assertHasSuggestion(t, got, "task:t1")
	assertHasSuggestion(t, got, "task:t2")
	assertHasSuggestion(t, got, "task:t3")
}

func TestValueSlotSuggestsEnumValues(t *testing.T) {
	w := loadTree(t)
	buf := `{"kind":"project","status":`
	ctx := BuildContext(w, buf, len([]rune(buf)), 12)
	if ctx.Slot.Kind != "object.value" {
		t.Fatalf("slot=%s context=%+v", ctx.Slot.Kind, ctx)
	}
	got := Suggest(w, ctx)
	assertHasSuggestion(t, got, "active")
	assertHasSuggestion(t, got, "paused")
	assertHasSuggestion(t, got, "archived")
}

func TestAcceptRequiresSuggestionIdentity(t *testing.T) {
	w := loadTree(t)
	buf := `{"kind":"project","tasks":[`
	ctx := BuildContext(w, buf, len([]rune(buf)), 13)
	got := Suggest(w, ctx)
	if len(got) == 0 {
		t.Fatal("no suggestions")
	}
	if _, err := Accept(Acceptance{Suggestion: got[0], SuggestionID: "wrong", SuggestionHash: got[0].Hash, BufferVersion: got[0].BufferVersion}); err == nil {
		t.Fatalf("expected id mismatch")
	}
	ins, err := Accept(Acceptance{Suggestion: got[0], SuggestionID: got[0].ID, SuggestionHash: got[0].Hash, BufferVersion: got[0].BufferVersion})
	if err != nil {
		t.Fatal(err)
	}
	if ins.CompileDraft.Operation != "append-ref" {
		t.Fatalf("operation=%s", ins.CompileDraft.Operation)
	}
}

func assertHasSuggestion(t *testing.T, got []Suggestion, label string) {
	t.Helper()
	for _, s := range got {
		if s.Label == label {
			return
		}
	}
	t.Fatalf("missing suggestion %q in %#v", label, got)
}

func assertNoSuggestion(t *testing.T, got []Suggestion, label string) {
	t.Helper()
	for _, s := range got {
		if s.Label == label {
			t.Fatalf("unexpected suggestion %q in %#v", label, got)
		}
	}
}
