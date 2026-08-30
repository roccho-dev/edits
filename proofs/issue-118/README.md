# edits#118 RED-first proof lanes

Each worktree owns one disjoint lane under this directory. The lane includes:

- `CANON.md`: human acceptance contract;
- `TEST_LIST.md`: finite behavior list;
- `canon.json`: machine merge contract;
- `tests/`: executable RED assertions;
- `SPEC.sha256`: immutable RED-spec lock.

Initial proof:

```sh
proofs/issue-118/run-lane.sh --expect-red proofs/issue-118/<lane>
```

Merge proof:

```sh
proofs/issue-118/run-lane.sh --expect-green proofs/issue-118/<lane>
```

A Green result produced through skip, xfail, waiver, deleted test, weakened assertion, or changed expected output is invalid even when the process exits zero.
