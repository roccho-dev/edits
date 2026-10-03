# edits

Native Vim UI preparation for [ADRS #481](https://github.com/roccho-dev/adrs/issues/481)
and [#484](https://github.com/roccho-dev/adrs/issues/484).

The current surface reads a configured, non-authoritative
`decision-completion.view/1` fixture and projects ordered candidates into
standard Vim completion. It preserves opaque handles and uses native editing,
cancellation and Undo. Candidate generation, evaluation, admission and durable
current remain outside Vim; real shared proposals are not connected yet.

The former HQ plugins, ports, queues, workers and distribution paths have been
removed from this repository. Their source remains in Git history. This does
not modify the hq repository or existing User environments.

[Try the fixture](docs/operations/vim-nix-local-first.md).
The stock Vim definition remains pinned to 9.2.0478:

```sh
nix build ./proofs/vim-nix#vim --no-link --no-write-lock-file
nix flake check ./proofs/vim-nix --no-write-lock-file
```

The check builds that Vim and tests the current fixture's loading and ordered
display projection. It does not prove interactive Human UX or shared admission.
