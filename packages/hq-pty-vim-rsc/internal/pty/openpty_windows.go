//go:build windows

package pty

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
	"unicode/utf16"
	"unsafe"

	"golang.org/x/sys/windows"
)

type Master interface {
	io.Reader
	io.Writer
	io.Closer
}

type Session struct {
	Master   Master
	hpc      windows.Handle
	attrList *windows.ProcThreadAttributeListContainer
	process  windows.Handle
	thread   windows.Handle
	pid      int
	inRead   windows.Handle
	outWrite windows.Handle
	mu       sync.Mutex
	closed   bool
}

type pipeMaster struct {
	inWrite windows.Handle
	outRead windows.Handle
}

func (m *pipeMaster) Read(p []byte) (int, error) {
	var n uint32
	err := windows.ReadFile(m.outRead, p, &n, nil)
	return int(n), err
}
func (m *pipeMaster) Write(p []byte) (int, error) {
	var n uint32
	err := windows.WriteFile(m.inWrite, p, &n, nil)
	return int(n), err
}
func (m *pipeMaster) Close() error {
	closeHandles(m.inWrite, m.outRead)
	m.inWrite = 0
	m.outRead = 0
	return nil
}

func Start(argv []string, env []string) (*Session, error) {
	if len(argv) == 0 {
		return nil, fmt.Errorf("empty argv")
	}
	resolvedArgv := append([]string(nil), argv...)
	if p, err := exec.LookPath(argv[0]); err == nil {
		resolvedArgv[0] = p
	}
	sa := &windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), InheritHandle: 1}
	var inRead, inWrite windows.Handle
	var outRead, outWrite windows.Handle
	if err := windows.CreatePipe(&inRead, &inWrite, sa, 0); err != nil {
		return nil, fmt.Errorf("CreatePipe input: %w", err)
	}
	if err := windows.CreatePipe(&outRead, &outWrite, sa, 0); err != nil {
		closeHandles(inRead, inWrite)
		return nil, fmt.Errorf("CreatePipe output: %w", err)
	}
	var hpc windows.Handle
	if err := windows.CreatePseudoConsole(windows.Coord{X: 120, Y: 40}, inRead, outWrite, 0, &hpc); err != nil {
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, fmt.Errorf("CreatePseudoConsole: %w", err)
	}
	attrList, err := windows.NewProcThreadAttributeList(1)
	if err != nil {
		windows.ClosePseudoConsole(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, err
	}
	if err := attrList.Update(windows.PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, unsafe.Pointer(hpc), unsafe.Sizeof(hpc)); err != nil {
		attrList.Delete()
		windows.ClosePseudoConsole(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, fmt.Errorf("UpdateProcThreadAttribute: %w", err)
	}
	si := windows.StartupInfoEx{}
	si.StartupInfo.Flags = windows.STARTF_USESTDHANDLES
	si.ProcThreadAttributeList = attrList.List()
	si.Cb = uint32(unsafe.Sizeof(si))
	var pi windows.ProcessInformation
	argv0p, err := windows.UTF16PtrFromString(resolvedArgv[0])
	if err != nil {
		attrList.Delete()
		windows.ClosePseudoConsole(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, err
	}
	cmdline := windows.ComposeCommandLine(resolvedArgv)
	cmdlinep, err := windows.UTF16PtrFromString(cmdline)
	if err != nil {
		attrList.Delete()
		windows.ClosePseudoConsole(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, err
	}
	envBlock := makeEnvBlock(env)
	var envPtr *uint16
	if len(envBlock) > 0 {
		envPtr = &envBlock[0]
	}
	flags := uint32(windows.EXTENDED_STARTUPINFO_PRESENT | windows.CREATE_UNICODE_ENVIRONMENT)
	if err := windows.CreateProcess(argv0p, cmdlinep, sa, sa, false, flags, envPtr, nil, &si.StartupInfo, &pi); err != nil {
		attrList.Delete()
		windows.ClosePseudoConsole(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, fmt.Errorf("CreateProcess %q: %w", cmdline, err)
	}
	return &Session{Master: &pipeMaster{inWrite: inWrite, outRead: outRead}, hpc: hpc, attrList: attrList, process: pi.Process, thread: pi.Thread, pid: int(pi.ProcessId), inRead: inRead, outWrite: outWrite}, nil
}

func (s *Session) PID() int {
	if s == nil {
		return 0
	}
	return s.pid
}
func (s *Session) Wait() error {
	if s == nil || s.process == 0 {
		return nil
	}
	_, err := windows.WaitForSingleObject(s.process, windows.INFINITE)
	return err
}
func (s *Session) Close() error {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true
	if s.Master != nil {
		_ = s.Master.Close()
		s.Master = nil
	}
	closeHandles(s.inRead, s.outWrite)
	s.inRead, s.outWrite = 0, 0
	if s.attrList != nil {
		s.attrList.Delete()
		s.attrList = nil
	}
	if s.process != 0 {
		if state, err := windows.WaitForSingleObject(s.process, 0); err == nil && state == uint32(windows.WAIT_TIMEOUT) {
			_ = windows.TerminateProcess(s.process, 1)
		}
		_ = windows.CloseHandle(s.process)
		s.process = 0
	}
	if s.thread != 0 {
		_ = windows.CloseHandle(s.thread)
		s.thread = 0
	}
	if s.hpc != 0 {
		windows.ClosePseudoConsole(s.hpc)
		s.hpc = 0
	}
	return nil
}

func closeHandles(handles ...windows.Handle) {
	for _, h := range handles {
		if h != 0 {
			_ = windows.CloseHandle(h)
		}
	}
}

func makeEnvBlock(extra []string) []uint16 {
	merged := map[string]string{}
	order := []string{}
	add := func(kv string) {
		if kv == "" || !strings.Contains(kv, "=") {
			return
		}
		key := strings.SplitN(kv, "=", 2)[0]
		lower := strings.ToLower(key)
		if _, ok := merged[lower]; !ok {
			order = append(order, lower)
		}
		merged[lower] = kv
	}
	for _, kv := range os.Environ() {
		add(kv)
	}
	for _, kv := range extra {
		add(kv)
	}
	var out []uint16
	for _, key := range order {
		out = append(out, utf16.Encode([]rune(merged[key]))...)
		out = append(out, 0)
	}
	out = append(out, 0)
	return out
}
