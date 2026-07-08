package rsc

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

type KeySpec struct {
	Key         string   `json:"key"`
	Type        string   `json:"type"`
	Required    bool     `json:"required"`
	Enum        []string `json:"enum,omitempty"`
	Ref         string   `json:"ref,omitempty"`
	Relation    string   `json:"relation,omitempty"`
	Description string   `json:"description,omitempty"`
}

type ObjectSchema struct {
	Object      string             `json:"object"`
	Description string             `json:"description,omitempty"`
	Keys        map[string]KeySpec `json:"keys"`
	Order       []string           `json:"order"`
}

type ObjectNode struct {
	ID     string            `json:"id"`
	Object string            `json:"object"`
	Fields map[string]string `json:"fields"`
}

type Relation struct {
	Parent string `json:"parent"`
	Child  string `json:"child"`
	Role   string `json:"role"`
	Index  int    `json:"index"`
}

type World struct {
	Digest     string                   `json:"digest"`
	Schemas    map[string]*ObjectSchema `json:"schemas"`
	Objects    map[string]ObjectNode    `json:"objects"`
	Relations  []Relation               `json:"relations"`
	Children   map[string][]Relation    `json:"children"`
	EventCount int                      `json:"event_count"`
}

func NewWorld() World {
	return World{Schemas: map[string]*ObjectSchema{}, Objects: map[string]ObjectNode{}, Children: map[string][]Relation{}}
}

func LoadWorld(path string) (World, error) {
	f, err := os.Open(path)
	if err != nil {
		return World{}, err
	}
	defer f.Close()

	w := NewWorld()
	h := sha256.New()
	s := bufio.NewScanner(f)
	lineNo := 0
	for s.Scan() {
		lineNo++
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		h.Write([]byte(line))
		h.Write([]byte("\n"))
		var ev map[string]any
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			return World{}, fmt.Errorf("%s:%d: %w", path, lineNo, err)
		}
		switch stringField(ev, "kind") {
		case "schema.object":
			obj := stringField(ev, "object")
			if obj == "" {
				return World{}, fmt.Errorf("%s:%d schema.object missing object", path, lineNo)
			}
			if _, ok := w.Schemas[obj]; !ok {
				w.Schemas[obj] = &ObjectSchema{Object: obj, Description: stringField(ev, "description"), Keys: map[string]KeySpec{}}
			}
		case "schema.key":
			obj := stringField(ev, "object")
			key := stringField(ev, "key")
			if obj == "" || key == "" {
				return World{}, fmt.Errorf("%s:%d schema.key missing object/key", path, lineNo)
			}
			if _, ok := w.Schemas[obj]; !ok {
				w.Schemas[obj] = &ObjectSchema{Object: obj, Keys: map[string]KeySpec{}}
			}
			ks := KeySpec{Key: key, Type: stringField(ev, "type"), Required: boolField(ev, "required"), Enum: stringSliceField(ev, "enum"), Ref: stringField(ev, "ref"), Relation: stringField(ev, "relation"), Description: stringField(ev, "description")}
			w.Schemas[obj].Keys[key] = ks
			w.Schemas[obj].Order = append(w.Schemas[obj].Order, key)
		case "object.upsert":
			id := stringField(ev, "id")
			obj := stringField(ev, "object")
			if id == "" || obj == "" {
				return World{}, fmt.Errorf("%s:%d object.upsert missing id/object", path, lineNo)
			}
			fields := map[string]string{}
			if raw, ok := ev["fields"].(map[string]any); ok {
				for k, v := range raw {
					fields[k] = fmt.Sprint(v)
				}
			}
			w.Objects[id] = ObjectNode{ID: id, Object: obj, Fields: fields}
		case "relation.add":
			rel := Relation{Parent: stringField(ev, "parent"), Child: stringField(ev, "child"), Role: stringField(ev, "role"), Index: intField(ev, "index")}
			if rel.Parent == "" || rel.Child == "" || rel.Role == "" {
				return World{}, fmt.Errorf("%s:%d relation.add missing parent/child/role", path, lineNo)
			}
			w.Relations = append(w.Relations, rel)
			w.Children[rel.Parent] = append(w.Children[rel.Parent], rel)
		default:
			return World{}, fmt.Errorf("%s:%d unknown kind %q", path, lineNo, stringField(ev, "kind"))
		}
		w.EventCount++
	}
	if err := s.Err(); err != nil {
		return World{}, err
	}
	for parent := range w.Children {
		sort.SliceStable(w.Children[parent], func(i, j int) bool { return w.Children[parent][i].Index < w.Children[parent][j].Index })
	}
	w.Digest = hex.EncodeToString(h.Sum(nil))
	return w, nil
}

func stringField(m map[string]any, key string) string { v, _ := m[key].(string); return v }
func boolField(m map[string]any, key string) bool     { v, _ := m[key].(bool); return v }
func intField(m map[string]any, key string) int {
	switch v := m[key].(type) {
	case float64:
		return int(v)
	case int:
		return v
	default:
		return 0
	}
}
func stringSliceField(m map[string]any, key string) []string {
	raw, ok := m[key].([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(raw))
	for _, v := range raw {
		out = append(out, fmt.Sprint(v))
	}
	return out
}
