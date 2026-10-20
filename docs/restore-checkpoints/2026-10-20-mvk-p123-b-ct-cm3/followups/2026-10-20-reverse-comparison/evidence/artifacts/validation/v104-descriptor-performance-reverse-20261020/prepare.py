from pathlib import Path
import json,hashlib,shutil,subprocess,importlib.util
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
OLD=R/'artifacts/validation/v104-descriptor-performance-comparison-20261020'
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
 with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(OLD/'preparation.json')
for name in ('controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','sdl-hidden-preflight.json','protected-inputs.json','parent-inventory.json','candidate-inventory.json','run-comparison.py'):
 shutil.copy2(OLD/name,O/name)
shutil.copytree(OLD/'inputs',O/'inputs')
auth=read(OLD/'authorization.json');auth.update(user='다시 해봐 순서 바꿔서. 기존 전원 연결·절전모드·동일 설정과 실험 캐시 정리 및 MVK GitHub 복원 보존 요청 유지.',order='candidate,parent,parent,candidate within Metal3 then Metal4',previousEvidence=str(OLD),maximumGameSessions=8,retry=False)
save(O/'authorization.json',auth)
spec=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for label in ('parent','candidate'):assert m.inventory(Path(prep[label]))==read(O/(label+'-inventory.json'))
for entry in read(O/'protected-inputs.json')['userState'].values():assert sha(entry['path'])==entry['sha256']
plans=[]
for ordinal,(backend,role) in enumerate(((b,r) for b in ('metal3','metal4') for r in ('candidate','parent','parent','candidate')),1):
 old=next(x for x in prep['plans'] if x['role']==role and x['backend']==backend)
 folder=O/f'{ordinal}-{role}-{backend}';folder.mkdir();schema=f'v104-descriptor-reverse-{ordinal}-{role}-{backend}-v1'
 def adapt(s):return s.replace(old['folder'],str(folder)).replace(str(OLD),str(O)).replace(old['schema'],schema)
 plan=json.loads(adapt(Path(old['plan']['path']).read_text()))
 plan.update(testIdentity=folder.name,authorization=pin(O/'authorization.json'))
 hostfile=folder/'effective-host.mjs';hostfile.write_text(adapt(Path(old['host']['path']).read_text()))
 assert str(folder) in hostfile.read_text() and "plan.schema!=="+repr(schema) in hostfile.read_text()
 # Re-pin all path/hash pairs; rebased files are exact copies except authorized paths/schema.
 def repin(v):
  if isinstance(v,list):return [repin(x) for x in v]
  if isinstance(v,dict):
   d={k:repin(x) for k,x in v.items()}
   if 'path' in d and 'sha256' in d:d['sha256']=sha(d['path'])
   return d
  return v
 plan=repin(plan);planfile=folder/'plan.json';save(planfile,plan)
 subprocess.run(['/opt/homebrew/bin/node','--check',str(hostfile)],check=True,capture_output=True)
 plans.append({'ordinal':ordinal,'role':role,'backend':backend,'folder':str(folder),'schema':schema,'plan':pin(planfile),'host':pin(hostfile)})
for name in ('benchmark-bootstrap.cjs','metal-bootstrap.cjs'):subprocess.run(['/opt/homebrew/bin/node','--check',str(O/name)],check=True,capture_output=True)
assert sha(O/'controller.lua')==sha(OLD/'controller.lua')
save(O/'preparation.json',{**prep,'plans':plans,'previousEvidence':str(OLD),'order':'candidate,parent,parent,candidate for each backend','hostChanges':'Only fixture paths/schema/test identity; actual app variants and measurement logic unchanged'})
spec=importlib.util.spec_from_file_location('screen',R/'tools/r92-benchmark-screen-guard.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0};desktop=screen.desktop();assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(O/'preflight.json',{'power':screen.power(),'desktop':desktop,'existingScreenIdle':screen.idle(),'syntaxChecks':10,'appInventoriesVerified':True,'newPremeasurementDeletion':False,'priorCachesAlreadyRetired':True,'sourceOrProductChanges':False})
print('Prepared reverse-order 8 arms; app inventory, power, desktop and syntax checks passed.',flush=True)
