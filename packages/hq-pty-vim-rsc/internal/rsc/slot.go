package rsc

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
)

type TextEdit struct {
	Start int    `json:"start"`
	End   int    `json:"end"`
	Text  string `json:"text"`
}

type Slot struct {
	Kind      string   `json:"kind"`
	Object    string   `json:"object"`
	Path      []string `json:"path"`
	Partial   string   `json:"partial,omitempty"`
	SchemaRef string   `json:"schema_ref,omitempty"`
}

type CursorContext struct {
	Buffer         string          `json:"buffer"`
	Cursor         int             `json:"cursor"`
	Object         string          `json:"object"`
	RootID         string          `json:"root_id"`
	Slot           Slot            `json:"slot"`
	ExistingKeys   []string        `json:"existing_keys"`
	ExistingKeySet map[string]bool `json:"-"`
	BufferVersion  int             `json:"buffer_version"`
	WorldDigest    string          `json:"world_digest"`
}

type CompileDraft struct {
	Kind       string         `json:"kind"`
	Operation  string         `json:"operation"`
	Object     string         `json:"object"`
	Path       []string       `json:"path"`
	Value      string         `json:"value,omitempty"`
	Ref        string         `json:"ref,omitempty"`
	SideEffect bool           `json:"side_effect"`
	Body       map[string]any `json:"body,omitempty"`
}

type Suggestion struct {
	ID            string       `json:"id"`
	Hash          string       `json:"hash"`
	Label         string       `json:"label"`
	Detail        string       `json:"detail,omitempty"`
	Kind          string       `json:"kind"`
	Edit          TextEdit     `json:"edit"`
	Meaning       string       `json:"meaning"`
	NextSlot      *Slot        `json:"next_slot,omitempty"`
	CompileDraft  CompileDraft `json:"compile_draft"`
	WorldDigest   string       `json:"world_digest"`
	BufferVersion int          `json:"buffer_version"`
}

type Acceptance struct {
	Suggestion     Suggestion `json:"suggestion"`
	SuggestionID   string     `json:"suggestion_id"`
	SuggestionHash string     `json:"suggestion_hash"`
	BufferVersion  int        `json:"buffer_version"`
}

type Instruction struct {
	Kind           string       `json:"kind"`
	InstructionID  string       `json:"instruction_id"`
	SuggestionID   string       `json:"suggestion_id"`
	SuggestionHash string       `json:"suggestion_hash"`
	BufferVersion  int          `json:"buffer_version"`
	CompileDraft   CompileDraft `json:"compile_draft"`
	WorldDigest    string       `json:"world_digest"`
}

func BuildContext(w World, buffer string, cursor int, version int) CursorContext {
	if cursor < 0 || cursor > len([]rune(buffer)) {
		cursor = len([]rune(buffer))
	}
	prefix := string([]rune(buffer)[:cursor])
	object := inferObject(prefix)
	if object == "" {
		object = "project"
	}
	root := inferRootID(prefix, object)
	existing := existingKeys(prefix)
	keySet := map[string]bool{}
	for _, k := range existing {
		keySet[k] = true
	}
	slot := classifySlot(prefix, object)
	return CursorContext{Buffer: buffer, Cursor: cursor, Object: object, RootID: root, Slot: slot, ExistingKeys: existing, ExistingKeySet: keySet, BufferVersion: version, WorldDigest: w.Digest}
}

func Suggest(w World, ctx CursorContext) []Suggestion {
	switch ctx.Slot.Kind {
	case "object.key":
		return suggestKeys(w, ctx)
	case "object.value":
		return suggestValues(w, ctx)
	case "array.item":
		return suggestArrayItems(w, ctx)
	default:
		return nil
	}
}

func Accept(a Acceptance) (Instruction, error) {
	if err := ValidateSuggestion(a.Suggestion); err != nil {
		return Instruction{}, err
	}
	if a.SuggestionID != a.Suggestion.ID {
		return Instruction{}, fmt.Errorf("suggestion id mismatch: got %s want %s", a.SuggestionID, a.Suggestion.ID)
	}
	if a.SuggestionHash != a.Suggestion.Hash {
		return Instruction{}, fmt.Errorf("suggestion hash mismatch: got %s want %s", a.SuggestionHash, a.Suggestion.Hash)
	}
	if a.BufferVersion != a.Suggestion.BufferVersion {
		return Instruction{}, fmt.Errorf("buffer version mismatch: got %d want %d", a.BufferVersion, a.Suggestion.BufferVersion)
	}
	if a.Suggestion.CompileDraft.SideEffect {
		return Instruction{}, fmt.Errorf("completion compileDraft must be side_effect=false")
	}
	id := hashString(a.Suggestion.ID + ":" + a.Suggestion.Hash + ":" + fmt.Sprint(a.BufferVersion))
	return Instruction{Kind: "instruction.accepted", InstructionID: "ins_" + id[:12], SuggestionID: a.Suggestion.ID, SuggestionHash: a.Suggestion.Hash, BufferVersion: a.BufferVersion, CompileDraft: a.Suggestion.CompileDraft, WorldDigest: a.Suggestion.WorldDigest}, nil
}

