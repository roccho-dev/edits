# verify

Expected commands after applying the overlay archive to the repo root:

```sh
cd packages/auto-complete
./test/run.sh
sha256sum -c files.sha256
```

The local container rerun of `./test/run.sh` passed with 735 assertions. The checksum gate should be run against the immutable archive state, because proof result JSON contains timing fields and is updated by reruns.

Release proof values:

| check | value |
|---|---:|
| assertions | 735 |
| provider contract assertions | 38 |
| fixed red/green failures | 33 |
| rendered examples | 8 |
| live PTY passes | 20 |
| repeated full-suite passes | 3 |
| candidate build p95 | 2.952 ms |
| candidate build gate | 20 ms |
