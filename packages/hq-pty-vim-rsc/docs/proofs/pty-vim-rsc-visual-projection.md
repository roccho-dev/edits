# PTY master -> direct Vim -> visual slot projection proof

This proof verifies that recursive slot completion is not only logged, but also projected into the Vim screen as a popup.

## Path

```text
Go hq proof command
  -> PTY master
      -> direct child: /usr/bin/vim -Nu NONE -n -i NONE -S <script> <buffer>
          -> TextChangedI projection adapter
              -> PTY-master-generated core projection map
              -> popup_create()
              -> screenstring() capture
```

No shell wrapper is used to start Vim. The proof records the child proc cmdline and rejects `sh\0` in that cmdline. The visual adapter does not shell out to query candidates; the PTY master precomputes the recursive slot projection map from Go core and Vim only projects it.

## Visual assertion

The captured Vim screen must contain:

```text
HQ SLOT PROJECTION
slot: array.item path: tasks
> task:t1
> task:t2
> task:t3
```

The final popup trace must also report `slot_kind=array.item`, `slot_path=["tasks"]`, and labels `task:t1`, `task:t2`, `task:t3`.

## Artifacts

```text
cache/vim-visual-projection.json
cache/vim-visual-projection.trace.jsonl
cache/vim-visual-projection.screen.txt
cache/vim-visual-projection.pty.raw
cache/vim-visual-projection.png
cache/vim-visual-projection.html
```

Run:

```sh
./scripts/proof_visual_projection.sh
```

Expected:

```text
VIM_VISUAL_PROJECTION_PROOF_OK
```
