package lsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
	"io"
	"strconv"
	"strings"
)

type Server struct {
	Engine *core.Engine
	Docs   map[string]string
}

func NewServer(engine *core.Engine) *Server {
	return &Server{Engine: engine, Docs: map[string]string{}}
}

type rpcMessage struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  any             `json:"result,omitempty"`
}

func (s *Server) Serve(r io.Reader, w io.Writer) error {
	br := bufio.NewReader(r)
	for {
		payload, err := readMessage(br)
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
		resp, exit, err := s.handle(payload)
		if err != nil {
			return err
		}
		if resp != nil {
			if err := writeMessage(w, resp); err != nil {
				return err
			}
		}
		if exit {
			return nil
		}
	}
}
func (s *Server) handle(payload []byte) ([]byte, bool, error) {
	var msg rpcMessage
	if err := json.Unmarshal(payload, &msg); err != nil {
		return nil, false, err
	}
	if msg.Method == "" {
		return nil, false, nil
	}
	respond := msg.ID != nil
	var result any
	switch msg.Method {
	case "initialize":
		result = map[string]any{"capabilities": map[string]any{"textDocumentSync": 1, "completionProvider": map[string]any{"resolveProvider": false}}}
	case "initialized":
		respond = false
	case "exit":
		return nil, true, nil
	case "textDocument/didOpen":
		var p struct {
			TextDocument struct {
				URI  string `json:"uri"`
				Text string `json:"text"`
			} `json:"textDocument"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		s.Docs[p.TextDocument.URI] = p.TextDocument.Text
		respond = false
	case "textDocument/completion":
		var p struct {
			TextDocument struct {
				URI string `json:"uri"`
			} `json:"textDocument"`
			Position core.Position `json:"position"`
		}
		_ = json.Unmarshal(msg.Params, &p)
		result = s.Engine.CompletionItems(s.Docs[p.TextDocument.URI], p.Position.Line, p.Position.Character)
	default:
		if !respond {
			return nil, false, nil
		}
	}
	if !respond {
		return nil, false, nil
	}
	out, err := json.Marshal(rpcMessage{JSONRPC: "2.0", ID: msg.ID, Result: result})
	return out, false, err
}
func readMessage(r *bufio.Reader) ([]byte, error) {
	n := -1
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return nil, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 && strings.EqualFold(strings.TrimSpace(parts[0]), "Content-Length") {
			v, err := strconv.Atoi(strings.TrimSpace(parts[1]))
			if err != nil {
				return nil, err
			}
			n = v
		}
	}
	if n < 0 {
		return nil, fmt.Errorf("missing Content-Length")
	}
	payload := make([]byte, n)
	_, err := io.ReadFull(r, payload)
	return payload, err
}
func writeMessage(w io.Writer, payload []byte) error {
	_, err := fmt.Fprintf(w, "Content-Length: %d\r\n\r\n%s", len(payload), payload)
	return err
}
func Frame(payload []byte) []byte {
	var b bytes.Buffer
	_ = writeMessage(&b, payload)
	return b.Bytes()
}
