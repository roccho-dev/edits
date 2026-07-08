# build notes

## Local Windows probe

The current Windows host did not have `go` on `PATH`, so the probe used mise:

```powershell
mise x go@1.23.2 -- go version
mise x go@1.23.2 -- go test ./...
mise x go@1.23.2 -- go build -o .\bin\hq.exe .\cmd\hq
```

Observed:

```text
go version go1.23.2 windows/amd64
```

Passing packages:

```text
hq/internal/core
hq/internal/jsonrpc
hq/internal/pty
hq/internal/lsp
hq/internal/rsc
```

Failing boundaries:

```text
hq/cmd/hq build failed:
  cmd\hq\rsc_cmd.go: sess.Master undefined

hq/internal/dispatcher tests failed:
  'printf' is not recognized as an internal or external command
```

## Interpretation

The archive is not a drop-in Windows executable by `go build ./cmd/hq`.

The likely fix is small but required:

- split Unix PTY proof commands behind Unix build tags, or expose a Windows
  compatible PTY/ConPTY implementation;
- separate the pure completion/Explorer launcher binary from Unix PTY proof
  commands;
- adjust shell adapter tests for Windows, or mark Unix shell behavior as
  Unix-only.

For the immediate Herdr/Vim Explorer workflow, the implementation should start
with the pure RSC completion path plus a Windows launcher adapter, not with the
Unix PTY proof command.
