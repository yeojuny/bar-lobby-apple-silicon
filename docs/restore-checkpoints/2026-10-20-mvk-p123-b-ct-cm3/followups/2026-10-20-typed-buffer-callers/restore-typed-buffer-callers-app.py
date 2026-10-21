"""Verify or restore exact signed typed-buffer-callers app bytes from the frozen drawable-size app. Never run/install."""
import argparse,hashlib,json,os,pathlib,stat,subprocess,shutil
C=pathlib.Path(__file__).resolve().parent;M=json.loads((C/'app-restore.json').read_text())
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
a=argparse.ArgumentParser(description=__doc__);a.add_argument('--base-app',type=pathlib.Path,required=True);a.add_argument('--out',type=pathlib.Path,help='NEW BAR.app path; omit to verify basis/payloads only');args=a.parse_args()
base=args.base_app.resolve();verify(base,M['baseInventory'])
for f in M['changedFiles']:
 payload=C/f['payload'];assert digest(payload)==f['after']['sha256'] and stat.S_IMODE(payload.stat().st_mode)==f['after']['mode'],f['path']
if args.out:
 dest=args.out.resolve();assert not dest.exists() and not args.out.is_symlink() and not dest.is_relative_to(base),'Destination must be new and outside base app'
 if pathlib.Path('/usr/bin/ditto').exists():subprocess.run(['/usr/bin/ditto',str(base),str(dest)],check=True)
 else:shutil.copytree(base,dest,symlinks=True)
 for f in M['changedFiles']:
  target=dest/f['path'];assert not target.is_symlink();target.unlink()
  with target.open('xb') as output:output.write((C/f['payload']).read_bytes())
  target.chmod(f['after']['mode'])
 verify(dest,M['candidateInventory'])
 if pathlib.Path('/usr/bin/codesign').exists():subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(dest)],check=True)
 print('Exact signed typed-buffer-callers app restored to fresh path. No signing, launch or installation performed.')
else:print('Exact drawable-size basis and three signed payloads verified; no app copied or changed.')