func ValidateSuggestion(s Suggestion) error {
	expected := suggestionHash(s)
	if s.Hash != expected {
		return fmt.Errorf("suggestion hash invalid: got %s want %s", s.Hash, expected)
	}
	if s.ID != "sug_"+expected[:12] {
		return fmt.Errorf("suggestion id invalid: got %s want %s", s.ID, "sug_"+expected[:12])
	}
	if s.CompileDraft.SideEffect {
		return fmt.Errorf("completion compileDraft must be side_effect=false")
	}
	return nil
}

func suggestKeys(w World, ctx CursorContext) []Suggestion {
	schema := w.Schemas[ctx.Object]
	if schema == nil {
		return nil
	}
	keys := append([]string(nil), schema.Order...)
	sort.SliceStable(keys, func(i, j int) bool {
		ki, kj := schema.Keys[keys[i]], schema.Keys[keys[j]]
		if ki.Required != kj.Required {
			return ki.Required
		}
		return keys[i] < keys[j]
	})
	var out []Suggestion
	for _, key := range keys {
		ks := schema.Keys[key]
		if ctx.ExistingKeySet[key] {
			continue
		}
		if ctx.Slot.Partial != "" && !strings.HasPrefix(key, ctx.Slot.Partial) {
			continue
		}
		insert := fmt.Sprintf("\"%s\": ", key)
		next := Slot{Kind: "object.value", Object: ctx.Object, Path: []string{key}, SchemaRef: ctx.Object + "." + key}
		if strings.HasPrefix(ks.Type, "array") {
			insert = fmt.Sprintf("\"%s\": [", key)
			next = Slot{Kind: "array.item", Object: ctx.Object, Path: []string{key}, SchemaRef: ctx.Object + "." + key}
		}
		out = append(out, mkSuggestion(ctx, key, "json.key", insert, ks.Description, "add key "+key+" to "+ctx.Object, &next, CompileDraft{Kind: "jsonl.patch", Operation: "add-key", Object: ctx.Object, Path: []string{key}, SideEffect: false, Body: map[string]any{"key": key, "required": ks.Required}}))
	}
	return out
}

