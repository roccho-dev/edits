# edits

A native Vim Human surface for [ADRS #481](https://github.com/roccho-dev/adrs/issues/481),
[#484](https://github.com/roccho-dev/adrs/issues/484) and [edits #125](https://github.com/roccho-dev/edits/issues/125).

`nix build .#edits` (also the default package) installs pinned Vim, the surface,
and the pinned ops semcmp CLI with its Node/JS dependencies. No second checkout
or separate Node installation is required. Stock `#vim` remains unchanged.

Configure the proposal owner explicitly and open your ordinary file:

```sh
EDITS_SEMCMP_PROPOSER=/absolute/path/proposer.mjs \
  LANG=C.UTF-8 TERM=xterm-256color result/bin/edits -Nu NONE -i NONE -n notes.txt
```

The module exports `propose(query)` for semcmp's `--propose` entry; edits ships
no proposer, catalog or fallback. Semcmp uses the existing `JEV_API_KEY`, optional
`JEV_API_URL` and `JEV_TIMEOUT_MS` process environment. An artifact's capability
declaration does not provide credentials; fixed voice-ui/ops-jev launchers do not
authorize arbitrary semcmp programs.

Just write. From the first typed character, each Human edit in Insert mode asks
semcmp in the background; typing never waits. When the latest answer still
matches the text, it appears as the native completion menu; no answer stays quiet.
Compare with `Ctrl-N/P`, accept with `Ctrl-Y` or by typing on, cancel with
`Ctrl-E`, then keep editing. `Ctrl-X Ctrl-U` asks again explicitly through the
same path. `:SurfaceSelection` rereads what the last accepted selection meant when
it was chosen. The initial query replaces only the current line's prefix before
the cursor; the full representation is inserted exactly, and right-hand text and
other lines remain. The caller may supply another `b:surface_query`; this example
does not define all Input types or make a semantic unit equal to a line.

Each request sends the latest full Working/current/context and opaque input/focus
to semcmp. Only the answer to the newest unchanged request is shown, and only
while no other menu or preview is active. Order is preserved; the original
Proposal and evaluation evidence remain in the opaque handle. Selection is an
unadopted Working edit, not a relation effect or Admit.

The underlying `packages/vim/surface.vim` remains independently usable with
caller-supplied buffer-local Query and Acquire Funcrefs. Importing has no IO or
buffer effects; explicitly call its `Attach()`. The installed semcmp entry
attaches the current buffer without example bootstrap or invented current.

```sh
nix flake check . --no-write-lock-file --print-build-logs
nix build .#vim --no-link --no-write-lock-file
```

The checks retain the product/fixture guards and exercise the installed
`edits-semcmp-package-connection` with a test-owned proposer and test-only
transport, including real typing in a terminal. They do not prove real Jev
quality, actual Voice sharing or Human UX. Real-provider
access through an authorized target-native credential entry, Human comparison,
and Commit/Prove/Admit/persistence remain separate gates.

[Operations and private composition](docs/operations/vim-nix-local-first.md).
HQ implementation/distribution dependencies are retired; Git history and
existing User environments remain intact.
