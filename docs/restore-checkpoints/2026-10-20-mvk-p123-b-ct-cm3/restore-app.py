"""Restore one exact experimental app from a v1.0.3 BAR.app into a NEW path. Never launch/install."""
import argparse,hashlib,json,os,pathlib,stat,subprocess,shutil
C=pathlib.Path(__file__).resolve().parent;M=json.loads((C/'app-deltas.json').read_text())
def digest(p):
 h=hashlib.sha256()
 with pathlib.Path(p).open('rb') as f:
  for b in iter(lambda:f.read(2**20),b''):h.update(b)
 return h.hexdigest()
def verify(app,inventory):
 actual=set()
 for root,dirs,files in os.walk(app,followlinks=False):
  for name in dirs+files:
   p=pathlib.Path(root)/name
   if p.is_symlink() or p.is_file():actual.add(p.relative_to(app).as_posix())
 assert actual==set(inventory),'App file/link set differs'
 for rel,v in inventory.items():
  p=app/rel
  if v['type']=='link':assert p.is_symlink() and os.readlink(p)==v['target'],rel
  else:assert p.is_file() and not p.is_symlink() and p.stat().st_size==v['bytes'] and stat.S_IMODE(p.stat().st_mode)==v['mode'] and digest(p)==v['sha256'],rel
a=argparse.ArgumentParser(description=__doc__);a.add_argument('--base-app',type=pathlib.Path,required=True);a.add_argument('--state',choices=sorted(M['states']),required=True);a.add_argument('--out',type=pathlib.Path,help='NEW BAR.app path; omit to verify basis and patches only');args=a.parse_args()
base=args.base_app.resolve();verify(base,M['baseInventory']);s=M['states'][args.state]
for change in s['changes']:assert digest(C/change['patch']['file'])==change['patch']['sha256']
if args.out:
 dest=args.out.absolute();assert not dest.exists() and not dest.is_symlink(),'Destination must not exist'
 # The supplied frozen app is never modified. A fresh copy preserves native signature bytes.
 if pathlib.Path('/usr/bin/ditto').exists():subprocess.run(['/usr/bin/ditto',str(base),str(dest)],check=True)
 else:shutil.copytree(base,dest,symlinks=True)
 zstd=shutil.which('zstd');assert zstd,'zstd is required'
 for change in s['changes']:
  target=dest/change['path'];assert not target.is_symlink()
  target.unlink()
  subprocess.run([zstd,'-q','-d','--long=29','--patch-from='+str(base/change['path']),str(C/change['patch']['file']),'-o',str(target)],check=True)
  target.chmod(change['after']['mode']);assert digest(target)==change['after']['sha256']
 verify(dest,s['inventory'])
 if pathlib.Path('/usr/bin/codesign').exists():subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(dest)],check=True)
 print('Exact experimental '+args.state+' app restored. No resign, launch or installation performed.')
else:print('Exact v1.0.3 basis and patch hashes verified. No app copied or changed.')