func suggestValues(w World, ctx CursorContext) []Suggestion {
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
	var values []string
	if len(ks.Enum) > 0 {
		values = append(values, ks.Enum...)
	}
	if ks.Type == "string" {
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
	var out []Suggestion
	for _, v := range values {
		if ctx.Slot.Partial != "" && !strings.HasPrefix(v, ctx.Slot.Partial) {
			continue
		}
		text := jsonString(v)
		out = append(out, mkSuggestion(ctx, v, "json.value", text, ks.Description, "set "+key+" value to "+v, nil, CompileDraft{Kind: "jsonl.patch", Operation: "set-value", Object: ctx.Object, Path: []string{key}, Value: v, SideEffect: false, Body: map[string]any{"key": key, "value": v}}))
	}
	return out
}

func suggestArrayItems(w World, ctx CursorContext) []Suggestion {
	if len(ctx.Slot.Path) == 0 {
		return nil
	}
	key := ctx.Slot.Path[len(ctx.Slot.Path)-1]
	schema := w.Schemas[ctx.Object]
	if schema == nil {
		return nil
	}
	ks, ok := schema.Keys[key]
	if !ok || !strings.HasPrefix(ks.Type, "array:ref") {
		return nil
	}
	root := ctx.RootID
	if root == "" {
		root = firstObjectID(w, ctx.Object)
	}
	rels := w.Children[root]
	var out []Suggestion
	for _, rel := range rels {
		if rel.Role != key {
			continue
		}
		child, ok := w.Objects[rel.Child]
		if !ok || child.Object != ks.Ref {
			continue
		}
		title := child.Fields["title"]
		detail := title
		if detail == "" {
			detail = child.ID
		}
		text := jsonString(child.ID)
		out = append(out, mkSuggestion(ctx, child.ID, "json.ref", text, detail, "append child ref "+child.ID+" to "+root+"."+key, nil, CompileDraft{Kind: "jsonl.patch", Operation: "append-ref", Object: ctx.Object, Path: []string{key}, Ref: child.ID, SideEffect: false, Body: map[string]any{"parent": root, "role": key, "child": child.ID}}))
	}
	return out
}

func mkSuggestion(ctx CursorContext, label, kind, editText, detail, meaning string, next *Slot, draft CompileDraft) Suggestion {
	s := Suggestion{Label: label, Detail: detail, Kind: kind, Edit: TextEdit{Start: ctx.Cursor - len([]rune(ctx.Slot.Partial)), End: ctx.Cursor, Text: editText}, Meaning: meaning, NextSlot: next, CompileDraft: draft, WorldDigest: ctx.WorldDigest, BufferVersion: ctx.BufferVersion}
	s.Hash = suggestionHash(s)
	s.ID = "sug_" + s.Hash[:12]
	return s
}

func suggestionHash(s Suggestion) string {
	payload := struct {
		Label, Kind   string
		Edit          TextEdit
		Meaning       string
		NextSlot      *Slot
		CompileDraft  CompileDraft
		WorldDigest   string
		BufferVersion int
	}{s.Label, s.Kind, s.Edit, s.Meaning, s.NextSlot, s.CompileDraft, s.WorldDigest, s.BufferVersion}
	b, _ := json.Marshal(payload)
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func hashString(s string) string { sum := sha256.Sum256([]byte(s)); return hex.EncodeToString(sum[:]) }
func jsonString(s string) string { b, _ := json.Marshal(s); return string(b) }

var reKind = regexp.MustCompile(`"kind"\s*:\s*"([^"]*)"`)
var reID = regexp.MustCompile(`"id"\s*:\s*"([^"]*)"`)
var reKeys = regexp.MustCompile(`"([A-Za-z0-9_-]+)"\s*:`)
var reLastKeyBeforeColon = regexp.MustCompile(`"([A-Za-z0-9_-]+)"\s*:\s*$`)
var reLastArrayKey = regexp.MustCompile(`"([A-Za-z0-9_-]+)"\s*:\s*\[\s*$`)
var reOpenKeyString = regexp.MustCompile(`(?:^|[\{,])\s*"([A-Za-z0-9_-]*)$`)
var reOpenValueString = regexp.MustCompile(`"([A-Za-z0-9_-]+)"\s*:\s*"([^"]*)$`)

func inferObject(prefix string) string {
	m := reKind.FindStringSubmatch(prefix)
	if len(m) == 2 {
		return m[1]
	}
	return ""
}

func inferRootID(prefix, object string) string {
	m := reID.FindStringSubmatch(prefix)
	if len(m) == 2 {
		return object + ":" + m[1]
	}
	if object == "project" {
		return "project:hq"
	}
	return ""
}

func existingKeys(prefix string) []string {
	matches := reKeys.FindAllStringSubmatch(prefix, -1)
	seen := map[string]bool{}
	var out []string
	for _, m := range matches {
		if len(m) == 2 && !seen[m[1]] {
			seen[m[1]] = true
			out = append(out, m[1])
		}
	}
	return out
}

func classifySlot(prefix, object string) Slot {
	trim := strings.TrimSpace(prefix)
	if m := reLastArrayKey.FindStringSubmatch(trim); len(m) == 2 {
		return Slot{Kind: "array.item", Object: object, Path: []string{m[1]}, SchemaRef: object + "." + m[1]}
	}
	if m := reOpenValueString.FindStringSubmatch(trim); len(m) == 3 {
		return Slot{Kind: "object.value", Object: object, Path: []string{m[1]}, Partial: m[2], SchemaRef: object + "." + m[1]}
	}
	if m := reLastKeyBeforeColon.FindStringSubmatch(trim); len(m) == 2 {
		return Slot{Kind: "object.value", Object: object, Path: []string{m[1]}, SchemaRef: object + "." + m[1]}
	}
	if m := reOpenKeyString.FindStringSubmatch(trim); len(m) == 2 {
		return Slot{Kind: "object.key", Object: object, Partial: m[1], SchemaRef: object}
	}
	if strings.HasSuffix(trim, "{") || strings.HasSuffix(trim, ",") || trim == "" {
		return Slot{Kind: "object.key", Object: object, SchemaRef: object}
	}
	return Slot{Kind: "unknown", Object: object, SchemaRef: object}
}

func firstObjectID(w World, object string) string {
	ids := make([]string, 0, len(w.Objects))
	for id, obj := range w.Objects {
		if obj.Object == object {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	if len(ids) == 0 {
		return ""
	}
	return ids[0]
}
