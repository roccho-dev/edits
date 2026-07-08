//go:build !unix || !cgo

package pty

import "fmt"

type Session struct{}

func Start(argv []string, env []string) (*Session, error) {
	return nil, fmt.Errorf("pty proof requires unix+cgo")
}
func (s *Session) PID() int     { return 0 }
func (s *Session) Wait() error  { return nil }
func (s *Session) Close() error { return nil }
