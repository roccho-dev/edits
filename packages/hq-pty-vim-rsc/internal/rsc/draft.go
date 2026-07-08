package rsc

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

type DraftObject struct {
	Kind          string   `json:"kind"`
	Raw           string   `json:"raw"`
	Surface       string   `json:"surface"`
	Object        string   `json:"object"`
	RootID        string   `json:"root_id,omitempty"`
	Operation     string   `json:"operation,omitempty"`
	Path          []string `json:"path,omitempty"`
	Value         string   `json:"value,omitempty"`
	Ref           string   `json:"ref,omitempty"`
	Partial       bool     `json:"partial"`
	Missing       []string `json:"missing,omitempty"`
	SideEffect    bool     `json:"side_effect"`
	WorldDigest   string   `json:"world_digest"`
	BufferVersion int      `json:"buffer_version"`
}

type ValidationIssue struct {
	Phase    string `json:"phase"`
	Severity string `json:"severity"`
	Code     string `json:"code"`
	Field    string `json:"field,omitempty"`
	Message  string `json:"message"`
}

type IntakeResult struct {
	Input       string            `json:"input"`
	Surface     string            `json:"surface"`
	Draft       DraftObject       `json:"draft"`
	Context     CursorContext     `json:"context"`
	Validation  []ValidationIssue `json:"validation"`
	Suggestions []Suggestion      `json:"suggestions"`
}

func Intake(w World, input string, version int) IntakeResult {
	trim := strings.TrimSpace(input)
	if strings.HasPrefix(trim, "{") || trim == "" {
		ctx := BuildContext(w, input, len([]rune(input)), version)
		draft := DraftObject{Kind: "json.partial", Raw: input, Surface: "json", Object: ctx.Object, RootID: ctx.RootID, Operation: slotOperation(ctx.Slot), Path: ctx.Slot.Path, Partial: true, SideEffect: false, WorldDigest: w.Digest, BufferVersion: version}
		draft.Missing = missingSlots(draft)
		return IntakeResult{Input: input, Surface: "json", Draft: draft, Context: ctx, Validation: ValidateDraft(w, draft, "soft"), Suggestions: Suggest(w, ctx)}
	}

	draft, ctx := parseLooseDraft(w, input, version)
	return IntakeResult{Input: input, Surface: "loose-string", Draft: draft, Context: ctx, Validation: ValidateDraft(w, draft, "soft"), Suggestions: SuggestDraft(w, ctx, draft)}
}

