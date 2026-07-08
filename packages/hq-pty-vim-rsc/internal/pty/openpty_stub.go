//go:build (!unix || !cgo) && !windows

package pty

import (
	"fmt"
	"io"
)

type Master interface {
	io.Reader
	io.Writer
	io.Closer
}

type Session struct{ Master Master }

func Start(argv []string, env []string) (*Session, error) {
	return nil, fmt.Errorf("pty proof requires unix+cgo or windows conpty")
}
func (s *Session) PID() int    { return 0 }
func (s *Session) Wait() error { return nil }
func (s *Session) Close() error {
	if s != nil && s.Master != nil {
		_ = s.Master.Close()
	}
	return nil
}
