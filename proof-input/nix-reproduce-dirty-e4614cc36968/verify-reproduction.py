#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import tarfile
from typing import Any


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def inspect(path: pathlib.Path) -> dict[str, Any]:
    with tarfile.open(path, 'r:*') as tf:
        members = tf.getmembers()
        names = [m.name for m in members]
        if 'manifest.json' not in names:
            raise SystemExit(f'{path}: manifest.json missing')
        manifest = json.load(tf.extractfile('manifest.json'))
        if not isinstance(manifest, list) or len(manifest) != 1:
            raise SystemExit(f'{path}: expected exactly one image')
        image = manifest[0]
        config_name = image['Config']
        config_bytes = tf.extractfile(config_name).read()
        config = json.loads(config_bytes)
        layers = []
        for name in image['Layers']:
            if name not in names:
                raise SystemExit(f'{path}: missing layer {name}')
            blob = tf.extractfile(name).read()
            digest = sha256_bytes(blob)
            expected_name = f'blobs/sha256/{digest}'
            if name != expected_name:
                raise SystemExit(f'{path}: layer filename/hash mismatch: {name} != {expected_name}')
            layers.append({'name': name, 'sha256': digest, 'size': len(blob)})
        for name in names:
            if name.startswith('blobs/sha256/'):
                blob = tf.extractfile(name).read()
                digest = sha256_bytes(blob)
                if name != f'blobs/sha256/{digest}':
                    raise SystemExit(f'{path}: blob filename/hash mismatch: {name}')
        chain = '\n'.join(x['sha256'] for x in layers).encode()
        rootfs_diff_ids = config['rootfs'].get('diff_ids')
        layer_manifest = '\n'.join(f"{x['name']}\t{x['size']}\t{x['sha256']}" for x in layers).encode()
        member_names = '\n'.join(names).encode()
        return {
            'artifact_sha256': sha256_file(path),
            'artifact_size': path.stat().st_size,
            'repo_tags': image['RepoTags'],
            'config_name': config_name,
            'config_digest': 'sha256:' + sha256_bytes(config_bytes),
            'image_config': {k: config['config'].get(k) for k in ['User', 'WorkingDir', 'Entrypoint', 'Cmd', 'Env']},
            'rootfs_diff_ids_sha256': sha256_bytes('\n'.join(rootfs_diff_ids).encode()),
            'rootfs_layer_chain_sha256': sha256_bytes(chain),
            'layer_manifest_sha256': sha256_bytes(layer_manifest),
            'layer_count': len(layers),
            'member_count': len(members),
            'member_names_sha256': sha256_bytes(member_names),
        }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--expected', required=True, type=pathlib.Path)
    ap.add_argument('--first', required=True, type=pathlib.Path)
    ap.add_argument('--second', required=True, type=pathlib.Path)
    ap.add_argument('--out', required=True, type=pathlib.Path)
    args = ap.parse_args()

    expected = json.loads(args.expected.read_text(encoding='utf-8'))
    first = inspect(args.first)
    second = inspect(args.second)
    checks: dict[str, bool] = {}

    for key in [
        'artifact_sha256', 'artifact_size', 'repo_tags', 'config_name',
        'config_digest', 'image_config', 'rootfs_diff_ids_sha256',
        'rootfs_layer_chain_sha256', 'layer_manifest_sha256', 'layer_count',
        'member_count', 'member_names_sha256'
    ]:
        checks[f'first.{key}'] = first[key] == expected[key]
        checks[f'second.{key}'] = second[key] == expected[key]
    checks['two_builds.byte_identical'] = first['artifact_sha256'] == second['artifact_sha256']
    checks['two_builds.rootfs_chain_identical'] = first['rootfs_layer_chain_sha256'] == second['rootfs_layer_chain_sha256']
    checks['expected.image_id'] = first['config_digest'] == 'sha256:ba3e136d7bf01f94433b91c5eebb632f70c5c25f745b5e793d735e3da393e32e'
    checks['expected.layer_count'] = first['layer_count'] == 68
    checks['expected.repo_tag'] = first['repo_tags'] == ['roccho/edits:dirty-e4614cc36968']
    checks['expected.user'] = first['image_config']['User'] == '1000:1000'
    checks['expected.working_dir'] = first['image_config']['WorkingDir'] == '/work/repos'

    passed = all(checks.values())
    verdict = {
        'schema': 'edits.nixReproductionVerdict.v1',
        'passed': passed,
        'claim': 'Nix 2.34.4 reproduced the baseline Docker archive byte-for-byte twice' if passed else 'Nix reproduction did not fully match the baseline',
        'checks': checks,
        'expected': {
            'artifact_sha256': expected['artifact_sha256'],
            'artifact_size': expected['artifact_size'],
            'image_id': expected['config_digest'],
            'layer_count': expected['layer_count'],
            'rootfs_layer_chain_sha256': expected.get('rootfs_layer_chain_sha256'),
        },
        'first': first,
        'second': second,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(verdict, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    if not passed:
        failed = [k for k, v in checks.items() if not v]
        print('FAILED checks:')
        print('\n'.join(failed))
        return 1
    print('NIX_2_34_4_BYTE_EXACT_REPRODUCTION_PASS')
    print(json.dumps({
        'artifact_sha256': first['artifact_sha256'],
        'image_id': first['config_digest'],
        'rootfs_layer_chain_sha256': first['rootfs_layer_chain_sha256'],
        'layers': first['layer_count'],
        'members': first['member_count'],
    }, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
