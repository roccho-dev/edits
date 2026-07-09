package hostopen

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	QueueKind   = "hq.hostPathOpenQueued.v1"
	ReceiptKind = "hq.hostPathOpenReceipt.v1"
)

type Target struct {
	Kind string `json:"kind"`
	Path string `json:"path"`
	Mode string `json:"mode"`
}

type Source struct {
	Client string `json:"client"`
}

type QueueRow struct {
	Kind      string `json:"kind"`
	ID        string `json:"id"`
	Confirmed bool   `json:"confirmed"`
	Target    Target `json:"target"`
	Source    Source `json:"source"`
}

type Plan struct {
	Executable string   `json:"executable"`
	Args       []string `json:"args"`
}

type Receipt struct {
	Kind      string `json:"kind"`
	ID        string `json:"id"`
	QueueID   string `json:"queue_id"`
	QueueHash string `json:"queue_hash"`
	Status    string `json:"status"`
	Time      string `json:"time"`
	Target    Target `json:"target"`
	Plan      Plan   `json:"plan"`
}

func NewQueueRow(id, path, mode, source string, confirmed bool) QueueRow {
	return QueueRow{
		Kind:      QueueKind,
		ID:        id,
		Confirmed: confirmed,
		Target: Target{
			Kind: "windows.host.path",
			Path: path,
			Mode: mode,
		},
		Source: Source{Client: source},
	}
}

func AppendQueue(path string, row QueueRow) error {
	if _, err := PlanFor(row, "explorer.exe"); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := json.Marshal(row)
	if err != nil {
		return err
	}
	if _, err := f.Write(append(b, '\n')); err != nil {
		return err
	}
	return nil
}

func DispatchQueue(queuePath, receiptPath, explorerBin string, execute bool) (Receipt, error) {
	row, raw, err := readFirstQueueRow(queuePath)
	if err != nil {
		return Receipt{}, err
	}
	plan, err := PlanFor(row, explorerBin)
	if err != nil {
		return Receipt{}, err
	}
	if execute {
		cmd := exec.Command(plan.Executable, plan.Args...)
		if out, err := cmd.CombinedOutput(); err != nil {
			return Receipt{}, fmt.Errorf("host open command failed: %w: %s", err, strings.TrimSpace(string(out)))
		}
	}
	receipt := Receipt{
		Kind:      ReceiptKind,
		ID:        "rcpt_" + row.ID,
		QueueID:   row.ID,
		QueueHash: hash(raw),
		Status:    status(execute),
		Time:      time.Now().UTC().Format(time.RFC3339),
		Target:    row.Target,
		Plan:      plan,
	}
	if err := appendReceipt(receiptPath, receipt); err != nil {
		return Receipt{}, err
	}
	return receipt, nil
}

func PlanFor(row QueueRow, explorerBin string) (Plan, error) {
	if row.Kind != QueueKind {
		return Plan{}, fmt.Errorf("unsupported host open queue kind %q", row.Kind)
	}
	if strings.TrimSpace(row.ID) == "" {
		return Plan{}, errors.New("host open queue id is required")
	}
	if !row.Confirmed {
		return Plan{}, errors.New("host open requires confirmed=true")
	}
	if row.Target.Kind != "windows.host.path" {
		return Plan{}, fmt.Errorf("unsupported host open target kind %q", row.Target.Kind)
	}
	if strings.TrimSpace(row.Target.Path) == "" {
		return Plan{}, errors.New("host open target path is required")
	}
	if looksRemote(row.Target.Path) {
		return Plan{}, fmt.Errorf("host open target must be a local Windows path: %s", row.Target.Path)
	}
	mode := row.Target.Mode
	if mode == "" {
		mode = "open"
	}
	var args []string
	switch mode {
	case "open":
		args = []string{row.Target.Path}
	case "select":
		args = []string{"/select," + row.Target.Path}
	default:
		return Plan{}, fmt.Errorf("unsupported host open mode %q", row.Target.Mode)
	}
	if strings.TrimSpace(explorerBin) == "" {
		explorerBin = "explorer.exe"
	}
	return Plan{Executable: explorerBin, Args: args}, nil
}

func readFirstQueueRow(path string) (QueueRow, []byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return QueueRow{}, nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		raw := append([]byte(nil), sc.Bytes()...)
		if len(strings.TrimSpace(string(raw))) == 0 {
			continue
		}
		var row QueueRow
		if err := json.Unmarshal(raw, &row); err != nil {
			return QueueRow{}, nil, err
		}
		return row, raw, nil
	}
	if err := sc.Err(); err != nil {
		return QueueRow{}, nil, err
	}
	return QueueRow{}, nil, errors.New("host open queue is empty")
}

func appendReceipt(path string, receipt Receipt) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := json.Marshal(receipt)
	if err != nil {
		return err
	}
	_, err = f.Write(append(b, '\n'))
	return err
}

func looksRemote(path string) bool {
	lower := strings.ToLower(path)
	return strings.Contains(lower, "://") ||
		strings.HasPrefix(lower, "ssh:") ||
		strings.HasPrefix(lower, "ssot:") ||
		strings.HasPrefix(lower, "kite:")
}

func status(execute bool) string {
	if execute {
		return "executed"
	}
	return "planned"
}

func hash(raw []byte) string {
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}
