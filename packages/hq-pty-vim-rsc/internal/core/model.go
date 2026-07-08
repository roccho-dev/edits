package core

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

type Adapter struct {
	Name        string `json:"name"`
	Safe        bool   `json:"safe"`
	Description string `json:"description,omitempty"`
}

type Target struct {
	Name        string `json:"name"`
	Adapter     string `json:"adapter"`
	Description string `json:"description,omitempty"`
}

type ContextRef struct {
	Ref         string `json:"ref"`
	Description string `json:"description,omitempty"`
}

type CommandTemplate struct {
	Label       string `json:"label"`
	Insert      string `json:"insert"`
	Adapter     string `json:"adapter"`
	Action      string `json:"action"`
	Description string `json:"description,omitempty"`
}

type Model struct {
	Digest     string                `json:"digest"`
	Adapters   map[string]Adapter    `json:"adapters"`
	Targets    map[string]Target     `json:"targets"`
	Contexts   map[string]ContextRef `json:"contexts"`
	Templates  []CommandTemplate     `json:"templates"`
	EventCount int                   `json:"event_count"`
}

func EmptyModel() Model {
	return Model{
		Adapters:  map[string]Adapter{},
		Targets:   map[string]Target{},
		Contexts:  map[string]ContextRef{},
		Templates: []CommandTemplate{},
	}
}

func LoadWorld(path string) (Model, error) {
	f, err := os.Open(path)
	if err != nil {
		return Model{}, err
	}
	defer f.Close()

	m := EmptyModel()
	h := sha256.New()
	scanner := bufio.NewScanner(f)
	lineNo := 0
	for scanner.Scan() {
		rawLine := strings.TrimSpace(scanner.Text())
		lineNo++
		if rawLine == "" || strings.HasPrefix(rawLine, "#") {
			continue
		}
		h.Write([]byte(rawLine))
		h.Write([]byte("\n"))
		var ev map[string]any
		if err := json.Unmarshal([]byte(rawLine), &ev); err != nil {
			return Model{}, fmt.Errorf("%s:%d: invalid jsonl: %w", path, lineNo, err)
		}
		kind, _ := ev["kind"].(string)
		switch kind {
		case "adapter.registered":
			name := stringField(ev, "adapter")
			if name == "" {
				return Model{}, fmt.Errorf("%s:%d: adapter.registered missing adapter", path, lineNo)
			}
			m.Adapters[name] = Adapter{Name: name, Safe: boolField(ev, "safe"), Description: stringField(ev, "description")}
		case "target.upsert":
			name := stringField(ev, "target")
			adapter := stringField(ev, "adapter")
			if name == "" || adapter == "" {
				return Model{}, fmt.Errorf("%s:%d: target.upsert missing target/adapter", path, lineNo)
			}
			m.Targets[name] = Target{Name: name, Adapter: adapter, Description: stringField(ev, "description")}
		case "context.ref":
			ref := stringField(ev, "ref")
			if ref == "" {
				return Model{}, fmt.Errorf("%s:%d: context.ref missing ref", path, lineNo)
			}
			m.Contexts[ref] = ContextRef{Ref: ref, Description: stringField(ev, "description")}
		case "command.template":
			tmpl := CommandTemplate{
				Label:       stringField(ev, "label"),
				Insert:      stringField(ev, "insert"),
				Adapter:     stringField(ev, "adapter"),
				Action:      stringField(ev, "action"),
				Description: stringField(ev, "description"),
			}
			if tmpl.Label == "" || tmpl.Insert == "" || tmpl.Adapter == "" || tmpl.Action == "" {
				return Model{}, fmt.Errorf("%s:%d: command.template missing label/insert/adapter/action", path, lineNo)
			}
			m.Templates = append(m.Templates, tmpl)
		default:
			return Model{}, fmt.Errorf("%s:%d: unknown event kind %q", path, lineNo, kind)
		}
		m.EventCount++
	}
	if err := scanner.Err(); err != nil {
		return Model{}, err
	}
	m.Digest = hex.EncodeToString(h.Sum(nil))
	sort.Slice(m.Templates, func(i, j int) bool { return m.Templates[i].Insert < m.Templates[j].Insert })
	return m, nil
}

func stringField(m map[string]any, key string) string {
	v, _ := m[key].(string)
	return v
}

func boolField(m map[string]any, key string) bool {
	v, _ := m[key].(bool)
	return v
}
