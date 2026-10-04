# Native Decision Completion

## Installed semcmp connection

From this repository's root, build `nix build .#edits`. The default package is
the same executable. It closes over pinned stock Vim, the product/adapter/entry,
and the exact ops semcmp package plus Node and its required JS siblings.

Set `EDITS_SEMCMP_CATALOG` to an absolute JSON file containing an array of
`{id, meaning, representation}` records. IDs must be unique, nonempty strings;
representation is nonempty insertion text. Meaning stays opaque. The explicit
example at `result/share/edits/examples/proposals.json` has two relation records
and one text record; it is neither an inferred semantic model nor a fallback.

```sh
EDITS_SEMCMP_CATALOG=/absolute/path/proposals.json \
  LANG=C.UTF-8 TERM=xterm-256color result/bin/edits -Nu NONE -i NONE -n notes.txt
```

The entry attaches this buffer, including named, modified and multiline buffers.
It preserves caller Query/current/context; absent read context is unknown/null.
Its initial Query returns start=0 and the current line's cursor prefix as input.
Right suffixes and other lines remain. This is one replaceable composition,
not an Input enum, meaning parser or definition that every unit is a line.

In Insert mode use `Ctrl-X Ctrl-U`, `Ctrl-N/P`, `Ctrl-Y` or `Ctrl-E`. After
rewriting, explicitly complete again. Menu movement is temporary preview;
cancellation restores the input and preserves the previous selection's origin.

The native information popup shows the supplied meaning and evaluation evidence
separately from insertion text. With `Ctrl-N/P`, compare this information before
accepting: equal labels and scores can belong to different meanings. These are
the owner's JSON values, not a generated explanation or an executed action.
An accepted native selection keeps the full Proposal/evidence and raw query base
in `b:surface_selection`. Relation representation is text only, with no effect.
Edit and Undo remain native. `:write` and `:edit` save/read the local Working file;
they do not Commit or Adopt it. Cancellation can leave a text-neutral Undo step.

The adapter snapshots the configured catalog once and sends the private stdin
`{query, proposals}` composition to the installed CLI using a shell-free argv.
Query contains opaque input, full Working/current/context, and cursor/start focus.
It checks returned query, all candidate IDs, original meaning/representation and
evidence before producing the private `decision-completion.view/1` display.
That internal view permits an optional string `info` for reading only; callers
without it retain their insertion-text information. It is not a shared wire type.
Numeric JSON values may round-trip as Number/Float; strings remain distinct.
A final catalog byte check rejects observed source changes, without claiming
ABA or generation guarantees. Product native snapshot/guard checks remain in use.
Missing catalog, child failure or malformed/unrelated response fails closed:
no new active bundle, with Working and the last selection origin preserved.

The CLI reuses ops Jev evaluation/ranking and its existing `JEV_API_KEY`,
`JEV_API_URL`, `JEV_TIMEOUT_MS` environment. Credentials must come from an
authorized target-native entry. Existing fixed voice-ui/ops-jev launchers have
no arbitrary attribute/program/argument choice and are not reused as semcmp
credential launchers. No secret is copied or placed in a query/example/trace.

## Caller composition and retained fixture

For an independently composed surface, import `packages/vim/surface.vim` and
explicitly call `Attach()`. Buffer-local `surface_query` returns exactly
`{start, input}`; start is a UTF-8 byte boundary before the cursor on its line,
while input may describe an opaque semantic unit spanning lines. Acquire
receives a deep copy of the full raw snapshot plus start/input. Set opaque
`surface_source`, `surface_current` and `surface_context` as applicable.
Changing an IO binding requires changing its source marker.

Native temporary span removal is checked separately from raw evaluation input.
Each findstart capture is consumed once; exceptions, malformed values and changed
callbacks/context invalidate the result. No same-Funcref mutable-state guarantee
or remote evaluation authority is manufactured.

The separate unchanged `packages/vim/tests/surface.vim` requires a fresh empty
session and creates temporary examples from `tests/candidates.json`:

```sh
EDITS_COMPLETION_SOURCE=/absolute/path/packages/vim/tests/candidates.json \
  LANG=C.UTF-8 TERM=xterm-256color \
  vim -Nu NONE -i NONE -n -S /absolute/path/packages/vim/tests/surface.vim
```

## Evidence limits

The root flake checks the actual product/fixture tree and installed
`edits-semcmp-package-connection`. Test-only transport replacement checks fresh
query delivery/order changes, original typed records, numeric round-trips,
failure/source-change refusal, and origin preservation without network calls.
Native TTY controls separately exercise prefix replacement, suffix/other-line
preservation, preview/cancel/selection, Unicode editing/Undo and owned save/read.
Controlled scores are not Jev semantic-quality evidence.
Equal-text/equal-score controls verify distinct meaning information and unchanged
order, text and handles. Human comprehension of the displayed data remains a
separate acceptance gate, including whether native wrapping makes differences readable.

Real Jev access and the two-input ranking-quality trial await a permitted
credential entry. Actual Voice integration, Human Readline acceptance, general
unit interpretation and Commit/Prove/Admit/confirmed readback remain unproved.
