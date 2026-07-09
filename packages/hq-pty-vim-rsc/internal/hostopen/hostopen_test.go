package hostopen

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPlanForConfirmedLocalOpen(t *testing.T) {
	row := NewQueueRow("vim-open-edits", `C:\Users\resta\Codex\repos\edits`, "open", "vim", true)
	plan, err := PlanFor(row, `C:\Windows\explorer.exe`)
	if err != nil {
		t.Fatalf("expected plan: %v", err)
	}
	if plan.Executable != `C:\Windows\explorer.exe` || len(plan.Args) != 1 || plan.Args[0] != row.Target.Path {
		t.Fatalf("unexpected plan: %+v", plan)
	}
}

func TestPlanRejectsUnconfirmedIntent(t *testing.T) {
	row := NewQueueRow("vim-open-edits", `C:\Users\resta\Codex\repos\edits`, "open", "vim", false)
	if _, err := PlanFor(row, "explorer.exe"); err == nil {
		t.Fatal("expected unconfirmed host open intent to be rejected")
	}
}

func TestPlanForSelectUsesSingleExplorerArg(t *testing.T) {
	row := NewQueueRow("vim-select-file", `C:\Users\resta\Codex\repos\edits\README.md`, "select", "vim", true)
	plan, err := PlanFor(row, "explorer.exe")
	if err != nil {
		t.Fatalf("expected plan: %v", err)
	}
	if len(plan.Args) != 1 || plan.Args[0] != `/select,C:\Users\resta\Codex\repos\edits\README.md` {
		t.Fatalf("unexpected select args: %+v", plan.Args)
	}
}

func TestPlanRejectsRemoteTarget(t *testing.T) {
	row := NewQueueRow("vim-open-kite", "kite:/srv/repos/edits", "open", "vim", true)
	if _, err := PlanFor(row, "explorer.exe"); err == nil {
		t.Fatal("expected remote host open target to be rejected")
	}
}

func TestDispatchQueueWritesReceipt(t *testing.T) {
	dir := t.TempDir()
	queue := filepath.Join(dir, "queue.jsonl")
	receipts := filepath.Join(dir, "receipts.jsonl")
	row := NewQueueRow("vim-open-edits", `C:\Users\resta\Codex\repos\edits`, "open", "vim", true)
	if err := AppendQueue(queue, row); err != nil {
		t.Fatalf("append queue: %v", err)
	}
	receipt, err := DispatchQueue(queue, receipts, "explorer.exe", false)
	if err != nil {
		t.Fatalf("dispatch queue: %v", err)
	}
	if receipt.Kind != ReceiptKind || receipt.Status != "planned" || receipt.QueueID != row.ID {
		t.Fatalf("unexpected receipt: %+v", receipt)
	}
	if b, err := os.ReadFile(receipts); err != nil || len(b) == 0 {
		t.Fatalf("receipt not written: len=%d err=%v", len(b), err)
	}
}