func ValidateDraft(w World, d DraftObject, phase string) []ValidationIssue {
	strict := phase == "strict" || phase == "dispatch"
	mk := func(sev, code, field, msg string) ValidationIssue {
		return ValidationIssue{Phase: phase, Severity: sev, Code: code, Field: field, Message: msg}
	}
	missingSeverity := "info"
	if strict {
		missingSeverity = "error"
	}
	var out []ValidationIssue
	if d.Object == "" {
		out = append(out, mk("error", "missing-object", "object", "object kind is missing"))
		return out
	}
	schema := w.Schemas[d.Object]
	if schema == nil {
		out = append(out, mk("error", "unknown-object", "object", "object schema not found: "+d.Object))
		return out
	}
	if d.RootID == "" {
		out = append(out, mk(missingSeverity, "missing-slot", "root_id", "root object is not selected yet"))
	} else if obj, ok := w.Objects[d.RootID]; !ok {
		sev := "warning"
		if strict {
			sev = "error"
		}
		out = append(out, mk(sev, "unknown-root", "root_id", "root object not found: "+d.RootID))
	} else if obj.Object != d.Object {
		out = append(out, mk("error", "root-object-mismatch", "root_id", fmt.Sprintf("%s is %s, not %s", d.RootID, obj.Object, d.Object)))
	}
	if len(d.Path) == 0 {
		out = append(out, mk(missingSeverity, "missing-slot", "path", "field/role slot is not selected yet"))
		return out
	}
	key := d.Path[len(d.Path)-1]
	ks, ok := schema.Keys[key]
	if !ok {
		out = append(out, mk("error", "unknown-field", "path", "field is not in schema: "+key))
		return out
	}
	if strings.HasPrefix(ks.Type, "array:ref") {
		if d.Operation == "" || d.Operation == "set-value" {
			d.Operation = "append-ref"
		}
		if d.Ref == "" {
			out = append(out, mk(missingSeverity, "missing-slot", "ref", "reference value is not selected yet"))
		} else if obj, ok := w.Objects[d.Ref]; !ok {
			sev := "warning"
			if strict {
				sev = "error"
			}
			out = append(out, mk(sev, "unknown-ref", "ref", "referenced object not found: "+d.Ref))
		} else if obj.Object != ks.Ref {
			out = append(out, mk("error", "ref-object-mismatch", "ref", fmt.Sprintf("%s is %s, not %s", d.Ref, obj.Object, ks.Ref)))
		}
	} else {
		if d.Operation == "" || d.Operation == "append-ref" {
			d.Operation = "set-value"
		}
		if d.Value == "" {
			out = append(out, mk(missingSeverity, "missing-slot", "value", "value slot is not filled yet"))
		} else if len(ks.Enum) > 0 && !stringIn(d.Value, ks.Enum) {
			out = append(out, mk("error", "enum-mismatch", "value", fmt.Sprintf("%q is not allowed for %s", d.Value, key)))
		}
	}
	if d.SideEffect {
		out = append(out, mk("error", "side-effect-in-draft", "side_effect", "draft/intake phase must not have side effects"))
	}
	return out
}

func HasBlockingValidation(issues []ValidationIssue) bool {
	for _, issue := range issues {
		if issue.Severity == "error" {
			return true
		}
	}
	return false
}

func SuggestDraft(w World, ctx CursorContext, d DraftObject) []Suggestion {
	if ctx.Slot.Kind == "draft.path" {
		return suggestDraftPaths(w, ctx)
	}
	if ctx.Slot.Kind == "draft.value" || ctx.Slot.Kind == "draft.ref" {
		return suggestDraftValues(w, ctx, d)
	}
	return nil
}

func parseLooseDraft(w World, input string, version int) (DraftObject, CursorContext) {
	tokens := strings.Fields(input)
	endsWithSpace := len(input) > 0 && (input[len(input)-1] == ' ' || input[len(input)-1] == '\t')
	object := ""
	rootID := ""
	path := []string{}
	value := ""
	ref := ""
	partial := ""
	operation := ""

	if len(tokens) >= 1 {
		object = normalizeObjectToken(tokens[0])
	}
	if object == "" {
		object = "project"
	}
	if len(tokens) >= 2 {
		rootID = normalizeObjectID(object, tokens[1])
	}
	if len(tokens) >= 3 {
		path = []string{tokens[2]}
		if keySpecIsArrayRef(w, object, tokens[2]) {
			operation = "append-ref"
		} else {
			operation = "set-value"
		}
	}
	if len(tokens) >= 4 {
		key := path[len(path)-1]
		if keySpecIsArrayRef(w, object, key) {
			ref = normalizeRefToken(w, object, key, tokens[3])
			operation = "append-ref"
		} else {
			value = tokens[3]
			operation = "set-value"
		}
	}

	missing := []string{}
	if len(tokens) == 1 && !endsWithSpace {
		partial = tokens[0]
	} else if len(tokens) == 2 && !endsWithSpace {
		partial = tokens[1]
	} else if len(tokens) == 3 && !endsWithSpace {
		partial = tokens[2]
	} else if len(tokens) >= 4 && !endsWithSpace {
		partial = tokens[len(tokens)-1]
	}
	if rootID == "" {
		missing = append(missing, "root_id")
	}
	if len(path) == 0 {
		missing = append(missing, "path")
	}
	if len(path) > 0 {
		key := path[len(path)-1]
		if keySpecIsArrayRef(w, object, key) {
			if ref == "" {
				missing = append(missing, "ref")
			}
		} else if value == "" {
			missing = append(missing, "value")
		}
	}

	slotKind := "draft.path"
	slotPath := path
	if rootID == "" {
		slotKind = "draft.root"
	} else if len(path) == 0 || (len(tokens) == 3 && !endsWithSpace) {
		slotKind = "draft.path"
	} else if len(path) > 0 {
		if keySpecIsArrayRef(w, object, path[len(path)-1]) {
			slotKind = "draft.ref"
		} else {
			slotKind = "draft.value"
		}
	}
	ctx := CursorContext{Buffer: input, Cursor: len([]rune(input)), Object: object, RootID: rootID, Slot: Slot{Kind: slotKind, Object: object, Path: slotPath, Partial: partial, SchemaRef: strings.Join(append([]string{object}, slotPath...), ".")}, BufferVersion: version, WorldDigest: w.Digest}
	d := DraftObject{Kind: object + ".patch", Raw: input, Surface: "loose-string", Object: object, RootID: rootID, Operation: operation, Path: path, Value: value, Ref: ref, Partial: len(missing) > 0, Missing: missing, SideEffect: false, WorldDigest: w.Digest, BufferVersion: version}
	return d, ctx
}

