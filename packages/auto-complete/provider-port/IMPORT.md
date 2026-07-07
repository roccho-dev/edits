# import

Target: `roccho-dev/edits/packages/auto-complete`

Apply `edits-auto-complete-provider-port.260621.zip` as an overlay to repo root.

```sh
unzip edits-auto-complete-provider-port.260621.zip
rsync -a edits-provider-overlay/ ./
rm -rf packages/auto-complete/test/__pycache__
cd packages/auto-complete
./test/run.sh
sha256sum -c files.sha256
```

Proof release values are recorded in `MANIFEST.json`.
