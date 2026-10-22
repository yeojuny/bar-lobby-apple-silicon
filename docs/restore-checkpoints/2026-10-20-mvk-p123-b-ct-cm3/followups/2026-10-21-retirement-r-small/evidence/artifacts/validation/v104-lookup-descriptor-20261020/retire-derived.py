from pathlib import Path
import json,hashlib,shutil,os,subprocess,importlib.util
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
assert json.loads((O/'completion.json').read_text())['status']=='implementation-independent-review-diagnostics-and-performance-complete'
assert not (O/'derived-cleanup-completion.json').exists()
app=R/'artifacts/runtime/v104-lookup-descriptor-diagnostic-20261020/BAR.app';C=R/'artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py');inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv);assert inv.inventory(app)==json.loads((O/'diagnostic-inventory.json').read_text())
# Only the temporary diagnostic app and our successfully completed fixture outputs.
roots=[app]
for rel in ['validation/allocation-cpu','validation/registration-exact','validation/cost-cpu-0','validation/cost-cpu-1','gpu-validation/native-registration','gpu-validation/prepared-selected']:
 p=O/rel
 for q in [p,Path(str(p)+'.dSYM')]:
  if q.exists():roots.append(q)
for root in roots:
 assert root.resolve()==root and not root.is_symlink()
 p=subprocess.run(['/usr/sbin/lsof','-t','+D',str(root)] if root.is_dir() else ['/usr/sbin/lsof','-t',str(root)],capture_output=True,text=True,timeout=15);assert p.returncode in [0,1] and not p.stdout.strip(),(root,p.stdout)
md=[]
for p in app.rglob('*.md'):
 if not p.is_file():continue
 relative=p.relative_to(app);counterpart=C/relative;assert counterpart.is_file() and sha(counterpart)==sha(p);dst=O/'retained-markdown/diagnostic'/relative;assert not dst.exists();dst.parent.mkdir(parents=True,exist_ok=True);h=sha(p);p.rename(dst);assert sha(dst)==h;md.append(dict(oldPath=str(p),retainedPath=str(dst),sha256=h))
leaves=[]
for root in roots:
 entries=list(root.rglob('*')) if root.is_dir() else [root]
 for p in entries:
  if p.is_file() or p.is_symlink():
   assert p.suffix.lower()!='.md';s=p.lstat();leaves.append(dict(path=str(p),dev=s.st_dev,ino=s.st_ino,bytes=s.st_size))
selection=dict(roots=[str(p) for p in roots],leaves=leaves,logicalBytes=sum(x['bytes'] for x in leaves),preservedMarkdown=md,scope='Temporary diagnostic app and successful derived fixture binaries only; C/D/apps outside these exact roots, source, logs, input/error evidence and preserved raw diagnostic library remain.')
(O/'derived-cleanup-selection.json').write_text(json.dumps(selection,indent=2))
for row in leaves:
 p=Path(row['path']);s=p.lstat();assert (s.st_dev,s.st_ino,s.st_size)==(row['dev'],row['ino'],row['bytes'])
for root in roots:
 if root.is_dir():shutil.rmtree(root)
 else:root.unlink()
result=dict(rootsRemoved=len(roots),leavesRemoved=len(leaves),logicalBytesRemoved=selection['logicalBytes'],physicalBytesMeasured=False,allAbsent=all(not p.exists() for p in roots),preservedMarkdownCount=len(md),diagnosticAppRetired=str(app),rawDiagnosticLibraryRetained=str(O/'diagnostic-raw-MoltenVK.dylib'),CAndDKept=True,sourceLogsResultsAndFailureEvidencePreserved=True)
(O/'derived-cleanup-completion.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