func suggestDraftPaths(w World, ctx CursorContext) []Suggestion {
	schema := w.Schemas[ctx.Object]
	if schema == nil {
		return nil
	}
	keys := append([]string(nil), schema.Order...)
	sort.Strings(keys)
	var out []Suggestion
	for _, key := range keys {
		ks := schema.Keys[key]
		if key == "kind" || key == "id" {
			continue
		}
		if ctx.Slot.Partial != "" && !strings.HasPrefix(key, ctx.Slot.Partial) {
			continue
		}
		nextKind := "draft.value"
		op := "set-value"
		if strings.HasPrefix(ks.Type, "array:ref") {
			nextKind = "draft.ref"
			op = "append-ref"
		}
		next := Slot{Kind: nextKind, Object: ctx.Object, Path: []string{key}, SchemaRef: ctx.Object + "." + key}
		draft := CompileDraft{Kind: "draft.patch", Operation: op, Object: ctx.Object, Path: []string{key}, SideEffect: false, Body: map[string]any{"surface": "loose-string", "root": ctx.RootID, "field": key}}
		out = append(out, mkSuggestion(ctx, key, "draft.path", key+" ", ks.Description, "select field/role "+key, &next, draft))
	}
	return out
}

func suggestDraftValues(w World, ctx CursorContext, d DraftObject) []Suggestion {
	if len(ctx.Slot.Path) == 0 {
		return nil
	}
	key := ctx.Slot.Path[len(ctx.Slot.Path)-1]
	schema := w.Schemas[ctx.Object]
	if schema == nil {
		return nil
	}
	ks, ok := schema.Keys[key]
	if !ok {
		return nil
	}
	var out []Suggestion
	if strings.HasPrefix(ks.Type, "array:ref") {
		candidates := relationCandidates(w, d.RootID, key, ks.Ref)
		for _, obj := range candidates {
			if ctx.Slot.Partial != "" && !strings.HasPrefix(obj.ID, ctx.Slot.Partial) {
				continue
			}
			detail := obj.Fields["title"]
			if detail == "" {
				detail = obj.ID
			}
			draft := CompileDraft{Kind: "jsonl.patch", Operation: "append-ref", Object: ctx.Object, Path: []string{key}, Ref: obj.ID, SideEffect: false, Body: map[string]any{"parent": d.RootID, "role": key, "child": obj.ID, "source": "loose-string"}}
			out = append(out, mkSuggestion(ctx, obj.ID, "draft.ref", obj.ID, detail, "append child ref "+obj.ID+" to "+d.RootID+"."+key, nil, draft))
		}
		return out
	}
	values := append([]string(nil), ks.Enum...)
	if len(values) == 0 && ks.Type == "string" {
		seen := map[string]bool{}
		for _, obj := range w.Objects {
			if obj.Object != ctx.Object {
				continue
			}
			v := obj.Fields[key]
			if v != "" && !seen[v] {
				seen[v] = true
				values = append(values, v)
			}
		}
	}
	for _, v := range values {
		if ctx.Slot.Partial != "" && !strings.HasPrefix(v, ctx.Slot.Partial) {
			continue
		}
		draft := CompileDraft{Kind: "jsonl.patch", Operation: "set-value", Object: ctx.Object, Path: []string{key}, Value: v, SideEffect: false, Body: map[string]any{"root": d.RootID, "field": key, "value": v, "source": "loose-string"}}
		out = append(out, mkSuggestion(ctx, v, "draft.value", v, ks.Description, "set "+key+" to "+v, nil, draft))
	}
	return out
}

