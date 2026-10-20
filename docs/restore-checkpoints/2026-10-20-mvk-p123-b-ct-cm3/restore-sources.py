"""Verify frozen source basis; optionally export sources into a NEW destination. No build/run."""
import argparse, hashlib, io, json, pathlib, posixpath, tarfile
C=pathlib.Path(__file__).resolve().parent
M=json.loads((C/'manifest.json').read_text())
def digest(p):
 h=hashlib.sha256()
 with pathlib.Path(p).open('rb') as f:
  for b in iter(lambda:f.read(2**20),b''):h.update(b)
 return h.hexdigest()
def safe_members(archive, root):
 for m in archive.getmembers():
  n=posixpath.normpath(m.name)
  if m.name.startswith('/') or not (n==root or n.startswith(root+'/')):raise ValueError(m.name)
  if not (m.isfile() or m.isdir() or m.issym() or m.islnk()):raise ValueError(m.name)
  if m.issym() or m.islnk():
   target=posixpath.normpath(posixpath.join(posixpath.dirname(n),m.linkname) if m.issym() else m.linkname)
   if m.linkname.startswith('/') or not (target==root or target.startswith(root+'/')):raise ValueError((m.name,m.linkname))
 return archive.getmembers()
a=argparse.ArgumentParser(description=__doc__);a.add_argument('--wrapper',type=pathlib.Path,required=True);a.add_argument('--state',choices=['parent-ab','descriptor'],default='descriptor');a.add_argument('--out',type=pathlib.Path,help='NEW output directory; omit to verify only');args=a.parse_args()
assert digest(args.wrapper)==M['sourceCompanion']['sha256'],'Wrong source wrapper'
if args.out:
 assert not args.out.exists(),'Destination must not exist'
 args.out.mkdir(parents=True)
with tarfile.open(args.wrapper) as outer:
 for lane,c in M['components'].items():
  raw=outer.extractfile('BAR-1.0.3-sources/'+c['archiveMember']).read()
  assert hashlib.sha256(raw).hexdigest()==c['archiveSHA256'],lane
  with tarfile.open(fileobj=io.BytesIO(raw)) as inner:
   validated_members=safe_members(inner,c['archiveRoot'])
   for f in c['files']:
    b=inner.extractfile(c['archiveRoot']+'/'+f['path']).read()
    assert hashlib.sha256(b).hexdigest()==f['beforeSHA256'],f['path']
    assert digest(C/'postimages'/lane/f['path'])==f['afterSHA256'],f['path']
   if args.out:
    target=args.out/lane;target.mkdir()
    inner.extractall(target,members=validated_members)
    root=target/c['archiveRoot']
    for f in c['files']:
     dest=root/f['path'];assert not dest.is_symlink()
     parent_preimage=args.state=='parent-ab' and lane=='moltenvk' and not f['path'].endswith('/MVKCmdDraw.mm')
     src=C/('preimages' if parent_preimage else 'postimages')/lane/f['path']
     dest.write_bytes(src.read_bytes());dest.chmod(f['mode'])
     assert digest(dest)==f['beforeSHA256' if parent_preimage else 'afterSHA256']
  print(lane+': frozen basis and '+str(len(c['files']))+' exact postimages verified')
print('Sources exported; no configure/build/game was run.' if args.out else 'Verification only; no sources extracted or changed.')
