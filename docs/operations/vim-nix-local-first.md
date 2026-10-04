# Native Decision Completion fixture

This example projects an ordered `decision-completion.view/1` fixture into
Vim's native completion. Candidate handles stay opaque; label, short provenance
and insertion text are display data, not semantic authority.

From a fresh Vim session, use the actual paths of these files:

```sh
EDITS_COMPLETION_SOURCE=/path/to/candidates.json LANG=C.UTF-8 TERM=xterm-256color \
  vim -Nu NONE -i NONE -n -S /path/to/surface.vim
```

Use `i`, `Ctrl-X Ctrl-U`, `Ctrl-N/P`, then `Ctrl-Y` to accept the selection or
`Ctrl-E` to cancel. Use `Esc`, then `:bnext` to switch fixture contexts.
`:write` saves only a temporary example file. Native completion cancellation
can leave a text-neutral Undo step: one `u` reverses that step, a second reverses
the preceding edit.

The preceding UI and unchanged fixture were independently verified in native TTY
controls and launched through Noctty into the running OCI on 2026-10-03. That checkpoint
does not guarantee a later OCI's setup or prove the whole visible Human UX.

An owned buffer may set `b:surface_acquire` to an acquisition Funcref. Each explicit
completion passes it a deep copy of the latest Working, opaque context/current
and local buffer/source snapshot. The function returns the same display view;
an unset function uses the file above. Invalid settings, exceptions and invalid
views do not fall back. Acquisition changes invalidate the active result while
preserving Working and the last selection's original handle/base. This private
composition boundary is not a shared owner's public wire or proof of evaluation.

The Nix check tests loading, input delivery, failure preservation and ordered
projection with a controlled acquisition function. Real shared proposals,
admission and durable saving remain separate gates under
[ADRS #481](https://github.com/roccho-dev/adrs/issues/481) and
[#484](https://github.com/roccho-dev/adrs/issues/484).
