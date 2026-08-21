#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$EVIDENCE/oci-structure"
cat > "$RUNNER_TEMP/verify_oci.py" <<'PY'
from __future__ import annotations
import argparse, hashlib, io, json, pathlib, re, tarfile

SHA = re.compile(r"^sha256:([0-9a-f]{64})$")
MANIFEST = "application/vnd.oci.image.manifest.v1+json"
CONFIG = "application/vnd.oci.image.config.v1+json"
LAYERS = {
    "application/vnd.oci.image.layer.v1.tar",
    "application/vnd.oci.image.layer.v1.tar+gzip",
    "application/vnd.oci.image.layer.v1.tar+zstd",
    "application/vnd.oci.image.layer.nondistributable.v1.tar",
    "application/vnd.oci.image.layer.nondistributable.v1.tar+gzip",
    "application/vnd.oci.image.layer.nondistributable.v1.tar+zstd",
}
def digest(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def fail(msg: str): raise SystemExit("verify-oci: " + msg)
def load(path: pathlib.Path):
    files = {}
    with tarfile.open(path, "r:*") as tf:
        for m in tf.getmembers():
            name = m.name.removeprefix("./")
            parts = pathlib.PurePosixPath(name).parts
            if not name or name.startswith("/") or any(p in {"", ".", ".."} for p in parts): fail(f"unsafe entry {m.name!r}")
            if m.isdir(): continue
            if not m.isfile(): fail(f"non-regular entry {m.name!r}")
            if name in files: fail(f"duplicate entry {name}")
            stream = tf.extractfile(m)
            if stream is None: fail(f"unreadable entry {name}")
            files[name] = stream.read()
    return files
def js(files, name):
    if name not in files: fail(f"missing {name}")
    try: return json.loads(files[name])
    except Exception as exc: fail(f"invalid JSON {name}: {exc}")
def blob(files, desc, role):
    if not isinstance(desc, dict): fail(f"{role} descriptor is not object")
    match = SHA.fullmatch(str(desc.get("digest", "")))
    size = desc.get("size")
    if not match or not isinstance(size, int) or size < 0: fail(f"invalid {role} descriptor")
    name = "blobs/sha256/" + match.group(1)
    if name not in files: fail(f"missing {role} blob")
    data = files[name]
    if len(data) != size or digest(data) != match.group(1): fail(f"{role} size/digest mismatch")
    return desc["digest"], data
def verify(path, expected_revision):
    raw = path.read_bytes(); files = load(path)
    if js(files, "oci-layout") != {"imageLayoutVersion":"1.0.0"}: fail("bad layout")
    index = js(files, "index.json")
    manifests = index.get("manifests") if isinstance(index, dict) else None
    if index.get("schemaVersion") != 2 or not isinstance(manifests, list) or len(manifests) != 1: fail("bad index")
    md = manifests[0]
    if md.get("mediaType") != MANIFEST: fail("bad manifest media type")
    manifest_digest, manifest_raw = blob(files, md, "manifest")
    manifest = json.loads(manifest_raw)
    if manifest.get("schemaVersion") != 2 or manifest.get("mediaType") != MANIFEST: fail("bad manifest")
    cd = manifest.get("config")
    if not isinstance(cd, dict) or cd.get("mediaType") != CONFIG: fail("bad config descriptor")
    config_digest, config_raw = blob(files, cd, "config")
    config = json.loads(config_raw)
    if config.get("os") != "linux" or config.get("architecture") != "amd64": fail("bad platform")
    runtime = config.get("config")
    if not isinstance(runtime, dict): fail("missing runtime config")
    entry = runtime.get("Entrypoint")
    cmd = runtime.get("Cmd")
    labels = runtime.get("Labels")
    if not isinstance(entry, list) or len(entry) != 3 or not entry[0].endswith("/bin/run-vim-nix-proof") or entry[1] != "--proof-root" or entry[2] != entry[0].removesuffix("/bin/run-vim-nix-proof"): fail(f"bad entrypoint {entry!r}")
    if cmd != ["--mode","image","--output","/evidence"]: fail(f"bad cmd {cmd!r}")
    if not isinstance(labels, dict) or labels.get("org.opencontainers.image.revision") != expected_revision: fail("revision mismatch")
    rows=[]
    layers=manifest.get("layers")
    if not isinstance(layers, list) or not layers: fail("no layers")
    for i, layer in enumerate(layers):
        if not isinstance(layer, dict) or layer.get("mediaType") not in LAYERS: fail(f"bad layer {i}")
        d,b=blob(files, layer, f"layer[{i}]")
        rows.append({"index":i,"digest":d,"bytes":len(b),"mediaType":layer["mediaType"]})
    expected={"oci-layout","index.json",f"blobs/sha256/{manifest_digest[7:]}",f"blobs/sha256/{config_digest[7:]}",*[f"blobs/sha256/{r['digest'][7:]}" for r in rows]}
    if set(files) != expected: fail(f"unexpected files {sorted(set(files)-expected)}")
    return {"schema":"edits.vimNixHerdrHq.ociVerification/1","status":"PASS","archive":{"bytes":len(raw),"sha256":digest(raw),"entries":len(files)},"indexSha256":digest(files["index.json"]),"manifestDigest":manifest_digest,"configDigest":config_digest,"layers":rows,"platform":"linux/amd64","entrypoint":entry,"cmd":cmd,"labels":labels}
ap=argparse.ArgumentParser(); ap.add_argument("archive",type=pathlib.Path); ap.add_argument("--revision",required=True); ap.add_argument("--receipt",type=pathlib.Path)
ns=ap.parse_args(); result=verify(ns.archive,ns.revision); encoded=json.dumps(result,indent=2,sort_keys=True)+"\n"
if ns.receipt: ns.receipt.write_text(encoded)
print(encoded,end="")
PY

python3 "$RUNNER_TEMP/verify_oci.py" "$DIST/vim-nix-herdr-hq.oci.tar" \
  --revision "$EXACT_BASE" --receipt "$EVIDENCE/oci-structure/receipt.json"
if python3 "$RUNNER_TEMP/verify_oci.py" "$DIST/vim-nix-herdr-hq.oci.tar" \
    --revision 0000000000000000000000000000000000000000 >/dev/null 2>&1; then
  echo 'wrong OCI revision unexpectedly passed' >&2; exit 1
fi
python3 - "$DIST/vim-nix-herdr-hq.oci.tar" "$RUNNER_TEMP/tampered.oci.tar" <<'PY'
import io, pathlib, tarfile, sys
src,dst=map(pathlib.Path,sys.argv[1:]); changed=False
with tarfile.open(src,"r:*") as r, tarfile.open(dst,"w") as w:
    for member in r.getmembers():
        if member.isdir(): w.addfile(member); continue
        stream=r.extractfile(member); data=stream.read() if stream else b""
        name=member.name.removeprefix("./")
        if not changed and name.startswith("blobs/sha256/"):
            data=bytes([data[0]^1])+data[1:]; changed=True
        member.size=len(data); w.addfile(member,io.BytesIO(data))
if not changed: raise SystemExit("no blob mutated")
PY
if python3 "$RUNNER_TEMP/verify_oci.py" "$RUNNER_TEMP/tampered.oci.tar" \
    --revision "$EXACT_BASE" >/dev/null 2>&1; then
  echo 'tampered OCI unexpectedly passed' >&2; exit 1
fi
jq -n '{wrongRevisionRejected:true,tamperedBlobRejected:true}' \
  > "$EVIDENCE/oci-structure/negative-controls.json"
echo "manifest_digest=$(jq -r .manifestDigest "$EVIDENCE/oci-structure/receipt.json")" >> "$GITHUB_OUTPUT"
echo "config_digest=$(jq -r .configDigest "$EVIDENCE/oci-structure/receipt.json")" >> "$GITHUB_OUTPUT"
