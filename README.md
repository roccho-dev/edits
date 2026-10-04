# edits

A native Vim Human surface for [ADRS #481](https://github.com/roccho-dev/adrs/issues/481),
[#484](https://github.com/roccho-dev/adrs/issues/484) and [edits #125](https://github.com/roccho-dev/edits/issues/125).

Import `packages/vim/surface.vim` and explicitly attach the current buffer.
Importing does not read IO, create buffers or change text. In a legacy Vim script:

```vim
import "/actual/path/packages/vim/surface.vim" as surface
" Set b:surface_query, b:surface_acquire, b:surface_source,
" b:surface_current and b:surface_context in this buffer first.
call s:surface.Attach()
```

In Vim9script use `surface.Attach()`. Query and acquisition are buffer-local
Funcrefs, supplied by the caller. Query receives the full pre-completion Working
snapshot and returns `{start, input}`: a UTF-8 byte boundary before the cursor,
and opaque input material. Acquisition receives that raw snapshot plus start/input.
The surface separately checks native completion's temporary text removal and
changes during callbacks. It preserves candidate order and opaque handles.
The current private display view is `decision-completion.view/1`; it is not a
shared owner's public wire. Neither callback's internal mutable state nor a
remote owner's evaluation guarantees are established by these local guards.

Use native completion, editing, cancellation and Undo. Selection changes
unadopted Working and records the original handle/raw input; it does not admit
meaning or execute a shared action. Candidate generation, evaluation, ranking,
semantic application, admission and confirmed current remain external.
The public shared acquisition connection and whole Human UX are still TODO.

[Run the owned fixture and see the private composition contract](docs/operations/vim-nix-local-first.md).
The former HQ implementation and distribution dependencies are retired;
Git history and existing User environments remain intact.

```sh
nix build ./proofs/vim-nix#vim --no-link --no-write-lock-file
nix flake check ./proofs/vim-nix --no-write-lock-file
```

Stock Vim remains pinned to 9.2.0478. The check exercises the actual product and
fixture tree's loading, snapshot delivery, guards and projection. Headless
integration is separate from native TTY selection and Human evaluation.
