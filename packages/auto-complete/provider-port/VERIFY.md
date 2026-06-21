# verify

Expected commands after applying the overlay archive to repo root:

```sh
cd packages/auto-complete
./test/run.sh
sha256sum -c files.sha256
```

Local container rerun of `./test/run.sh` passed with 735 assertions.

Important: the rerun updates timing-dependent result JSON. After rerun, `sha256sum -c files.sha256` differed for `test/proof_summary.json` and `test/window_timer_contract_result.json`. For proposal review, immutable zip hashes in `MANIFEST.json` remain the archive authority.
