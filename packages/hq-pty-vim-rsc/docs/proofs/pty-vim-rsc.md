# Proof: direct Vim PTY + recursive slot completion

This proof demonstrates the final line-editor replacement direction:

```text
herdr-like PTY master
  -> exec argv[0]=vim directly
  -> feed JSONL object text one character at a time
  -> PTY-master input middleware computes recursive slot completion
  -> 1 x n JSONL object relation appears as slot candidates
```

## Commands

```sh
./scripts/proof_rsc_pty_vim.sh
```

Expected result:

```text
RSC_PTY_VIM_PROOF_OK
```

## Proof artifacts

| path | meaning |
|---|---|
| `examples/tree_world.jsonl` | append-only schema/object/relation source |
| `cache/rsc-model.json` | reduced object/schema/relation model |
| `cache/rsc-key-complete.json` | object key slot completion |
| `cache/rsc-value-complete.json` | enum value slot completion |
| `cache/rsc-array-complete.json` | 1 x n relation child slot completion |
| `cache/rsc-accepted-instruction.json` | accepted candidate compiled into instruction |
| `cache/instruction.jsonl` | append-only accepted instruction queue |
| `cache/pty-vim-proof.json` | direct Vim PTY proof summary |
| `cache/pty-vim-slot-autocmp.jsonl` | one-character slot completion trace |

## Passed claims

- `proc_cmdline` begins with `/usr/bin/vim` and contains no shell command wrapper.
- Vim buffer saved exactly the characters sent by the PTY master.
- The final input `{"kind":"project","tasks":[` classifies to slot `array.item` at path `tasks`.
- The 1 parent x n children relation `project:hq -> task:t1,t2,t3` becomes three slot candidates.
- Suggestions contain side-effect-free `compileDraft` values.
- Accepting a suggestion appends an `instruction.accepted` JSONL row.
