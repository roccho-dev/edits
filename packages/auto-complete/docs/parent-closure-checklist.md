# #37 parent closure checklist

#37 must remain open until each blocking child is closed by merged PR evidence or explicitly moved to a documented non-blocking follow-up.

## Blocking children

- [ ] #39 post-merge CI verification
- [ ] #40 Go import graph boundary check
- [ ] #41 provider port contract tests for all source adapters
- [ ] #42 hq-source-jsonl real fixture gate
- [ ] #43 negative fixtures for source adapters
- [ ] #44 canonical snapshots for candidate and LSP outputs
- [ ] #45 UX visual artifact snapshot audit
- [ ] #46 source adapter performance and large fixture budget
- [ ] #47 old path absence and migration guard
- [ ] #48 parent closure checklist

## Final comment required on #37

The final #37 closure comment must include:

- merged PR list
- post-merge workflow run id and conclusion
- hq-source fixture result
- provider contract result
- negative fixture result
- candidate/LSP snapshot result
- UX visual snapshot result
- performance budget result
- old-path/import boundary result

## Re-close rule

Do not re-close #37 until the final post-merge workflow on `proposals` is green and this checklist has been posted back to #37 with concrete run evidence.
