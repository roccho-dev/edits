//go:build windows

package pty

import (
	"bytes"
	"io"
	"strings"
	"testing"
	"time"
)

func TestConPTYCmdEchoOutput(t *testing.T) {
	sess, err := Start([]string{"cmd.exe", "/c", "echo", "hq-conpty-ok"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	done := make(chan error, 1)
	go func() {
		_, err := io.Copy(&buf, sess.Master)
		done <- err
	}()
	_ = sess.Wait()
	_ = sess.Close()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatalf("timed out reading ConPTY output; got so far %q", buf.String())
	}
	if !strings.Contains(buf.String(), "hq-conpty-ok") {
		t.Fatalf("missing conpty output; got %q", buf.String())
	}
}
