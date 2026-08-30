# Test list

1. Materialize catalog, intake, result, and view-plan adapter packages.
2. Bind one exact ops release and catalog digest.
3. Reject malformed, duplicate, orphan, and unknown operation definitions.
4. Match legacy and adapter candidate semantics in shadow mode.
5. Produce zero ops intake before explicit accept.
6. Produce exactly one ops intake for one explicit accept.
7. Start zero package executables from edits.
8. Fail closed when ops is unavailable; use no local fallback.
9. Reject stale result generations.
10. Keep provider-native references separate from canonical run identity.
11. Keep result projection read-only.
12. Read no mutable ops repository HEAD at runtime.
13. Project a newly released operation without edits source changes.
14. Produce zero effects while shadow mode is active.
