from pathlib import Path
import json,hashlib,shutil,datetime
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert not (O/'derived-cleanup-completion.json').exists()
selection=[]
for role in ['R','Combined']:
 assert read(O/role/'completion.json')['status']=='passed'
 for label in ['cpu-build','native-build','vulkan-build']:
  receipt=read(O/role/(label+'.json'));assert receipt['exitCode']==0;args=receipt['arguments'];exe=Path(args[args.index('-o')+1]);assert exe.parent==O/role and exe.is_file() and not exe.is_symlink()
  for target in [exe,Path(str(exe)+'.dSYM')]:
   if not target.exists():continue
   paths=[target] if target.is_file() else sorted(p for p in target.rglob('*') if p.is_file())
   assert all(not p.is_symlink() and p.suffix!='.md' for p in paths)
   selection.append(dict(path=str(target),files=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)) for p in paths],successfulBuildReceipt=str(O/role/(label+'.json'))))
assert len([s for s in selection if Path(s['path']).is_file()])==6
(O/'derived-cleanup-selection.json').write_text(json.dumps(dict(scope='six successful standalone test executables and their dSYMs only',roots=selection,physicalBytesMeasured=False),indent=2)+'\n')
for s in selection:
 for p in s['files']:assert sha(p['path'])==p['sha256'] and Path(p['path']).stat().st_size==p['bytes']
for s in selection:
 p=Path(s['path'])
 if p.is_dir():shutil.rmtree(p)
 else:p.unlink()
assert all(not Path(s['path']).exists() for s in selection)
result=dict(status='complete',completedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),roots=len(selection),leaves=sum(len(s['files']) for s in selection),logicalBytes=sum(p['bytes'] for s in selection for p in s['files']),physicalBytesMeasured=False,allAbsent=True,rawAppsSourceFixtureLogsMarkdownPreserved=True)
(O/'derived-cleanup-completion.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
