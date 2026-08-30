# Issue 118 Kent Beck Canon TDD contract

This directory defines the immutable RED-first merge contract for `edits#118`.

## Canon

1. Write a finite test list before product code.
2. Give each test one observable behavior and one reason to fail.
3. Run the test and observe the declared failure before implementation.
4. Add the smallest product change that makes one failing test pass.
5. Refactor only while every already-green test stays green.
6. Add no production behavior without a new observed RED test.
7. Keep the RED specification, fixtures, and assertions unchanged after the RED commit.
8. Never turn RED into Green with skip, xfail, waiver, looser assertion, deleted test, or changed expected output.
9. Keep all pre-existing repository tests Green.
10. Merge only the exact branch head whose lane suite and required parent suites are Green.

## Machine verdict

A lane is mergeable only when the runner reports:

```text
failures = 0
errors = 0
skipped = 0
expected_failures = 0
unexpected_successes = 0
missing_declared_tests = 0
spec_lock = pass
base_ancestor = pass
```

The initial RED proof is valid only when every test declared by the lane fails as an assertion, with zero errors and zero skips.
