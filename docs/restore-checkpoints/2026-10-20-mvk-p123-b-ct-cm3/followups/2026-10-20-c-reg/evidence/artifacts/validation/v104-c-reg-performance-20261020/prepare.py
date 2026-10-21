from pathlib import Path
import json,hashlib,shutil,subprocess,importlib.util
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
OLD=R/'artifacts/validation/v104-descriptor-performance-order3-20261020';IMPL=R/'artifacts/validation/v104-c-reg-20261020'
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
 with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(OLD/'preparation.json');assert read(OLD/'outcome.json')['status']=='completed'
package=read(IMPL/'package-receipt.json');parent=package['parent'];candidate=package['app']
for name in ('controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','sdl-hidden-preflight.json','run-comparison.py','screen-guard-locked-allowed.py'):
 shutil.copy2(OLD/name,O/name)
shutil.copytree(OLD/'inputs',O/'inputs')
shutil.copy2(R/'artifacts/validation/v104-followup-c-t-20261020/candidate-inventory.json',O/'parent-inventory.json')
shutil.copy2(IMPL/'candidate-inventory.json',O/'candidate-inventory.json')
save(O/'authorization.json',{'humanTask':'그럼 C-REG부터 구현하고 검증해봐. 지금 후보랑 전원 연결·절전모드에서 같은 조건으로 Metal3·4 성능 비교해서 표로 줘.','standingDirection':'동일 설정; 화면 잠금 허용; 시험 전용 캐시 정리 및 MVK 복원 근거 보존.','order':'Metal4 parent,candidate,candidate,parent; Metal3 candidate,parent,parent,candidate','maximumGameSessions':8,'measuredSampleRetries':False,'productChangesDuringBenchmark':False,'controllerChanges':False,'screenUnlockOrAuthenticationChanges':False,'previousEvidence':str(OLD),'cleanup':'Only regenerable private shader/browser caches after verified owned-process shutdown; logs, raw results, apps, sources, build and Markdown preserved.'})
spec=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for label,app in [('parent',parent),('candidate',candidate)]:assert m.inventory(Path(app))==read(O/(label+'-inventory.json'))
# Use precisely the benchmark host's recursive inventory serialization (includes directories).
oldhost=Path(prep['plans'][0]['host']['path']).read_text();a=oldhost.index('function inventory(app){');b=oldhost.index('\nfunction checkPins()',a)
inv=O/'inventory-digest.mjs';inv.write_text("import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';\nconst hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');\n"+oldhost[a:b]+"\nconsole.log(crypto.createHash('sha256').update(JSON.stringify(inventory(process.argv[2]))).digest('hex'));\n")
digests={app:subprocess.check_output(['/opt/homebrew/bin/node',str(inv),app],text=True).strip() for app in (parent,candidate)}
assert digests[parent]==read(OLD/'protected-inputs.json')['apps'][parent]
protected=read(OLD/'protected-inputs.json');protected['apps']=digests
for entry in protected['userState'].values():assert sha(entry['path'])==entry['sha256']
save(O/'protected-inputs.json',protected)
plans=[]
order=[('metal4',r) for r in ('parent','candidate','candidate','parent')]+[('metal3',r) for r in ('candidate','parent','parent','candidate')]
for ordinal,(backend,role) in enumerate(order,1):
 old=next(x for x in prep['plans'] if x['role']==role and x['backend']==backend)
 folder=O/f'{ordinal}-{role}-{backend}';folder.mkdir();schema=f'v104-c-reg-{ordinal}-{role}-{backend}-v1'
 def adapt(s):
  s=s.replace(old['folder'],str(folder)).replace(str(OLD),str(O)).replace(old['schema'],schema)
  return s.replace(prep['parent'],'__C_REG_PARENT__').replace(prep['candidate'],candidate).replace('__C_REG_PARENT__',parent)
 plan=json.loads(adapt(Path(old['plan']['path']).read_text()));app=parent if role=='parent' else candidate
 plan.update(testIdentity=folder.name,authorization=pin(O/'authorization.json'),limits=['C-T+C-M3 cumulative parent versus same cumulative candidate plus C-REG','No retries; identical controller, settings, engine and scene; only MoltenVK differs','No product or actual user preference edits during comparison'])
 assert plan['app']['app']==app
 plan['app']['inventorySha256']=digests[app];plan['protectedApps']=[{'app':p,'inventorySha256':h} for p,h in digests.items()]
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
rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
save(O/'preparation.json',{**prep,'parent':parent,'candidate':candidate,'parentMvk':pin(Path(parent)/rel),'candidateMvk':pin(Path(candidate)/rel),'plans':plans,'previousEvidence':str(OLD),'order':'Metal4 parent,candidate,candidate,parent then Metal3 candidate,parent,parent,candidate','hostChanges':'Only app identity, fixture paths, schema and test identity; stable read-only Lobby startup and measured logic preserved','localGuard':pin(O/'screen-guard-locked-allowed.py'),'sourceValidation':pin(IMPL/'validation-summary.json')})
spec=importlib.util.spec_from_file_location('screen',O/'screen-guard-locked-allowed.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0};desktop=screen.desktop();assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(O/'preflight.json',{'power':screen.power(),'desktop':desktop,'existingScreenIdle':screen.idle(),'syntaxChecks':10,'appInventoriesVerified':True,'newPremeasurementDeletion':False,'priorCachesAlreadyRetired':True,'humanAllowsLockedScreen':True})
print('Prepared 8 new samples; parent C-T+C-M3, candidate adds C-REG. App identities, inputs, power and syntax verified.',flush=True)
