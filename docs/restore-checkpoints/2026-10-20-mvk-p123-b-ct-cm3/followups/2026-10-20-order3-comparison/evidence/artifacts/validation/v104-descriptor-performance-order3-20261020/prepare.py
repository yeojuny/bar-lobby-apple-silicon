from pathlib import Path
import json,hashlib,shutil,subprocess,importlib.util
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
OLD=R/'artifacts/validation/v104-descriptor-performance-reverse-20261020'
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
 with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(OLD/'continuation-preparation.json')
assert read(OLD/'continuation-outcome.json')['status']=='completed'
for name in ('controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','sdl-hidden-preflight.json','protected-inputs.json','parent-inventory.json','candidate-inventory.json','run-comparison.py','screen-guard-locked-allowed.py'):
 shutil.copy2(OLD/name,O/name)
shutil.copytree(OLD/'inputs',O/'inputs')
save(O/'authorization.json',{'humanTask':'다시 해봐 순서 또 바꿔서','standingDirection':'전원 연결·절전모드·동일 설정. 화면 잠금 허용: 그냥 해봐 화면 필요없잖아. 시험 전용 캐시 정리 및 MVK GitHub 복원 근거 보존.','order':'Metal4 first then Metal3; parent,candidate,candidate,parent within each backend','maximumGameSessions':8,'measuredSampleRetries':False,'productChanges':False,'controllerChanges':False,'screenUnlockOrAuthenticationChanges':False,'previousEvidence':str(OLD),'cleanup':'Only regenerable private shader/browser caches after verified owned-process shutdown; logs, raw results, apps, sources, build and Markdown preserved.'})
spec=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for label in ('parent','candidate'):assert m.inventory(Path(prep[label]))==read(O/(label+'-inventory.json'))
for entry in read(O/'protected-inputs.json')['userState'].values():assert sha(entry['path'])==entry['sha256']
plans=[]
for ordinal,(backend,role) in enumerate(((b,r) for b in ('metal4','metal3') for r in ('parent','candidate','candidate','parent')),1):
 old=next(x for x in prep['plans'] if x['role']==role and x['backend']==backend)
 folder=O/f'{ordinal}-{role}-{backend}';folder.mkdir();schema=f'v104-descriptor-order3-{ordinal}-{role}-{backend}-v1'
 def adapt(s):return s.replace(old['folder'],str(folder)).replace(str(OLD),str(O)).replace(old['schema'],schema)
 plan=json.loads(adapt(Path(old['plan']['path']).read_text()))
 plan.update(testIdentity=folder.name,authorization=pin(O/'authorization.json'))
 hostfile=folder/'effective-host.mjs';hostfile.write_text(adapt(Path(old['host']['path']).read_text()))
 assert str(folder) in hostfile.read_text() and "plan.schema!=="+repr(schema) in hostfile.read_text()
 assert 'Stable read-only Lobby readiness unavailable' in hostfile.read_text()
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
save(O/'preparation.json',{**prep,'plans':plans,'previousEvidence':str(OLD),'order':'Metal4 parent,candidate,candidate,parent then Metal3 parent,candidate,candidate,parent','hostChanges':'Only fixture paths/schema/test identity; same stable read-only Lobby startup and measured logic as previous continuation','localGuard':pin(O/'screen-guard-locked-allowed.py')})
spec=importlib.util.spec_from_file_location('screen',O/'screen-guard-locked-allowed.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0};desktop=screen.desktop();assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(O/'preflight.json',{'power':screen.power(),'desktop':desktop,'existingScreenIdle':screen.idle(),'syntaxChecks':10,'appInventoriesVerified':True,'newPremeasurementDeletion':False,'priorCachesAlreadyRetired':True,'sourceOrProductChanges':False,'humanAllowsLockedScreen':True})
print('Prepared 8 new samples: Metal4 first then Metal3, parent/candidate/candidate/parent. Immutable app inventories, pins, power and syntax verified.',flush=True)
