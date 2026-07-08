package lsp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"hq/internal/core"
	"hq/internal/jsonrpc"
)

type Server struct {
	Model core.Model
	docs  map[string]document
}

type document struct {
	Text    string
	Version int
}

func New(model core.Model) *Server {
	return &Server{Model: model, docs: map[string]document{}}
}

func (s *Server) Serve(r io.Reader, w io.Writer) error {
	br := bufio.NewReader(r)
	for {
		msg, err := jsonrpc.ReadMessage(br)
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if msg.Method == "exit" {
			return nil
		}
		responses, err := s.Handle(msg)
		if err != nil {
			responses = []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Error: &jsonrpc.Error{Code: -32603, Message: err.Error()}}}
		}
		for _, res := range responses {
			if len(res.ID) == 0 && res.Method == "" {
				continue
			}
			if err := jsonrpc.WriteMessage(w, res); err != nil {
				return err
			}
		}
	}
}

func (s *Server) Handle(msg jsonrpc.Message) ([]jsonrpc.Message, error) {
	switch msg.Method {
	case "initialize":
		return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Result: map[string]any{
			"capabilities": map[string]any{
				"textDocumentSync":   1,
				"completionProvider": map[string]any{"triggerCharacters": []string{".", " ", "=", ":", "\""}},
				"hoverProvider":      true,
				"codeActionProvider": true,
			},
			"serverInfo": map[string]any{"name": "hq-command-lsp", "version": "canonical"},
		}}}, nil
	case "initialized":
		return nil, nil
	case "shutdown":
		return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Result: nil}}, nil
	case "textDocument/didOpen":
		var p didOpenParams
		if err := json.Unmarshal(msg.Params, &p); err != nil {
			return nil, err
		}
		s.docs[p.TextDocument.URI] = document{Text: p.TextDocument.Text, Version: p.TextDocument.Version}
		return s.publishDiagnostics(p.TextDocument.URI), nil
	case "textDocument/didChange":
		var p didChangeParams
		if err := json.Unmarshal(msg.Params, &p); err != nil {
			return nil, err
		}
		if len(p.ContentChanges) > 0 {
			s.docs[p.TextDocument.URI] = document{Text: p.ContentChanges[len(p.ContentChanges)-1].Text, Version: p.TextDocument.Version}
		}
		return s.publishDiagnostics(p.TextDocument.URI), nil
	case "textDocument/completion":
		var p completionParams
		if err := json.Unmarshal(msg.Params, &p); err != nil {
			return nil, err
		}
		doc := s.docs[p.TextDocument.URI]
		line := linePrefix(doc.Text, p.Position.Line, p.Position.Character)
		suggestions := core.Complete(s.Model, core.CursorContext{Line: line, Prefix: line, BufferVersion: doc.Version})
		items := make([]completionItem, 0, len(suggestions))
		for _, sug := range suggestions {
			items = append(items, completionItem{
				Label:         sug.Label,
				Kind:          14,
				Detail:        sug.Detail,
				Documentation: markupContent{Kind: "markdown", Value: fmt.Sprintf("**meaning**: %s\n\n`%s`", sug.Meaning, sug.EditText)},
				InsertText:    sug.EditText,
				Data:          map[string]any{"meaning": sug.Meaning, "planDraft": sug.PlanDraft},
			})
		}
		return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Result: completionList{IsIncomplete: false, Items: items}}}, nil
	case "textDocument/hover":
		var p completionParams
		if err := json.Unmarshal(msg.Params, &p); err != nil {
			return nil, err
		}
		doc := s.docs[p.TextDocument.URI]
		line := strings.TrimSpace(linePrefix(doc.Text, p.Position.Line, p.Position.Character))
		plan, err := core.BuildPlan(s.Model, line, doc.Version)
		if err != nil {
			return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Result: hover{Contents: markupContent{Kind: "markdown", Value: "No complete PlanDraft yet: " + err.Error()}}}}, nil
		}
		b, _ := json.MarshalIndent(plan, "", "  ")
		return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Result: hover{Contents: markupContent{Kind: "markdown", Value: "```json\n" + string(b) + "\n```"}}}}, nil
	case "textDocument/codeAction":
		var p codeActionParams
		if err := json.Unmarshal(msg.Params, &p); err != nil {
			return nil, err
		}
		doc := s.docs[p.TextDocument.URI]
		line := strings.TrimSpace(fullLine(doc.Text, p.Range.Start.Line))
		plan, err := core.BuildPlan(s.Model, line, doc.Version)
		if err != nil {
			return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Result: []codeAction{}}}, nil
		}
		title := "HQ Dispatch: " + plan.CommandText
		actions := []codeAction{{Title: title, Kind: "quickfix", Command: command{Title: title, Command: "hq.dispatch", Arguments: []any{plan}}}}
		return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Result: actions}}, nil
	default:
		if len(msg.ID) == 0 {
			return nil, nil
		}
		return []jsonrpc.Message{{JSONRPC: "2.0", ID: msg.ID, Error: &jsonrpc.Error{Code: -32601, Message: "method not found: " + msg.Method}}}, nil
	}
}

