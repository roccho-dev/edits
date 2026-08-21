package smoke

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// TestNativePopupArtifactUsesControllingTTY is deliberately opt-in because it
// needs a real controlling terminal. The local proof runner executes this test
// under script(1) while redirecting the parent Go test output to a regular
// file. That makes the regression observable: without the NativePopupArtifact
// /dev/tty hand-off, the fake child inherits non-TTY stdout/stderr.
func TestNativePopupArtifactUsesControllingTTY(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("/dev/tty proof is Unix-only")
	}
	if os.Getenv("HQ_SMOKE_TTY_PROOF") != "1" {
		t.Skip("set HQ_SMOKE_TTY_PROOF=1 and run under a real controlling terminal")
	}

	terminal, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		t.Fatalf("open controlling terminal: %v", err)
	}
	_ = terminal.Close()

	root, err := PackageRoot("")
	if err != nil {
		t.Fatal(err)
	}
	tmp := t.TempDir()
	lspRoot := filepath.Join(tmp, "lsp")
	for _, path := range []string{
		filepath.Join(lspRoot, "plugin", "lsp.vim"),
		filepath.Join(lspRoot, "autoload", "lsp", "buffer.vim"),
	} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("\" local TTY fixture\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	proofPath := filepath.Join(tmp, "child-stdio.txt")
	fakeVim := filepath.Join(tmp, "fake-vim")
	fakeScript := `#!/bin/sh
set -eu
case " $* " in
  *" -S "*) ;;
  *) exit 0 ;;
esac
result=
for fd in 0 1 2; do
  if test -t "$fd"; then
    state=tty
  else
    state=not-tty
  fi
  result="${result}${fd}=${state}\n"
done
printf '%b' "$result" > "${FAKE_VIM_TTY_PROOF:?}"
`
	if err := os.WriteFile(fakeVim, []byte(fakeScript), 0o755); err != nil {
		t.Fatal(err)
	}

	artifact := filepath.Join(tmp, "native-popup-artifact.json")
	err = Run(Config{
		HQBin:                   "/bin/true",
		Vim:                     fakeVim,
		Vim9LSP:                 lspRoot,
		PluginRoot:              root,
		ExpectedCompletionLabel: "candidate",
		ExpectedCompletionText:  "candidate",
		NativePopupArtifact:     artifact,
		Env: map[string]string{
			"FAKE_VIM_TTY_PROOF": proofPath,
		},
		Timeout: 5 * time.Second,
	})
	if err != nil {
		t.Fatalf("smoke.Run: %v", err)
	}

	body, err := os.ReadFile(proofPath)
	if err != nil {
		t.Fatal(err)
	}
	got := strings.TrimSpace(string(body))
	want := "0=tty\n1=tty\n2=tty"
	if got != want {
		t.Fatalf("child stdio did not use controlling terminal\nwant:\n%s\ngot:\n%s", want, got)
	}
}
