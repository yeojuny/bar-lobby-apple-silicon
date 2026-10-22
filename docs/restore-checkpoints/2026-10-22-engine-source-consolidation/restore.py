"""Materialize the explicitly public part of a historical source snapshot.

Use a new destination. Local-only files and Git databases are intentionally
excluded and remain in the original backups. No existing tree is overwritten.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def relative(value):
    p=PurePosixPath(value)
    if not value or p.is_absolute() or any(x in ('..','.git') for x in p.parts) or str(p)!=value:
        raise ValueError('Invalid relative path')
    return p


def ordinary(path):
    if path.resolve()!=path or not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('Expected ordinary checkpoint file')


def load(checkpoint):
    checkpoint=checkpoint.resolve(strict=True)
    ordinary(checkpoint/'manifest.json')
    manifest=json.loads((checkpoint/'manifest.json').read_text())
    c=manifest['catalog'];p=checkpoint/relative(c['path']);ordinary(p)
    raw=p.read_bytes()
    if len(raw)!=c['bytes'] or sha(raw)!=c['sha256']:raise ValueError('Catalog checksum mismatch')
    catalog=json.loads(gzip.decompress(raw))
    lookup={}
    for pack in manifest['packs']:
        p=checkpoint/relative(pack['path']);ordinary(p);data=p.read_bytes()
        if len(data)!=pack['bytes'] or sha(data)!=pack['sha256']:raise ValueError('Pack checksum mismatch')
        with zipfile.ZipFile(p) as z:
            names=z.namelist()
            if len(names)!=len(set(names)) or set(names)!=set(pack['objects']):raise ValueError('Pack inventory mismatch')
            for name in names:
                if not re.fullmatch('[0-9a-f]{64}',name) or name in lookup:raise ValueError('Object name mismatch')
                if sha(z.read(name))!=name:raise ValueError('Object checksum mismatch')
                lookup[name]=('zip',p)
    external_root=checkpoint/'external'
    if external_root.resolve()!=external_root:raise ValueError('External input directory must not be a link')
    cache=external_root/'objects'
    if cache.resolve()!=cache:raise ValueError('Object cache must not be a link')
    cache.mkdir(exist_ok=True)
    for external in manifest.get('external',[]):
        p=checkpoint/relative(external['path']);ordinary(p);data=p.read_bytes()
        if len(data)!=external['bytes'] or sha(data)!=external['sha256']:raise ValueError('External checksum mismatch')
        if external['kind']=='raw':
            h=external['sha256']
            if h in lookup or external['objects']!={h:None}:raise ValueError('Duplicate external object')
            lookup[h]=('raw',p)
        elif external['kind']=='tar.gz':
            wanted={member:h for h,member in external['objects'].items()}
            seen=set()
            with tarfile.open(p,'r:gz') as t:
                for member in t:
                    if member.name not in wanted:continue
                    h=wanted[member.name]
                    if not member.isfile() or h in seen or h in lookup:raise ValueError('Ambiguous source member')
                    contents=t.extractfile(member).read()
                    if sha(contents)!=h:raise ValueError('Source member checksum mismatch')
                    target=cache/h
                    if os.path.lexists(target):
                        ordinary(target)
                        if sha(target.read_bytes())!=h:raise ValueError('Changed cache object')
                    else:
                        with target.open('xb') as f:f.write(contents)
                    lookup[h]=('raw',target);seen.add(h)
            if seen!=set(external['objects']):raise ValueError('Missing source members')
        else:raise ValueError('Unknown external kind')
    return manifest,catalog,lookup


def restore(checkpoint,destination,snapshot_id,selected_only=False,loaded=None):
    destination=Path(destination).absolute()
    if os.path.lexists(destination):raise ValueError('Destination must not exist')
    if not destination.parent.is_dir() or destination.parent.resolve()!=destination.parent:
        raise ValueError('Destination parent must exist without symbolic links')
    manifest,catalog,lookup=loaded or load(checkpoint)
    snapshots={s['id']:s for s in catalog['snapshots']}
    if snapshot_id not in snapshots:raise ValueError('Unknown snapshot')
    s=snapshots[snapshot_id]
    selected={e['relative'] for e in catalog['selected'] if e['snapshot']==snapshot_id}
    entries={p:e for p,e in s['entries'].items() if e['storage']=='github-pack' and (not selected_only or p in selected)}
    for p,e in entries.items():
        relative(p)
        if e['sha256'] not in lookup or not 0<=e['mode']<=0o777:raise ValueError('Unrestorable file')
    # Directory structure is source data, never executable instructions.
    directories={p:m for p,m in s['directories'].items() if p!='.'}
    for p,m in directories.items():
        relative(p)
        if not 0<=m<=0o777:raise ValueError('Invalid directory mode')
    handles={}
    try:
        destination.mkdir(mode=0o700)
        for p in sorted(directories,key=lambda x:(len(PurePosixPath(x).parts),x)):
            (destination/p).mkdir(parents=True,exist_ok=True)
        for p,e in entries.items():
            kind,pack=lookup[e['sha256']]
            if kind=='zip':
                if pack not in handles:handles[pack]=zipfile.ZipFile(pack)
                data=handles[pack].read(e['sha256'])
            else:
                ordinary(pack);data=pack.read_bytes()
            if len(data)!=e['bytes'] or sha(data)!=e['sha256']:raise ValueError('Changed payload')
            target=destination/p
            target.parent.mkdir(parents=True,exist_ok=True)
            if target.parent.resolve()!=target.parent:raise ValueError('Destination path changed')
            with target.open('xb') as f:f.write(data)
            os.chmod(target,e['mode']);os.utime(target,ns=(e['mtime_ns'],e['mtime_ns']))
            if sha(target.read_bytes())!=e['sha256']:raise ValueError('Restored content mismatch')
        for p in sorted(directories,key=lambda x:len(PurePosixPath(x).parts),reverse=True):
            os.chmod(destination/p,directories[p])
        os.chmod(destination,s['directories']['.'])
    finally:
        for z in handles.values():z.close()
    return dict(snapshot=snapshot_id,restoredFiles=len(entries),
                bytes=sum(e['bytes'] for e in entries.values()),
                retainedLocalOnly=sum(e['storage']=='local-only' for e in s['entries'].values()),
                selectedOnly=selected_only,gitDatabaseRestored=False)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--destination',type=Path,required=True)
    p.add_argument('--snapshot',required=True)
    p.add_argument('--selected-only',action='store_true')
    a=p.parse_args()
    print(json.dumps(restore(Path(__file__).parent,a.destination,a.snapshot,a.selected_only)))
