# build notes

## Local Windows probe

The current Windows host did not have `go` on `PATH`, so the original probe used
mise:

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

The active Windows proof should stay focused on the ConPTY/Vim/RSC boundary.
Direct Explorer launch behavior has been retired from this package. If host path
opening is reintroduced, it must be modeled as hq semantics first and then pass
through explicit confirmation plus an ops/runtime receipt boundary.
