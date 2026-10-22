#!/usr/bin/env python3
"""Verify a retained R/Small app and restore one historical app to a fresh path."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import urllib.parse
import urllib.request


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()


def inventory(app):
    result = {}
    for folder, dirs, files in os.walk(app, followlinks=False):
        for name in dirs + files:
            p = Path(folder) / name
            s = p.lstat()
            key = p.relative_to(app).as_posix()
            if stat.S_ISLNK(s.st_mode):
                result[key] = dict(type='link', target=os.readlink(p), mode=stat.S_IMODE(s.st_mode))
            elif stat.S_ISREG(s.st_mode):
                result[key] = dict(type='file', sha256=digest(p), bytes=s.st_size, mode=stat.S_IMODE(s.st_mode))
    return result


def checked_relative(root, value):
    rel = Path(value)
    if rel.is_absolute() or '..' in rel.parts:
        raise ValueError('Invalid relative path in checkpoint')
    return root / rel


def read_json(path):
    return json.loads(path.read_text())


def payload(checkpoint, manifest, key, temp):
    p = manifest['payloads'][key]
    if p['storage'] == 'this-checkpoint':
        source = checked_relative(checkpoint, p['localPath'])
    elif p['storage'] == 'existing-immutable-blob':
        commit = p['commit']
        if len(commit) != 40 or any(c not in '0123456789abcdef' for c in commit):
            raise ValueError('Unpinned reused payload')
        url = 'https://raw.githubusercontent.com/' + manifest['repository'] + '/' + commit + '/' + urllib.parse.quote(p['repositoryPath'])
        source = temp / key
        request = urllib.request.Request(url, headers={'User-Agent': 'BAR-exact-app-restore'})
        with urllib.request.urlopen(request, timeout=90) as response, source.open('xb') as out:
            shutil.copyfileobj(response, out)
    else:
        raise ValueError('Unknown payload storage')
    if source.stat().st_size != p['bytes'] or digest(source) != p['sha256']:
        raise ValueError('Payload bytes do not match checkpoint: ' + key)
    h = hashlib.sha1(b'blob ' + str(p['bytes']).encode() + b'\0')
    with source.open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    if h.hexdigest() != p['gitBlobSHA1']:
        raise ValueError('Payload Git blob mismatch: ' + key)
    return source


def main():
    checkpoint = Path(__file__).resolve().parent
    manifest = read_json(checkpoint / 'app-restore-manifest.json')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-app', type=Path, required=True)
    parser.add_argument('--base-role', choices=sorted(manifest['baseApps']), required=True)
    parser.add_argument('--target', choices=sorted(manifest['targets']), required=True)
    parser.add_argument('--out', type=Path, help='Nonexistent output app; omit for virtual verification only')
    args = parser.parse_args()
    base = args.base_app.resolve(strict=True)
    base_spec = manifest['baseApps'][args.base_role]
    expected_base = read_json(checked_relative(checkpoint, base_spec['inventory']))
    actual_base = inventory(base)
    if actual_base != expected_base:
        raise ValueError('Base app is not the exact retained ' + args.base_role + ' inventory')
    target_spec = manifest['targets'][args.target]
    target = read_json(checked_relative(checkpoint, target_spec['inventory']))
    changes = target_spec['from'][args.base_role]['overlay']
    virtual = dict(actual_base)
    for change in changes:
        if virtual.get(change['path']) != change['before']:
            raise ValueError('Overlay preimage mismatch')
        virtual[change['path']] = change['after']
    if virtual != target or len(target) != 1194:
        raise ValueError('Virtual target is not the exact historical inventory')
    output = None
    if args.out is not None:
        output = args.out.absolute()
        if output.exists() or output.is_symlink():
            raise FileExistsError('Output must not already exist')
        output = output.parent.resolve(strict=True) / output.name
        resolved = output.resolve()
        if resolved == base or base in resolved.parents or resolved in base.parents:
            raise ValueError('Output must be separate from the base app')
    with tempfile.TemporaryDirectory(prefix='bar-exact-restore-') as folder:
        temp = Path(folder)
        data = {key: payload(checkpoint, manifest, key, temp)
                for key in sorted({c['payloadKey'] for c in changes if 'payloadKey' in c})}
        if output is not None:
            shutil.copytree(base, output, symlinks=True)
            for change in changes:
                destination = checked_relative(output, change['path'])
                if destination.parent.resolve() != destination.parent:
                    raise ValueError('Overlay cannot traverse a directory symlink')
                value = change['after']
                if value['type'] == 'link':
                    destination.unlink()
                    destination.symlink_to(value['target'])
                    if hasattr(os, 'lchmod'):
                        os.lchmod(destination, value['mode'])
                else:
                    if destination.is_symlink():
                        destination.unlink()
                    shutil.copyfile(data[change['payloadKey']], destination)
                    destination.chmod(value['mode'])
            if inventory(output) != target:
                raise ValueError('Output inventory differs; retain it for inspection')
            subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(output)], check=True)
    print(json.dumps({'target': args.target, 'baseRole': args.base_role, 'entries': 1194,
                      'virtualExact': True, 'outputCreated': output is not None,
                      'baseModified': False, 'signedOrLaunchedOrInstalled': False}, indent=2))


if __name__ == '__main__':
    main()
