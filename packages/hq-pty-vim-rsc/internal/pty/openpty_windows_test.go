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
	sess, err := Start([]string{"cmd.exe"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	done := make(chan error, 1)
	go func() {
		_, err := io.Copy(&buf, sess.Master)
		done <- err
	}()
	waitForAnyOutput(t, &buf, 3*time.Second)
	time.Sleep(1200 * time.Millisecond)
	if _, err := sess.Master.Write([]byte("echo hq-conpty-ok\r")); err != nil {
		_ = sess.Close()
		t.Fatalf("write echo to ConPTY failed: %v", err)
	}
	waitContains(t, &buf, "hq-conpty-ok", 3*time.Second)
	if _, err := sess.Master.Write([]byte("exit\r")); err != nil {
		_ = sess.Close()
		t.Fatalf("write exit to ConPTY failed: %v", err)
	}
	_ = sess.Wait()
	_ = sess.Close()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatalf("timed out reading ConPTY EOF; got %q", buf.String())
	}
	if !strings.Contains(buf.String(), "hq-conpty-ok") {
		t.Fatalf("missing conpty output; got %q", buf.String())
	}
}

func waitForAnyOutput(t *testing.T, buf *bytes.Buffer, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if buf.Len() > 0 {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for any ConPTY output")
}

func waitContains(t *testing.T, buf *bytes.Buffer, want string, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if strings.Contains(buf.String(), want) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %q; got %q", want, buf.String())
}
