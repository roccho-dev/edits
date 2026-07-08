# auto-complete

A small domain Japanese completion package.

This package keeps the current Vim proof behavior as a golden contract while introducing a Go LSP seed. The goal is to move candidate generation, dictionary lookup, rank merge, and replace-range calculation out of Vimscript so Vim becomes an adapter only.

## Current golden behavior

- raw buffer remains romaji / English while typing
- normal candidates and Japanese domain dictionary candidates coexist
- normal candidates keep priority in the current default rank
- Japanese candidates replace only the active romaji run at commit time

## Commands

```sh
bash test/run.sh
python3 test/golden_check.py
go test ./...
```

## Scope

This is not a general Japanese IME. It is a domain completion core and LSP adapter seed.