func normalizeObjectToken(tok string) string {
	tok = strings.TrimSpace(tok)
	tok = strings.TrimSuffix(tok, ":")
	return tok
}

func normalizeObjectID(object, tok string) string {
	tok = strings.TrimSpace(tok)
	if tok == "" {
		return ""
	}
	if strings.Contains(tok, ":") {
		return tok
	}
	return object + ":" + tok
}

func normalizeRefToken(w World, object, key, tok string) string {
	if strings.Contains(tok, ":") {
		return tok
	}
	if schema := w.Schemas[object]; schema != nil {
		if ks, ok := schema.Keys[key]; ok && ks.Ref != "" {
			return ks.Ref + ":" + tok
		}
	}
	return tok
}

func keySpecIsArrayRef(w World, object, key string) bool {
	if schema := w.Schemas[object]; schema != nil {
		if ks, ok := schema.Keys[key]; ok {
			return strings.HasPrefix(ks.Type, "array:ref")
		}
	}
	return false
}

func relationCandidates(w World, rootID, role, refObject string) []ObjectNode {
	seen := map[string]bool{}
	var out []ObjectNode
	if rootID != "" {
		for _, rel := range w.Children[rootID] {
			if rel.Role != role || seen[rel.Child] {
				continue
			}
			if obj, ok := w.Objects[rel.Child]; ok && obj.Object == refObject {
				out = append(out, obj)
				seen[obj.ID] = true
			}
		}
	}
	if len(out) == 0 {
		ids := make([]string, 0, len(w.Objects))
		for id, obj := range w.Objects {
			if obj.Object == refObject {
				ids = append(ids, id)
			}
		}
		sort.Strings(ids)
		for _, id := range ids {
			out = append(out, w.Objects[id])
		}
	}
	return out
}

func slotOperation(s Slot) string {
	if s.Kind == "array.item" {
		return "append-ref"
	}
	if s.Kind == "object.value" {
		return "set-value"
	}
	if s.Kind == "object.key" {
		return "add-key"
	}
	return ""
}

func missingSlots(d DraftObject) []string {
	var out []string
	if d.RootID == "" {
		out = append(out, "root_id")
	}
	if len(d.Path) == 0 {
		out = append(out, "path")
	}
	if d.Operation == "append-ref" && d.Ref == "" {
		out = append(out, "ref")
	}
	if d.Operation == "set-value" && d.Value == "" {
		out = append(out, "value")
	}
	return out
}

func stringIn(s string, xs []string) bool {
	for _, x := range xs {
		if s == x {
			return true
		}
	}
	return false
}

func StrictDraftFromJSON(data []byte) (DraftObject, error) {
	var d DraftObject
	if err := json.Unmarshal(data, &d); err != nil {
		return DraftObject{}, err
	}
	return d, nil
}
