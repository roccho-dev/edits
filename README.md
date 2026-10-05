# edits

A native Vim Human surface for [ADRS #481](https://github.com/roccho-dev/adrs/issues/481),
[#484](https://github.com/roccho-dev/adrs/issues/484) and [edits #125](https://github.com/roccho-dev/edits/issues/125).

`nix build .#edits` (also the default package) installs pinned Vim, the surface,
and the pinned ops semcmp CLI with its Node/JS dependencies. No second checkout
or separate Node installation is required. Stock `#vim` remains unchanged.

Supply a proposal catalog explicitly and open your ordinary file:

```sh
EDITS_SEMCMP_CATALOG=/absolute/path/proposals.json \
  LANG=C.UTF-8 TERM=xterm-256color result/bin/edits -Nu NONE -i NONE -n notes.txt
```

The installed example is `result/share/edits/examples/proposals.json`. It is
hand-authored input, never an implicit fallback. Semcmp uses the existing
`JEV_API_KEY`, optional `JEV_API_URL` and `JEV_TIMEOUT_MS` process environment.
An artifact's capability declaration does not provide credentials; fixed
voice-ui/ops-jev launchers do not authorize arbitrary semcmp programs.

Write, use `Ctrl-X Ctrl-U`, compare with `Ctrl-N/P`, accept with `Ctrl-Y` or cancel
with `Ctrl-E`, then edit and complete again. `:SurfaceSelection` rereads what the
last accepted selection meant when it was chosen. The initial query replaces only
the current line's prefix before the cursor; the full representation is inserted
exactly, and right-hand text and other lines remain.
The caller may supply another `b:surface_query`; this example does not define
all Input types or make a semantic unit equal to a line.

Each explicit completion sends the latest full Working/current/context and
opaque input/focus to semcmp. The response must match the query and supplied
candidate identities, meaning and representation. Order is preserved; the
original Proposal and evaluation evidence remain in the opaque handle.
Selection is an unadopted Working edit, not a relation effect or Admit.

The underlying `packages/vim/surface.vim` remains independently usable with
caller-supplied buffer-local Query and Acquire Funcrefs. Importing has no IO or
buffer effects; explicitly call its `Attach()`. The installed semcmp entry
attaches the current buffer without example bootstrap or invented current.

```sh
nix flake check . --no-write-lock-file --print-build-logs
nix build .#vim --no-link --no-write-lock-file
```

The checks retain the product/fixture guards and exercise the installed
`edits-semcmp-package-connection` with test-only transport responses. They do
not prove real Jev quality, actual Voice sharing or Human UX. Real-provider
access through an authorized target-native credential entry, Human comparison,
and Commit/Prove/Admit/persistence remain separate gates.

[Operations and private composition](docs/operations/vim-nix-local-first.md).
HQ implementation/distribution dependencies are retired; Git history and
existing User environments remain intact.
