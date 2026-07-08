package rsc

import "testing"

func TestLooseStringIntakeNormalizesToDraftObject(t *testing.T) {
	w := loadTree(t)
	res := Intake(w, "project hq tasks ", 21)
	if res.Surface != "loose-string" {
		t.Fatalf("surface=%s", res.Surface)
	}
	if res.Draft.Kind != "project.patch" || res.Draft.RootID != "project:hq" || res.Draft.Operation != "append-ref" {
		t.Fatalf("bad draft: %+v", res.Draft)
	}
	if !res.Draft.Partial || !stringIn("ref", res.Draft.Missing) {
		t.Fatalf("expected missing ref: %+v", res.Draft)
	}
	if res.Context.Slot.Kind != "draft.ref" {
		t.Fatalf("slot=%s ctx=%+v", res.Context.Slot.Kind, res.Context)
	}
	assertHasSuggestion(t, res.Suggestions, "task:t1")
	assertHasSuggestion(t, res.Suggestions, "task:t2")
	assertHasSuggestion(t, res.Suggestions, "task:t3")
	for _, s := range res.Suggestions {
		if s.CompileDraft.SideEffect {
			t.Fatalf("intake suggestions must be side-effect-free: %+v", s)
		}
		if s.CompileDraft.Kind == "" || s.Meaning == "" {
			t.Fatalf("suggestion must carry meaning and compileDraft: %+v", s)
		}
	}
}

func TestDraftValidationIsSoftThenStrict(t *testing.T) {
	w := loadTree(t)
	partial := Intake(w, "project hq tasks ", 22).Draft
	soft := ValidateDraft(w, partial, "soft")
	if HasBlockingValidation(soft) {
		t.Fatalf("soft validation should guide, not block: %+v", soft)
	}
	strict := ValidateDraft(w, partial, "strict")
	if !HasBlockingValidation(strict) {
		t.Fatalf("strict validation should block missing ref: %+v", strict)
	}
	complete := Intake(w, "project hq tasks task:t1", 23).Draft
	if issues := ValidateDraft(w, complete, "strict"); HasBlockingValidation(issues) {
		t.Fatalf("complete draft should pass strict validation: %+v draft=%+v", issues, complete)
	}
}

func TestLooseStringAcceptanceStillRequiresSuggestionIdentity(t *testing.T) {
	w := loadTree(t)
	res := Intake(w, "project hq tasks ", 24)
	if len(res.Suggestions) == 0 {
		t.Fatal("no suggestions")
	}
	s := res.Suggestions[0]
	if _, err := Accept(Acceptance{Suggestion: s, SuggestionID: s.ID, SuggestionHash: "bad", BufferVersion: s.BufferVersion}); err == nil {
		t.Fatal("expected acceptance hash mismatch")
	}
	mutated := s
	mutated.CompileDraft.Ref = "task:t2"
	if _, err := Accept(Acceptance{Suggestion: mutated, SuggestionID: mutated.ID, SuggestionHash: mutated.Hash, BufferVersion: mutated.BufferVersion}); err == nil {
		t.Fatal("expected canonical suggestion hash validation to reject mutated body")
	}
	ins, err := Accept(Acceptance{Suggestion: s, SuggestionID: s.ID, SuggestionHash: s.Hash, BufferVersion: s.BufferVersion})
	if err != nil {
		t.Fatal(err)
	}
	if ins.CompileDraft.Operation != "append-ref" || ins.CompileDraft.Ref != "task:t1" {
		t.Fatalf("bad instruction: %+v", ins)
	}
}

func TestLooseStringEnumValueCompletion(t *testing.T) {
	w := loadTree(t)
	res := Intake(w, "project hq status ", 25)
	if res.Context.Slot.Kind != "draft.value" {
		t.Fatalf("slot=%s ctx=%+v", res.Context.Slot.Kind, res.Context)
	}
	assertHasSuggestion(t, res.Suggestions, "active")
	assertHasSuggestion(t, res.Suggestions, "paused")
	assertHasSuggestion(t, res.Suggestions, "archived")
}
