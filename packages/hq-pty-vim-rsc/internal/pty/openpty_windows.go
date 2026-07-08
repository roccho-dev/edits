//go:build windows

package pty

import (
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
	"unicode/utf16"
	"unsafe"
)

type Master interface {
	io.Reader
	io.Writer
	io.Closer
}

type Session struct {
	Master      Master
	inputRead   syscall.Handle
	outputWrite syscall.Handle
	hpc         uintptr
	process     syscall.Handle
	thread      syscall.Handle
	pid         int
}

type pipeMaster struct {
	input  *os.File
	output *os.File
}

func (m *pipeMaster) Read(p []byte) (int, error)  { return m.output.Read(p) }
func (m *pipeMaster) Write(p []byte) (int, error) { return m.input.Write(p) }
func (m *pipeMaster) Close() error {
	if m.input != nil {
		_ = m.input.Close()
	}
	if m.output != nil {
		_ = m.output.Close()
	}
	return nil
}

type coord struct{ X, Y int16 }
type startupInfoEx struct {
	syscall.StartupInfo
	ProcThreadAttributeList *byte
}

const (
	extendedStartupInfoPresent       = 0x00080000
	createUnicodeEnvironment        = 0x00000400
	procThreadAttributePseudoConsole = 0x00020016
	infinite                         = 0xffffffff
)

var (
	kernel32                              = syscall.NewLazyDLL("kernel32.dll")
	procCreatePseudoConsole              = kernel32.NewProc("CreatePseudoConsole")
	procClosePseudoConsole               = kernel32.NewProc("ClosePseudoConsole")
	procInitializeProcThreadAttributeList = kernel32.NewProc("InitializeProcThreadAttributeList")
	procUpdateProcThreadAttribute        = kernel32.NewProc("UpdateProcThreadAttribute")
	procDeleteProcThreadAttributeList    = kernel32.NewProc("DeleteProcThreadAttributeList")
)

func Start(argv []string, env []string) (*Session, error) {
	if len(argv) == 0 {
		return nil, fmt.Errorf("empty argv")
	}
	var inRead, inWrite syscall.Handle
	var outRead, outWrite syscall.Handle
	if err := syscall.CreatePipe(&inRead, &inWrite, nil, 0); err != nil {
		return nil, fmt.Errorf("CreatePipe input: %w", err)
	}
	if err := syscall.CreatePipe(&outRead, &outWrite, nil, 0); err != nil {
		_ = syscall.CloseHandle(inRead)
		_ = syscall.CloseHandle(inWrite)
		return nil, fmt.Errorf("CreatePipe output: %w", err)
	}
	var hpc uintptr
	if r1, _, err := procCreatePseudoConsole.Call(uintptr(unsafe.Pointer(&coord{X: 120, Y: 40})), uintptr(inRead), uintptr(outWrite), 0, uintptr(unsafe.Pointer(&hpc))); r1 != 0 {
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, fmt.Errorf("CreatePseudoConsole: %w", err)
	}
	var attrSize uintptr
	procInitializeProcThreadAttributeList.Call(0, 1, 0, uintptr(unsafe.Pointer(&attrSize)))
	attrBuf := make([]byte, attrSize)
	attrList := unsafe.Pointer(&attrBuf[0])
	if r1, _, err := procInitializeProcThreadAttributeList.Call(uintptr(attrList), 1, 0, uintptr(unsafe.Pointer(&attrSize))); r1 == 0 {
		procClosePseudoConsole.Call(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, fmt.Errorf("InitializeProcThreadAttributeList: %w", err)
	}
	if r1, _, err := procUpdateProcThreadAttribute.Call(uintptr(attrList), 0, procThreadAttributePseudoConsole, uintptr(unsafe.Pointer(&hpc)), unsafe.Sizeof(hpc), 0, 0); r1 == 0 {
		procDeleteProcThreadAttributeList.Call(uintptr(attrList))
		procClosePseudoConsole.Call(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, fmt.Errorf("UpdateProcThreadAttribute: %w", err)
	}
	si := startupInfoEx{ProcThreadAttributeList: (*byte)(attrList)}
	si.Cb = uint32(unsafe.Sizeof(si))
	var pi syscall.ProcessInformation
	cmdlineRaw := windowsCommandLine(argv)
	cmdline, err := syscall.UTF16PtrFromString(cmdlineRaw)
	if err != nil {
		procDeleteProcThreadAttributeList.Call(uintptr(attrList))
		procClosePseudoConsole.Call(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, err
	}
	envBlock := makeEnvBlock(env)
	var envPtr *uint16
	if len(envBlock) > 0 {
		envPtr = &envBlock[0]
	}
	flags := uint32(extendedStartupInfoPresent | createUnicodeEnvironment)
	err = syscall.CreateProcess(nil, cmdline, nil, nil, false, flags, envPtr, nil, (*syscall.StartupInfo)(unsafe.Pointer(&si)), &pi)
	procDeleteProcThreadAttributeList.Call(uintptr(attrList))
	if err != nil {
		procClosePseudoConsole.Call(hpc)
		closeHandles(inRead, inWrite, outRead, outWrite)
		return nil, fmt.Errorf("CreateProcess %q: %w", cmdlineRaw, err)
	}
	return &Session{Master: &pipeMaster{input: os.NewFile(uintptr(inWrite), "conpty-input"), output: os.NewFile(uintptr(outRead), "conpty-output")}, inputRead: inRead, outputWrite: outWrite, hpc: hpc, process: pi.Process, thread: pi.Thread, pid: int(pi.ProcessId)}, nil
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
	_, err := syscall.WaitForSingleObject(s.process, infinite)
	if err == syscall.Errno(0) {
		return nil
	}
	return err
}
func (s *Session) Close() error {
	if s == nil {
		return nil
	}
	if s.Master != nil {
		_ = s.Master.Close()
	}
	closeHandles(s.inputRead, s.outputWrite)
	if s.process != 0 {
		_ = syscall.TerminateProcess(s.process, 1)
		_ = syscall.CloseHandle(s.process)
	}
	if s.thread != 0 {
		_ = syscall.CloseHandle(s.thread)
	}
	if s.hpc != 0 {
		procClosePseudoConsole.Call(s.hpc)
	}
	return nil
}

func closeHandles(handles ...syscall.Handle) {
	for _, h := range handles {
		if h != 0 {
			_ = syscall.CloseHandle(h)
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

func windowsCommandLine(argv []string) string {
	parts := make([]string, len(argv))
	for i, a := range argv {
		parts[i] = quoteArg(a)
	}
	return strings.Join(parts, " ")
}
func quoteArg(s string) string {
	if s == "" {
		return `""`
	}
	if !strings.ContainsAny(s, " \t\n\v\"") {
		return s
	}
	var b strings.Builder
	b.WriteByte('"')
	bs := 0
	for _, r := range s {
		if r == '\\' {
			bs++
			continue
		}
		if r == '"' {
			b.WriteString(strings.Repeat(`\`, bs*2+1))
			b.WriteRune(r)
			bs = 0
			continue
		}
		if bs > 0 {
			b.WriteString(strings.Repeat(`\`, bs))
			bs = 0
		}
		b.WriteRune(r)
	}
	if bs > 0 {
		b.WriteString(strings.Repeat(`\`, bs*2))
	}
	b.WriteByte('"')
	return b.String()
}
