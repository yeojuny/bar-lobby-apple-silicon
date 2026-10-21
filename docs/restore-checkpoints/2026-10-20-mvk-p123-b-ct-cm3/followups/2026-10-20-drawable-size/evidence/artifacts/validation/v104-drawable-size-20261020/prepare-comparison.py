from pathlib import Path
import hashlib, importlib.util, json, shutil, subprocess

ROOT=Path(__file__).resolve().parents[3]
IMPL=Path(__file__).resolve().parent
OLD=ROOT/'artifacts/validation/v104-c-reg-fullscreen-reverse-20261020'
OUT=ROOT/'artifacts/validation/v104-drawable-size-performance-20261020'
OUT.mkdir(exist_ok=False)
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
    with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(OLD/'preparation.json');package=read(IMPL/'package-receipt.json')
parent,candidate=package['parent'],package['app']
assert read(OLD/'outcome.json')['status']=='completed'
for name in ['controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','screen-guard-locked-allowed.py','run-comparison.py','hidden-fullscreen.m','libhidden-fullscreen.dylib','sdl-hidden-preflight.json','display-geometry.json']:
    shutil.copy2(OLD/name,OUT/name)
shutil.copytree(OLD/'inputs',OUT/'inputs')
for role in ['parent','candidate']:shutil.copy2(IMPL/(role+'-inventory.json'),OUT/(role+'-inventory.json'))
save(OUT/'authorization.json',{'humanTask':'그래 그렇게 하자: narrow viewport/scissor live-size query optimization, related checks, independent Astra High review and same-condition M3/M4 comparison.','standingConditions':'AC Power, Low Power ON, Ultra, AA Off, Spring, fullscreen setting, notch-excluded1512x950 viewport, hidden window, sound off; private profiles/cold caches; preserve raw evidence and remove owned regenerable caches after process exit.','order':'Metal4 parent,candidate,candidate,parent; Metal3 candidate,parent,parent,candidate','maximumGameSessions':8,'measuredSampleRetries':False,'runtimeSampling':False,'productChangesDuringBenchmark':False,'nativeSpaceTransitionAcceptance':False})
spec=importlib.util.spec_from_file_location('inventory',ROOT/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for role,app in [('parent',parent),('candidate',candidate)]:assert m.inventory(Path(app))==read(OUT/(role+'-inventory.json'))
oldhost=Path(prep['plans'][0]['host']['path']).read_text();start=oldhost.index('function inventory(app){');end=oldhost.index('\nfunction checkPins()',start)
inv=OUT/'inventory-digest.mjs';inv.write_text("import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';\nconst hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');\n"+oldhost[start:end]+"\nconsole.log(crypto.createHash('sha256').update(JSON.stringify(inventory(process.argv[2]))).digest('hex'));\n")
digests={app:subprocess.check_output(['/opt/homebrew/bin/node',str(inv),app],text=True).strip() for app in [parent,candidate]}
protected=read(OLD/'protected-inputs.json');protected['apps']=digests
for item in protected['userState'].values():assert sha(item['path'])==item['sha256']
save(OUT/'protected-inputs.json',protected)
plans=[]
order=[('metal4',r) for r in ['parent','candidate','candidate','parent']]+[('metal3',r) for r in ['candidate','parent','parent','candidate']]
for ordinal,(backend,role) in enumerate(order,1):
    old=next(x for x in prep['plans'] if x['role']==role and x['backend']==backend)
    folder=OUT/f'{ordinal}-{role}-{backend}';folder.mkdir();schema=f'v104-drawable-size-{ordinal}-{role}-{backend}-v1'
    def adapt(text):
        text=text.replace(old['folder'],str(folder)).replace(str(OLD),str(OUT)).replace(old['schema'],schema)
        return text.replace(prep['parent'],'__DRAWABLE_PARENT__').replace(prep['candidate'],candidate).replace('__DRAWABLE_PARENT__',parent)
    plan=json.loads(adapt(Path(old['plan']['path']).read_text()))
    app=parent if role=='parent' else candidate
    plan.update(testIdentity=folder.name,authorization=pin(OUT/'authorization.json'),limits=['C-REG cumulative parent versus same cumulative app plus live window/drawable size query in both native engines','No retries, same frozen controller/settings/scene; only two engine binaries and signature differ','No CPU sampler or runtime cost collector during FPS measurement'])
    plan['app']['inventorySha256']=digests[app]
    plan['protectedApps']=[{'app':a,'inventorySha256':d} for a,d in digests.items()]
    engine=Path(plan['lanes']['lobby']['engine']['path'])
    plan['lanes']['lobby']['engine'].update(sha256=sha(engine),bytes=engine.stat().st_size)
    plan['buildDigest']=sha(engine)
    host=folder/'effective-host.mjs';host.write_text(adapt(Path(old['host']['path']).read_text()))
    def repin(value):
        if isinstance(value,list):return [repin(x) for x in value]
        if isinstance(value,dict):
            d={k:repin(v) for k,v in value.items()}
            if 'path' in d and 'sha256' in d:d['sha256']=sha(d['path'])
            return d
        return value
    plan=repin(plan);planfile=folder/'plan.json';save(planfile,plan)
    subprocess.run(['/opt/homebrew/bin/node','--check',str(host)],check=True,capture_output=True)
    assert 'cpuSampleHandle' not in host.read_text()
    plans.append({'ordinal':ordinal,'role':role,'backend':backend,'folder':str(folder),'schema':schema,'plan':pin(planfile),'host':pin(host)})
for name in ['benchmark-bootstrap.cjs','metal-bootstrap.cjs']:subprocess.run(['/opt/homebrew/bin/node','--check',str(OUT/name)],check=True,capture_output=True)
for name in ['controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','libhidden-fullscreen.dylib']:assert sha(OUT/name)==sha(OLD/name)
runtime='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
assert sha(Path(parent)/runtime)==sha(Path(candidate)/runtime)
save(OUT/'preparation.json',{**prep,'plans':plans,'parent':parent,'candidate':candidate,'parentMvk':pin(Path(parent)/runtime),'candidateMvk':pin(Path(candidate)/runtime),'previousEvidence':str(OLD),'order':'Metal4 parent,candidate,candidate,parent then Metal3 candidate,parent,parent,candidate','sourceValidation':pin(IMPL/'cpu-summary.json'),'packageReceipt':pin(IMPL/'package-receipt.json'),'hostChanges':'Private paths/app and engine identity pins/order only; fullscreen host, guard, controller, geometry, workload, settings and runtime unchanged.','localGuard':pin(OUT/'screen-guard-locked-allowed.py')})
spec=importlib.util.spec_from_file_location('screen',OUT/'screen-guard-locked-allowed.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0}
assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(OUT/'preflight.json',{'power':screen.power(),'desktop':screen.desktop(),'existingScreenIdle':screen.idle(),'syntaxChecks':10,'appInventoriesVerified':True,'controllerAndFullscreenToolBytesUnchanged':True,'noPremeasurementDeletion':True})
print(json.dumps({'status':'prepared','sessions':8,'parent':parent,'candidate':candidate,'order':order,'resolution':{'width':1512,'height':950}},ensure_ascii=False))
