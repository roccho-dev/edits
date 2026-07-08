//go:build !unix || !cgo

package pty

import (
	"fmt"
	"os"
)

type Session struct{ Master *os.File }

func Start(argv []string, env []string) (*Session, error) {
	return nil, fmt.Errorf("pty proof requires unix+cgo")
}
func (s *Session) PID() int    { return 0 }
func (s *Session) Wait() error { return nil }
func (s *Session) Close() error {
	if s != nil && s.Master != nil {
		_ = s.Master.Close()
	}
	return nil
}
