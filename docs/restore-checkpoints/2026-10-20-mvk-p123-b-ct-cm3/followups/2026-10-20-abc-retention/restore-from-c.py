"""Recover A/B from retained C and immutable GitHub payloads, to a fresh output only."""
import argparse,copy,hashlib,json,os,pathlib,shutil,stat,subprocess
HERE=pathlib.Path(__file__).resolve().parent
def digest(p):
 h=hashlib.sha256()
 with pathlib.Path(p).open('rb') as f:
  for b in iter(lambda:f.read(2**20),b''):h.update(b)
 return h.hexdigest()
def normalize(d):
 return {k:({'type':'link','target':v['target'],'mode':v['mode']} if v['type']=='link' else {'type':'file','sha256':v['sha256'],'bytes':v.get('bytes',v.get('size')),'mode':v['mode']}) for k,v in d.items()}
def inventory(app):
 result={}
 for root,dirs,files in os.walk(app,followlinks=False):
  for n in dirs+files:
   p=pathlib.Path(root)/n;rel=p.relative_to(app).as_posix()
   if p.is_symlink():result[rel]={'type':'link','target':os.readlink(p),'mode':stat.S_IMODE(p.lstat().st_mode)}
   elif p.is_file():result[rel]={'type':'file','sha256':digest(p),'bytes':p.stat().st_size,'mode':stat.S_IMODE(p.stat().st_mode)}
 return result
def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--base-app',type=pathlib.Path,required=True);a.add_argument('--target',choices=['A','B'],required=True);a.add_argument('--out',type=pathlib.Path,help='NONEXISTENT output BAR.app; omit for virtual verification only');args=a.parse_args()
 manifest=json.loads((HERE/'rollback-manifest.json').read_text());base=args.base_app.resolve();dest=args.out.resolve() if args.out else None
 if dest:assert not dest.exists() and not args.out.is_symlink() and not dest.is_relative_to(base) and not base.is_relative_to(dest),'Output must be new and separate from retained C'
 assert pathlib.Path('/usr/bin/codesign').is_file() and pathlib.Path('/usr/bin/ditto').is_file(),'Exact signed macOS app restoration requires macOS'
 expected=normalize(json.loads((HERE/manifest['baseInventory']).read_text()));actual=inventory(base)
 assert len(actual)==1194 and actual==expected,'Retained C does not match required exact inventory'
 subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(base)],check=True)
 state=manifest['targets'][args.target];target=normalize(json.loads((HERE/state['inventory']).read_text()));data={}
 for change in state['overlay']:
  p=manifest['payloads'][change['payloadKey']]
  if change['payloadKey'] not in data:
   if p['storage']=='this-checkpoint':
    f=HERE/p['localPath'];assert f.is_file() and not f.is_symlink() and stat.S_IMODE(f.stat().st_mode)==p['mode'],'Check out full immutable checkpoint including payloads'
    b=f.read_bytes()
   else:
    assert p['url'].startswith('https://raw.githubusercontent.com/yeojuny/bar-lobby-apple-silicon/'+p['commit']+'/')
    r=subprocess.run(['/usr/bin/curl','--disable','--fail','--location','--silent','--show-error','--connect-timeout','15','--max-time','180','--url',p['url']],capture_output=True,timeout=190)
    assert r.returncode==0,r.stderr.decode(errors='replace');b=r.stdout
   assert len(b)==p['bytes'] and hashlib.sha256(b).hexdigest()==p['sha256']
   assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==p['gitBlobSHA1']
   data[change['payloadKey']]=b
  assert actual[change['path']]==change['before']
 virtual=copy.deepcopy(actual)
 for change in state['overlay']:virtual[change['path']]=change['after']
 assert len(virtual)==1194 and virtual==target,'Overlay does not produce the complete exact target inventory'
 if not dest:
  print('C basis, all immutable rollback payload bytes and virtual '+args.target+' inventory1194 exact. No app copy or change.');return
 subprocess.run(['/usr/bin/ditto',str(base),str(dest)],check=True)
 for change in state['overlay']:
  out=dest/change['path'];assert not out.is_symlink() and out.resolve().is_relative_to(dest)
  out.unlink()
  with out.open('xb') as f:f.write(data[change['payloadKey']])
  out.chmod(change['after']['mode'])
 assert inventory(dest)==target,'Restored file bytes/modes/link targets differ'
 subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(dest)],check=True)
 assert inventory(base)==expected,'Retained C changed unexpectedly'
 print('Exact signed '+args.target+' restored to fresh path. C untouched; no sign, launch or installation.')
if __name__=='__main__':main()