func (s *Server) publishDiagnostics(uri string) []jsonrpc.Message {
	doc := s.docs[uri]
	lines := strings.Split(doc.Text, "\n")
	var diags []lspDiagnostic
	for i, line := range lines {
		for _, d := range core.Diagnose(s.Model, line, doc.Version) {
			severity := 1
			if d.Severity == "warning" {
				severity = 2
			}
			diags = append(diags, lspDiagnostic{Range: lspRange{Start: position{Line: i, Character: d.Start}, End: position{Line: i, Character: d.End}}, Severity: severity, Source: "hq", Message: d.Message})
		}
	}
	return []jsonrpc.Message{{JSONRPC: "2.0", Method: "textDocument/publishDiagnostics", Params: mustRaw(map[string]any{"uri": uri, "diagnostics": diags})}}
}

func mustRaw(v any) json.RawMessage {
	b, _ := json.Marshal(v)
	return b
}

func linePrefix(text string, lineNo, ch int) string {
	line := fullLine(text, lineNo)
	runes := []rune(line)
	if ch < 0 {
		ch = 0
	}
	if ch > len(runes) {
		ch = len(runes)
	}
	return string(runes[:ch])
}

func fullLine(text string, lineNo int) string {
	lines := strings.Split(text, "\n")
	if lineNo < 0 || lineNo >= len(lines) {
		return ""
	}
	return lines[lineNo]
}

type textDocumentItem struct {
	URI     string `json:"uri"`
	Version int    `json:"version"`
	Text    string `json:"text"`
}
type versionedTextDocumentIdentifier struct {
	URI     string `json:"uri"`
	Version int    `json:"version"`
}
type textDocumentIdentifier struct {
	URI string `json:"uri"`
}
type didOpenParams struct {
	TextDocument textDocumentItem `json:"textDocument"`
}
type didChangeParams struct {
	TextDocument   versionedTextDocumentIdentifier `json:"textDocument"`
	ContentChanges []struct {
		Text string `json:"text"`
	} `json:"contentChanges"`
}
type position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}
type completionParams struct {
	TextDocument textDocumentIdentifier `json:"textDocument"`
	Position     position               `json:"position"`
}
type lspRange struct {
	Start position `json:"start"`
	End   position `json:"end"`
}
type codeActionParams struct {
	TextDocument textDocumentIdentifier `json:"textDocument"`
	Range        lspRange               `json:"range"`
}
type completionList struct {
	IsIncomplete bool             `json:"isIncomplete"`
	Items        []completionItem `json:"items"`
}
type completionItem struct {
	Label         string        `json:"label"`
	Kind          int           `json:"kind,omitempty"`
	Detail        string        `json:"detail,omitempty"`
	Documentation markupContent `json:"documentation,omitempty"`
	InsertText    string        `json:"insertText,omitempty"`
	Data          any           `json:"data,omitempty"`
}
type markupContent struct {
	Kind  string `json:"kind"`
	Value string `json:"value"`
}
type hover struct {
	Contents markupContent `json:"contents"`
}
type command struct {
	Title     string `json:"title"`
	Command   string `json:"command"`
	Arguments []any  `json:"arguments,omitempty"`
}
type codeAction struct {
	Title   string  `json:"title"`
	Kind    string  `json:"kind,omitempty"`
	Command command `json:"command"`
}
type lspDiagnostic struct {
	Range    lspRange `json:"range"`
	Severity int      `json:"severity"`
	Source   string   `json:"source,omitempty"`
	Message  string   `json:"message"`
}
