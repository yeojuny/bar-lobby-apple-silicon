"""Fetch and verify existing GitHub source dependencies for this checkpoint."""
import hashlib,json,os,tarfile,tempfile,urllib.request
from pathlib import Path, PurePosixPath

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def valid(path,e):
    return path.is_file() and path.resolve()==path and path.stat().st_size==e['bytes'] and digest(path)==e['sha256']

def download(url,path,e):
    if not url.startswith(('https://github.com/yeojuny/bar-lobby-apple-silicon/',
                           'https://raw.githubusercontent.com/yeojuny/bar-lobby-apple-silicon/')):
        raise ValueError('Unexpected source URL')
    h=hashlib.sha256();n=0
    with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'BAR-source-restore'}),timeout=45) as r,path.open('xb') as f:
        for b in iter(lambda:r.read(1024*1024),b''):
            n+=len(b)
            if n>e['bytes']:raise ValueError('Oversized download')
            h.update(b);f.write(b)
    if (n,h.hexdigest())!=(e['bytes'],e['sha256']):raise ValueError('Downloaded checksum mismatch')

def fetch(root):
    root=root.resolve(strict=True);m=json.loads((root/'manifest.json').read_text())
    external=root/'external'
    if external.resolve()!=external:raise ValueError('External path is a link')
    external.mkdir(exist_ok=True)
    required=[]
    for e in m['external']:
        rel=PurePosixPath(e['path'])
        if len(rel.parts)!=2 or rel.parts[0]!='external' or '..' in rel.parts:raise ValueError('Invalid dependency path')
        dest=root/rel
        if os.path.lexists(dest):
            if not valid(dest,e):raise ValueError('Existing input does not match')
        else:required.append(e)
    with tempfile.TemporaryDirectory(prefix='download-',dir=external) as tmp:
        tmp=Path(tmp)
        archive_inputs=[e for e in required if e['kind']=='tar.gz']
        if archive_inputs:
            bundle=tmp/'source-bundle.tar.gz'
            download(m['sourceBundle']['url'],bundle,m['sourceBundle'])
            wanted={e['sourceBundleMember']:e for e in archive_inputs};seen=set()
            with tarfile.open(bundle,'r:gz') as t:
                for item in t:
                    if item.name not in wanted:continue
                    e=wanted[item.name]
                    if not item.isfile() or item.name in seen or item.size!=e['bytes']:raise ValueError('Invalid source member')
                    staging=tmp/Path(e['path']).name
                    with t.extractfile(item) as source,staging.open('xb') as dest:
                        for b in iter(lambda:source.read(1024*1024),b''):dest.write(b)
                    if not valid(staging,e):raise ValueError('Source archive checksum mismatch')
                    seen.add(item.name)
            if seen!=set(wanted):raise ValueError('Missing source archives')
        for e in required:
            staging=tmp/Path(e['path']).name
            if e['kind']=='raw':download(e['url'],staging,e)
            if not valid(staging,e):raise ValueError('Unverified staged input')
            target=root/e['path']
            # Link is atomic and cannot overwrite a path created concurrently.
            os.link(staging,target);staging.unlink()
    return dict(dependencies=len(m['external']),downloaded=len(required),allChecksumsMatch=True,
                sourceBundleSHA256=m['sourceBundle']['sha256'])

if __name__=='__main__':print(json.dumps(fetch(Path(__file__).parent)))
