# proof: vim

Vim proof keeps the current behavior frozen while internals move to Go/LSP.

Current CI command:

```sh
bash test/run.sh
python3 test/golden_check.py
```

The proof checks the current golden behavior:

- `houji` includes normal and Japanese candidates
- normal candidate priority is preserved
- `houjinb` reaches `法人売却`
- the summary reports PASS
