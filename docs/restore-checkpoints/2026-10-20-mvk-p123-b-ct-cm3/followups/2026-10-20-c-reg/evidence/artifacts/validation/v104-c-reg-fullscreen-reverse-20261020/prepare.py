from pathlib import Path
import json,hashlib,shutil,subprocess,importlib.util
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
OLD=R/'artifacts/validation/v104-c-reg-performance-20261020';IMPL=R/'artifacts/validation/v104-c-reg-20261020'
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
 with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(OLD/'preparation.json');assert read(OLD/'outcome.json')['status']=='completed'
package=read(IMPL/'package-receipt.json');parent=package['parent'];candidate=package['app']
for name in ('controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','run-comparison.py','screen-guard-locked-allowed.py'):
 shutil.copy2(OLD/name,O/name)
adapter=O/'benchmark-bootstrap.cjs'
oldAdapter=adapter.read_text();newAdapter=oldAdapter.replace('Fullscreen:0,WindowBorderless:0,XResolutionWindowed:1512,YResolutionWindowed:950,WindowPosX:80,WindowPosY:80','Fullscreen:1,WindowBorderless:0,XResolution:1512,YResolution:950,XResolutionWindowed:1512,YResolutionWindowed:982,WindowPosX:0,WindowPosY:0').replace("arg==='--fullscreen'||arg.startsWith('--fullscreen=')","arg==='--window'||arg.startsWith('--window=')").replace('Fullscreen flag refused','Windowed flag refused').replace("args.unshift('--window')","args.unshift('--fullscreen')")
assert newAdapter!=oldAdapter;adapter.write_text(newAdapter)
shutil.copytree(OLD/'inputs',O/'inputs')
shutil.copy2(R/'artifacts/validation/v104-followup-c-t-20261020/candidate-inventory.json',O/'parent-inventory.json')
shutil.copy2(IMPL/'candidate-inventory.json',O/'candidate-inventory.json')
save(O/'authorization.json',{'humanTask':'역순으로 조져봐. 해상도도 노치 제외한 전체화면해상도로 비교.','standingDirection':'동일 설정; 화면 잠금 허용; 시험 전용 캐시 정리 및 MVK 복원 근거 보존.','order':'Metal3 parent,candidate,candidate,parent; Metal4 candidate,parent,parent,candidate','maximumGameSessions':8,'measuredSampleRetries':False,'productChangesDuringBenchmark':False,'controllerChanges':False,'windowGeometryChange':'Actual game Fullscreen=1 and SDL fullscreen request; display container 1512x982 and safe viewport 1512x950; hidden display/Space presentation deferred by SDL','screenUnlockOrAuthenticationChanges':False,'previousEvidence':str(OLD),'cleanup':'Only regenerable private shader/browser caches after verified owned-process shutdown; logs, raw results, apps, sources, build and Markdown preserved.'})
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
order=[('metal3',r) for r in ('parent','candidate','candidate','parent')]+[('metal4',r) for r in ('candidate','parent','parent','candidate')]
for ordinal,(backend,role) in enumerate(order,1):
 old=next(x for x in prep['plans'] if x['role']==role and x['backend']==backend)
 folder=O/f'{ordinal}-{role}-{backend}';folder.mkdir();schema=f'v104-c-reg-safe-reverse-{ordinal}-{role}-{backend}-v1'
 def adapt(s):
  s=s.replace(old['folder'],str(folder)).replace(str(OLD),str(O)).replace(old['schema'],schema).replace('Fullscreen:0,WindowBorderless:0,XResolutionWindowed:1512,YResolutionWindowed:950,WindowPosX:80,WindowPosY:80','Fullscreen:1,WindowBorderless:0,XResolution:1512,YResolution:950,XResolutionWindowed:1512,YResolutionWindowed:982,WindowPosX:0,WindowPosY:0').replace('actual-sdl-dummy-hidden-contract-passed','actual-sdl-dummy-hidden-fullscreen-contract-passed')
  return s.replace(prep['parent'],'__C_REG_PARENT__').replace(prep['candidate'],candidate).replace('__C_REG_PARENT__',parent)
 plan=json.loads(adapt(Path(old['plan']['path']).read_text()));app=parent if role=='parent' else candidate
 plan.update(testIdentity=folder.name,authorization=pin(O/'authorization.json'),limits=['C-T+C-M3 cumulative parent versus same cumulative candidate plus C-REG','No retries; identical controller, settings, engine and scene; only MoltenVK differs','No product or actual user preference edits during comparison'])
 plan['expectedDrawable']={'width':1512,'height':950}
 guard=O/'libhidden-fullscreen.dylib';plan['lanes']['lobby']['guard']=pin(guard);plan['hiddenWindowGuard']=pin(guard)
 plan['hiddenQualification']={'preflight':pin(O/'sdl-hidden-preflight.json'),'guardSha256':sha(guard),'sdlSha256':plan['sdlSha256']}
 plan['gameFullscreen']=True;plan['nativePresentationDeferredWhileHidden']=True
 assert plan['app']['app']==app
 plan['app']['inventorySha256']=digests[app];plan['protectedApps']=[{'app':p,'inventorySha256':h} for p,h in digests.items()]
 hostfile=folder/'effective-host.mjs';host=adapt(Path(old['host']['path']).read_text())
 anchor="receipt.hiddenWindowEvents=guardEvents;"
 extra='''receipt.hiddenWindowEvents=guardEvents;
 const fullEvents=guardEvents.filter(e=>e.event==='fullscreen-enabled-hidden'||e.event==='fullscreen-disabled-hidden'),fullEvent=fullEvents.at(-1);
 if(!fullEvent||fullEvent.event!=='fullscreen-enabled-hidden'||!(fullEvent.flags&1)||!(fullEvent.flags&8))throw Error('Actual SDL fullscreen intent and hidden state unverified');
 const nativeLog=fs.readFileSync(path.join(data,'infolog.txt'),'utf8');
 const fullModes=[...nativeLog.matchAll(/cfgFullScreen=(\d)/g)];
 const safeViews=[...nativeLog.matchAll(/macOS safe viewport\] window=(\d+)x(\d+) view=<(-?\d+),(-?\d+) (\d+)x(\d+)>/g)];
 const lastView=safeViews.at(-1);
 if(fullModes.at(-1)?.[1]!=='1'||!lastView||Number(lastView[5])!==1512||Number(lastView[6])!==950)throw Error('Engine fullscreen safe viewport unverified');
 receipt.fullscreenMode={gameFullscreen:true,SDLFullscreen:true,SDLHidden:true,window:{width:Number(lastView[1]),height:Number(lastView[2])},viewport:{width:Number(lastView[5]),height:Number(lastView[6])},nativePresentation:'SDL defers native display/Space transition while hidden',logEvidence:lastView[0]};
'''
 assert anchor in host;host=host.replace(anchor,extra);hostfile.write_text(host)
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
save(O/'preparation.json',{**prep,'parent':parent,'candidate':candidate,'parentMvk':pin(Path(parent)/rel),'candidateMvk':pin(Path(candidate)/rel),'plans':plans,'previousEvidence':str(OLD),'order':'Metal3 parent,candidate,candidate,parent then Metal4 candidate,parent,parent,candidate','hostChanges':'Actual Fullscreen=1/--fullscreen, new fullscreen-preserving hidden sidecar and native fullscreen/safe-viewport checks; reverse order; frozen apps/controller/scene/quality preserved','localGuard':pin(O/'screen-guard-locked-allowed.py'),'sourceValidation':pin(IMPL/'validation-summary.json'),'resolution':{'width':1512,'height':950},'resolutionPolicy':'Engine fullscreen and SDL fullscreen intent at current product default 1x; safe viewport 1512x950; SDL native presentation remains deferred while hidden'})
spec=importlib.util.spec_from_file_location('screen',O/'screen-guard-locked-allowed.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0};desktop=screen.desktop();assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(O/'preflight.json',{'power':screen.power(),'desktop':desktop,'existingScreenIdle':screen.idle(),'syntaxChecks':10,'appInventoriesVerified':True,'newPremeasurementDeletion':False,'priorCachesAlreadyRetired':True,'humanAllowsLockedScreen':True})
print('Prepared 8 new samples; parent C-T+C-M3, candidate adds C-REG. App identities, inputs, power and syntax verified.',flush=True)
