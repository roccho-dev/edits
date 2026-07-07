# local rerun

Command:

```sh
cd packages/auto-complete
./test/run.sh
```

Result in container: PASS, 735 assertions.

Note: `./test/run.sh` updates timing-dependent result JSON. After the rerun, `sha256sum -c files.sha256` differed for `test/proof_summary.json` and `test/window_timer_contract_result.json`. For the GitHub proposal, immutable zip hashes in `MANIFEST.json` remain the archive authority.
