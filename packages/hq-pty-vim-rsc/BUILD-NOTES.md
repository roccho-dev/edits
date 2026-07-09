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

## Host path open semantic proof

The Windows proof now checks the allowed shape without restoring the retired Vim
Explorer plugin:

```text
Vim -> hqwin -> hq.hostPathOpenQueued.v1 JSONL
    -> hqwin dispatch -> hq.hostPathOpenReceipt.v1 JSONL
    -> explorer-compatible binary
```

The executable used in proof is `cmd/fake-explorer`, not the real Windows shell
UI. This keeps CI side-effect contained while proving that Vim does not call
Explorer directly and that the host action only happens after a confirmed hq
JSONL intent.
