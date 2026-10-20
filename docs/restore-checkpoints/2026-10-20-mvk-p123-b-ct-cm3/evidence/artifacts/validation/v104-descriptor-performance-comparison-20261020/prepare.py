from pathlib import Path
import json,hashlib,shutil,subprocess,importlib.util,os
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;OLD=R/'artifacts/validation/v104-performance-comparison-20261020/batch7'
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def rebase(v):
 if isinstance(v,str):return v.replace(str(OLD),str(O))
 if isinstance(v,list):return [rebase(x) for x in v]
 if isinstance(v,dict):return {k:rebase(x) for k,x in v.items()}
 return v
def save(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n')
for name in ('controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','sdl-hidden-preflight.json'):
 s=(OLD/name).read_text();(O/name).write_text(s.replace(str(OLD),str(O)))
assert sha(O/'controller.lua')==sha(OLD/'controller.lua')
previous=read(OLD/'preparation.json');first=read(Path(previous['plans'][0]['plan']['path']))
for rel,entry in first['inputPins'].items():
 source=Path(entry['path']);assert sha(source)==entry['sha256'];target=O/'inputs'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
parent=R/'artifacts/runtime/v104-performance-ab-candidate-20261020/BAR.app';candidate=R/'artifacts/runtime/v104-descriptor-candidate-20261020/BAR.app'
spec=importlib.util.spec_from_file_location('inventory_helpers',R/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for app,expected,label in ((parent,R/'artifacts/validation/v104-followup-ab-20261020/ab-candidate-inventory.json','parent'),(candidate,R/'artifacts/validation/v104-followup-c-t-20261020/candidate-inventory.json','candidate')):
 inv=m.inventory(app);assert inv==read(expected);save(O/(label+'-inventory.json'),inv)
def host_inventory(app):
 rows={}
 def walk(p,prefix=''):
  for x in sorted(p.iterdir(),key=lambda x:x.name):
   rel=prefix+'/'+x.name if prefix else x.name;mode=x.lstat().st_mode&511
   if x.is_symlink():rows[rel]={'type':'link','mode':mode,'target':os.readlink(x)}
   elif x.is_dir():rows[rel]={'type':'directory','mode':mode};walk(x,rel)
   else:rows[rel]={'type':'file','mode':mode,'size':x.stat().st_size,'sha256':sha(x)}
 walk(app);return hashlib.sha256(json.dumps(rows,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
apps={str(a):host_inventory(a) for a in (parent,candidate)}
state={k:pin(Path(v['path'])) for k,v in read(OLD/'protected-inputs.json')['userState'].items()}
save(O/'protected-inputs.json',{'apps':apps,'userState':state})
authorization={'user':'이전 후보 vs C-T·C-M3 후보 성능 비교. 전원 연결·절전모드, 같은 조건 Metal3·4, 표로 보고. 실험 흔적은 정리하되 특이한 큰 성능상승 라인 제외. MVK GitHub 복원 checkpoint 보존 요청.','parent':str(parent),'candidate':str(candidate),'maximumGameSessions':8,'retry':False,'sourceChanges':False,'settings':'AC Power/Low Power/Ultra/AA Off/Spring/VSync Off, same fixed scene and fresh private cache','benchmark':'Same successful batch7 controller/host logic; only provenance/app/path/schema adaptation','cleanup':'Remove regenerable private shader/browser cache after session; preserve logs/results/source/app/Markdown.'}
save(O/'authorization.json',authorization)
plans=[]
for item in previous['plans']:
 oldplan=read(Path(item['plan']['path']));plan=rebase(oldplan);role=item['role'];app=parent if role=='parent' else candidate;folder=O/Path(item['folder']).name;folder.mkdir();schema=item['schema'].replace('v104-performance-','v104-descriptor-')
 plan.update(schema=schema,app={'app':str(app),'inventorySha256':apps[str(app)]},appAsar=pin(app/'Contents/Resources/app.asar'),protectedApps=[{'app':a,'inventorySha256':v} for a,v in apps.items()],authorization=pin(O/'authorization.json'),limits=['P1/P2/P3+B versus cumulative descriptor candidate; current approved 8 arms','No retry; identical controller, settings, engine and scene; only MoltenVK differs','No source or actual user preference edits'])
 engine=app/'Contents/Resources/bundled-assets/engine/2026.09.01-24-g01efdf4 master/spring';plan['lanes']['lobby']['engine'].update(pin(engine),bytes=engine.stat().st_size);plan['buildDigest']=sha(engine)
 runtime=app/'Contents/Resources/bundled-assets/runtime';plan['sharedRuntime']=[pin(runtime/p) for p in ('sdl3/lib/libSDL3.0.dylib','mesa-zink/lib/libEGL.1.dylib','mesa-zink/lib/libgallium-26.3.0-devel.dylib','vulkan-loader/lib/libvulkan.1.4.365.dylib','moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib','moltenvk-pr2746/MoltenVK_icd.json')]
 for key,name in (('controller','controller.lua'),('scene','scene.txt'),('contentFiles','content-files.json'),('acceptanceBootstrap','metal-bootstrap.cjs'),('sourceAudit','content-receipt.json')):plan[key]=pin(O/name)
 plan['qualifiedAdapters']['lobby']=pin(O/'benchmark-bootstrap.cjs');plan['hiddenQualification']['preflight']=pin(O/'sdl-hidden-preflight.json');plan['inputPins']={rel:pin(O/'inputs'/rel) for rel in first['inputPins']}
 host=Path(item['host']['path']).read_text().replace(str(OLD),str(O)).replace(item['schema'],schema)
 assert str(folder) in host and "plan.schema!=="+repr(schema) in host and "grant.schema!=="+repr(schema+'-grant') in host
 hostfile=folder/'effective-host.mjs';hostfile.write_text(host)
 plan['executionFiles']=[pin(hostfile),pin(O/'benchmark-bootstrap.cjs'),pin(O/'metal-bootstrap.cjs')]+oldplan['executionFiles'][3:]
 planfile=folder/'plan.json';save(planfile,plan)
 for entry in plan['executionFiles']+list(plan['inputPins'].values())+plan['sharedRuntime']+[plan['controller'],plan['scene'],plan['contentFiles'],plan['authorization'],plan['sourceAudit']]:assert sha(Path(entry['path']))==entry['sha256'],entry
 subprocess.run(['/opt/homebrew/bin/node','--check',str(hostfile)],check=True,capture_output=True)
 plans.append({**item,'schema':schema,'folder':str(folder),'plan':pin(planfile),'host':pin(hostfile)})
for name in ('benchmark-bootstrap.cjs','metal-bootstrap.cjs'):subprocess.run(['/opt/homebrew/bin/node','--check',str(O/name)],check=True,capture_output=True)
for rel in ('Contents/Resources/app.asar','Contents/Resources/bundled-assets/engine/2026.09.01-24-g01efdf4 master/spring','Contents/Resources/bundled-assets/engine/2026.07.04/spring'):assert sha(parent/rel)==sha(candidate/rel)
runner=(OLD/'run-comparison.py').read_text();(O/'run-comparison.py').write_text(runner)
save(O/'preparation.json',{'plans':plans,'parent':str(parent),'candidate':str(candidate),'controllerByteIdenticalToSuccessfulPreviousTest':True,'hostChanges':'Only paths/schema/provenance and app pins; measurement logic unchanged','parentMvk':pin(parent/'Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'),'candidateMvk':pin(candidate/'Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib')})
spec=importlib.util.spec_from_file_location('screen',R/'tools/r92-benchmark-screen-guard.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0};desktop=screen.desktop();assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(O/'preflight.json',{'syntaxChecks':10,'power':screen.power(),'desktop':desktop,'existingScreenIdle':screen.idle(),'oldVBOFixtureNotStaged':True,'appInvsVerified':True,'sourceOrProductChanges':False})
print('Prepared exact two apps and 8 finite arms; same successful controller, no product changes, preflight passed.')
