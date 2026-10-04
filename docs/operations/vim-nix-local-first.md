# Native Decision Completion

The product module `packages/vim/surface.vim` attaches the current buffer,
including an existing named, modified or multiline buffer. Importing alone has
no buffer or IO effects. Call `Attach()` explicitly; repeating it replaces only
this surface's buffer-local completion hook and preserves the last selection.

The caller sets these buffer-local values:

- `surface_query`: Funcref receiving a deep copy of the full raw Working snapshot.
  Return exactly `{start, input}`. Start is a zero-based byte boundary on the
  cursor's line, at or before the cursor. Input is opaque caller material; a
  semantic unit may span lines and is not interpreted by Vim.
- `surface_acquire`: synchronous Funcref receiving a deep copy of the raw snapshot
  with start/input. Return the private ordered display view.
- `surface_source`, `surface_current`, `surface_context`: opaque binding and
  read context. Change the source marker when changing an IO binding.

The raw snapshot contains all Working lines, buffer/tick and cursor line/column.
Native completion may temporarily remove the typed span before acquisition.
That intermediate text is checked separately and never substituted for the raw
evaluation input. Each findstart capture is consumed once. Exceptions, malformed
queries/views and changed callbacks/context invalidate the result, keep Human
edits and retain the last selection's original handle/base. These guards do not
prove remote evaluation, CAS or immutability inside the same Funcref.

The view is `{schema: "decision-completion.view/1", contexts: [{current, context,
items}]}`. Ordered items are `{handle, label, provenance, text: string[]}`.
Handle stays opaque; label/provenance/text are display data. Text is inserted by
native completion, not applied as a semantic operation. The accepted native
selection is observed in `b:surface_selection`; its base is the raw query input.
Preview and cancellation do not create a new selection or erase the prior origin.

## Owned fixture

The separate `packages/vim/tests/surface.vim` bootstrap reads the configured JSON
and creates temporary example buffers. It requires a fresh, empty Vim session:

```sh
EDITS_COMPLETION_SOURCE=/actual/path/packages/vim/tests/candidates.json \
  LANG=C.UTF-8 TERM=xterm-256color \
  vim -Nu NONE -i NONE -n -S /actual/path/packages/vim/tests/surface.vim
```

Use `i`, `Ctrl-X Ctrl-U`, `Ctrl-N/P`, then `Ctrl-Y` to accept or `Ctrl-E` to
cancel. Use `Esc`, then `:bnext` for the other context. `:write` saves only the
temporary example file. A native cancellation can leave a text-neutral Undo step;
one `u` reverses that step and a second reverses the preceding edit.

The fixture uses cursor insertion and hand-authored candidates. Alphabet span
rules, candidate generation, ranking and arbitrary typed meaning are not product
defaults. The exact native TTY tests and isolated Nix integration prove bounded
mechanics; Human Readline UX, shared Voice/Jev candidates and explicit
Commit/Prove/Admit/persistence remain separate gates.
