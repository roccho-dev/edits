# Native Decision Completion

## Installed semcmp connection

From this repository's root, build `nix build .#edits`. The default package is
the same executable. It closes over pinned stock Vim, the product/adapter/entry,
and the exact ops semcmp package plus Node and its required JS siblings.

Set `EDITS_SEMCMP_PROPOSER` to an absolute JavaScript module exporting
`propose(query)`. Installed semcmp loads it through its private `--propose`
entry and asks it for `{id, meaning, representation}` records for that exact
query; it may return none. Proposal sources, generation and their correspondence
belong to that owner, not to Vim. edits installs no proposer, catalog or example.

```sh
EDITS_SEMCMP_PROPOSER=/absolute/path/proposer.mjs \
  LANG=C.UTF-8 TERM=xterm-256color result/bin/edits -Nu NONE -i NONE -n notes.txt
```

The entry attaches this buffer, including named, modified and multiline buffers.
It preserves caller Query/current/context; absent read context is unknown/null.
Its initial Query returns start=0 and the current line's cursor prefix as input.
Right suffixes and other lines remain. This is one replaceable composition,
not an Input enum, meaning parser or definition that every unit is a line.

In Insert mode just type. Every Human edit, from the first character on, is an
eligible request; one semcmp process runs at a time and further edits only mark
that the latest text must be asked next, so typing never waits. An answer is
shown as the native menu only if it answers the newest request and the buffer,
window, Working, cursor, source/current/context and Insert mode are unchanged and
no other menu or preview is active. Otherwise it is dropped. No proposal shows
nothing. Leaving Insert mode, the buffer or the window drops pending answers and
stops their semcmp process. Every process is also stopped after two owner
timeouts (`2 × JEV_TIMEOUT_MS`, default 15000 ms each), reported as `TIMEOUT`.
Native preview (`Ctrl-N/P`), cancelling (`Ctrl-E`) and accepting this menu are not
new requests; after cancel or accept nothing reappears until the Human edits again
or asks with `Ctrl-X Ctrl-U`. Without this menu, `Ctrl-E`/`Ctrl-Y` keep their native
Insert meaning. Cancellation restores the input and preserves the previous origin.

The native information popup shows the full insertion representation, followed
by the supplied meaning and evaluation evidence. With `Ctrl-N/P`, compare before
accepting: equal labels and scores can belong to different meanings. These are
the owner's JSON values, not a generated explanation or an executed action.
Equal first lines can also hide different later insertion lines; the popup keeps
those full lines independently of temporary preview. Only representation is inserted.
On acceptance, by `Ctrl-Y` or by continuing to type, Working becomes exactly the
prefix, the full representation and the original suffix; native reshaping of
multiline text is replaced by that composition within the same Undo step. Only the
inserted lines are rewritten. If other Working lines, the buffer,
source/current/context or the Query/Acquire binding changed since the menu was
shown, those lines return to the original line, the selection is not recorded
and other changes are kept.
An accepted native selection keeps the full Proposal/evidence, raw query base and
the information it was chosen with in `b:surface_selection`. `:SurfaceSelection`
rereads that selection-time, unadopted information; it is history of the choice,
not the current Working after later edits or Undo. Cancellation and acquisition
failure keep the previous origin. Relation representation is text only, with no effect.
Edit and Undo remain native. `:write` and `:edit` save/read the local Working file;
they do not Commit or Adopt it. Cancellation can leave a text-neutral Undo step.

The adapter starts the installed CLI as a Vim job with a shell-free argv
`semcmp --propose <module>` and writes the private stdin `{query}`. Query contains
opaque input, full Working/current/context, and cursor/start focus. It checks the
returned query, unique nonempty IDs, nonempty representation and evidence before
producing the private `decision-completion.view/1` display, keeping each returned
Proposal whole in its handle. That internal view permits an optional string
`info` for reading only; callers without it retain their insertion-text
information. It is not a shared wire type. Numeric JSON values may round-trip as
Number/Float; strings remain distinct. A missing proposer, child failure or
malformed/unrelated response fails closed with a bounded code (for example
`INVALID_PROPOSER`, `PROPOSE_FAILED`, `RESULT`): no menu, Working and the last
selection origin preserved, the code in `b:surface_error` and one message per
change of code in `:messages`. A later success clears it.

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
receives a deep copy of the full raw snapshot plus start/input and a `Deliver`
callback, which it calls once with a view or a bounded failure code; delivery may
come later from a job or timer. It may return a Funcref that stops that work; the
surface calls it when the request is dropped. Set opaque `surface_source`, `surface_current` and
`surface_context` as applicable. Changing an IO binding requires changing its
source marker.

Exceptions, malformed values and changed callbacks/context invalidate the result.
No same-Funcref mutable-state guarantee or remote evaluation authority is
manufactured.

The separate `packages/vim/tests/surface.vim` requires a fresh empty session and
creates temporary examples from `tests/candidates.json`:

```sh
EDITS_COMPLETION_SOURCE=/absolute/path/packages/vim/tests/candidates.json \
  LANG=C.UTF-8 TERM=xterm-256color \
  vim -Nu NONE -i NONE -n -S /absolute/path/packages/vim/tests/surface.vim
```

## Evidence limits

The root flake checks the actual product/fixture tree and installed
`edits-semcmp-package-connection` with a test-owned proposer that reads
`tests/proposals.json` and answers each partial input. Test-only transport checks
none with no evaluator call, changing sets, the exact query, numeric round-trips,
lossless records, bounded failures and origin preservation without network calls.
Equal-text and same-first-line controls keep distinct meanings and full text
readable. The same check runs the installed `edits` inside Vim's own terminal and
types real keys: a first-character request, quiet none, a changed set, preview and
back without a request, Japanese input replacing the old menu, cancel without
revival, an explicit request, exact multiline insertion with a suffix, no request
after acceptance, reread, one Undo step, accept by typing, an older slow answer
refused while the latest is asked, leaving Insert stopping the owned process,
answers dropped after current changes, a foreign keyword completion left
unrecorded, changed-context refusal, refusal when current changes while the menu
is shown, an observable failure that later clears and a never-answering proposer
stopped at the deadline with no owned process left. Controlled scores are not Jev
semantic-quality evidence, and one answer at a time is the bound, not concurrency.
Temporary preview is native and may still show reshaped multiline text; only the
accepted Working is composed exactly. IME preedit and a private vimrc are not
certified.
Human comprehension of the displayed data remains a
separate acceptance gate, including whether native wrapping makes differences readable.

Real Jev access and the two-input ranking-quality trial await a permitted
credential entry. Actual Voice integration, Human Readline acceptance, general
unit interpretation and Commit/Prove/Admit/confirmed readback remain unproved.
