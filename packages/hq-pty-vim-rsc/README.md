# hq PTY Vim recursive slot completion proof

This repository proves the line-editor replacement target:

```text
terminal emulator
  -> herdr-like single PTY owner
      -> exec vim directly, without shell wrapper
      -> input middleware
          -> recursive slot completion
          -> JSONL candidate protocol
```

The proof builds a 1 x n JSONL object relationship:

```text
project:hq
  ├─ task:t1
  ├─ task:t2
  └─ task:t3
```

Typing this into Vim through the PTY master:

```json
{"kind":"project","tasks":[
```

classifies the cursor as:

```json
{"slot_kind":"array.item","slot_path":["tasks"]}
```

and produces candidates:

```text
task:t1
task:t2
task:t3
```

Run:

```sh
./scripts/proof_rsc_pty_vim.sh
```

Expected:

```text
RSC_PTY_VIM_PROOF_OK
```


## Loose string intake validation proof

The RSC proof now accepts loose string input and immediately normalizes it into a strict `DraftObject`:

```text
project hq tasks 
  -> DraftObject{kind: project.patch, root_id: project:hq, operation: append-ref, path: [tasks], missing: [ref]}
  -> soft validation + task ref suggestions
  -> accept by canonical suggestion id/hash/version
  -> instruction.jsonl
```

Run:

```sh
./scripts/proof_loose_draft_validation.sh
```
