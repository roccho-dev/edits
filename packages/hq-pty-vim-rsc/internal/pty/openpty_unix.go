//go:build unix && cgo

package pty

/*
#include <pty.h>
#include <stdlib.h>
#include <unistd.h>
*/
import "C"

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
)

type Session struct {
	Master *os.File
	cmd    *exec.Cmd
}

func Start(argv []string, env []string) (*Session, error) {
	if len(argv) == 0 {
		return nil, fmt.Errorf("empty argv")
	}
	var master C.int
	var slave C.int
	if C.openpty(&master, &slave, nil, nil, nil) != 0 {
		return nil, fmt.Errorf("openpty failed")
	}
	mf := os.NewFile(uintptr(master), "pty-master")
	sf := os.NewFile(uintptr(slave), "pty-slave")
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdin = sf
	cmd.Stdout = sf
	cmd.Stderr = sf
	cmd.Env = append(os.Environ(), env...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
	if err := cmd.Start(); err != nil {
		_ = mf.Close()
		_ = sf.Close()
		return nil, err
	}
	_ = sf.Close()
	return &Session{Master: mf, cmd: cmd}, nil
}

func (s *Session) PID() int {
	if s == nil || s.cmd == nil || s.cmd.Process == nil {
		return 0
	}
	return s.cmd.Process.Pid
}

func (s *Session) Wait() error {
	if s == nil || s.cmd == nil {
		return nil
	}
	return s.cmd.Wait()
}

func (s *Session) Close() error {
	if s == nil {
		return nil
	}
	if s.Master != nil {
		_ = s.Master.Close()
	}
	if s.cmd != nil && s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
	}
	return nil
}
