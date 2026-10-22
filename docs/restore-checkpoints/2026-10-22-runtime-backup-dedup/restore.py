"""Restore selected duplicate files from an immutable checkpoint checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat


def check_relative(value):
    p = PurePosixPath(value)
    if p.is_absolute() or '..' in p.parts or not value.startswith('backups/runtime/'):
        raise ValueError('Not an allowed historical runtime backup path')
    return p


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def restore(checkpoint, destination, group_ids):
    checkpoint = checkpoint.resolve(strict=True)
    destination = destination.absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError('Destination must not exist; existing backups are never overwritten')
    if not destination.parent.is_dir() or destination.parent.resolve() != destination.parent:
        raise ValueError('Destination parent must exist without symbolic-link components')
    manifest = json.loads((checkpoint/'manifest.json').read_text())
    groups = [g for g in manifest['groups'] if not group_ids or g['id'] in group_ids]
    if group_ids and {g['id'] for g in groups} != set(group_ids):
        raise ValueError('Unknown group')
    # Validate every requested payload and path before creating any destination.
    plan = []
    for group in groups:
        payload = checkpoint/'payloads'/PurePosixPath(group['payload']['path']).name
        if payload.resolve() != payload or not stat.S_ISREG(payload.lstat().st_mode):
            raise ValueError('Payload must be an ordinary local file')
        if payload.stat().st_size != group['canonical']['bytes'] or digest(payload) != group['canonical']['sha256']:
            raise ValueError('Payload hash mismatch')
        for item in group['retiredCopies']:
            rel = check_relative(item['path'])
            if (item['sha256'], item['bytes']) != (group['canonical']['sha256'], group['canonical']['bytes']):
                raise ValueError('Manifest copy mismatch')
            if item['mode'] not in (0o644, 0o755):
                raise ValueError('Unsupported file mode')
            plan.append((payload, rel, item))
    destination.mkdir(mode=0o700)
    for payload, rel, item in plan:
        target = destination/rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.parent.resolve() != target.parent:
            raise ValueError('Destination path changed')
        with payload.open('rb') as source, target.open('xb') as output:
            shutil.copyfileobj(source, output, 1024 * 1024)
        os.chmod(target, item['mode'])
        os.utime(target, ns=(item['mtime_ns'], item['mtime_ns']))
        if digest(target) != item['sha256']:
            raise ValueError('Restored file mismatch')
    return len(plan)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True, help='New empty destination; its parent must exist')
    parser.add_argument('--group', action='append', default=[], help='Optional group ID; otherwise restore all selected copies')
    args = parser.parse_args()
    print(f'Restored {restore(Path(__file__).parent, args.destination, args.group)} files')
