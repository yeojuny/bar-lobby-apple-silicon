from pathlib import Path
import hashlib, json, shutil, subprocess

ROOT=Path(__file__).resolve().parents[3]
IMPL=Path(__file__).resolve().parent
BASE=ROOT/'artifacts/validation/v104-drawable-size-performance-20261020'
OUT=ROOT/'artifacts/validation/v104-drawable-size-observation-20261020'
OUT.mkdir(exist_ok=False)
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
    with p.open('x') as f:json.dump(d,f,indent=2);f.write('\n')
prep=read(BASE/'preparation.json')
for name in ['controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','screen-guard-locked-allowed.py','libhidden-fullscreen.dylib','sdl-hidden-preflight.json','protected-inputs.json','parent-inventory.json','candidate-inventory.json']:
    shutil.copy2(BASE/name,OUT/name)
shutil.copytree(BASE/'inputs',OUT/'inputs')
save(OUT/'authorization.json',{'humanTask':'그래 그렇게 하자: confirm removal of unnecessary display queries with the existing short OS sampler in a separate observation; sampled FPS is excluded from comparison.','maximumGameSessions':1,'sampler':'Existing /usr/bin/sample,10seconds,1ms requested interval','conditions':'Same AC+Low Power, fullscreen hidden1512x950, settings and controller as separate FPS cohort','noNewProductInstrumentation':True,'nativeVisibleScreenTransitionAcceptance':False})
old=next(p for p in prep['plans'] if p['role']=='candidate' and p['backend']=='metal4')
folder=OUT/'1-candidate-metal4';folder.mkdir();schema='v104-drawable-size-observation-metal4-v1'
def adapt(text):return text.replace(old['folder'],str(folder)).replace(str(BASE),str(OUT)).replace(old['schema'],schema)
plan=json.loads(adapt(Path(old['plan']['path']).read_text()))
plan.update(testIdentity=folder.name,authorization=pin(OUT/'authorization.json'),limits=['Sampled observation only; do not use FPS from this run for performance comparison','Actual current candidate, same controller/fullscreen settings; no product cost collector'],cpuObservation={'durationSeconds':10,'intervalMilliseconds':1,'usedForFPSComparison':False})
host=adapt(Path(old['host']['path']).read_text())
reference=(ROOT/'artifacts/validation/v104-remaining-c-cost-design-20261020/1-candidate-metal4/effective-host.mjs').read_text()
start=reference.index(' // Observation only:')
end=reference.index(" const resultPath=path.join(data,'LuaUI/Config/v104-performance-result.json');",start)
block=reference[start:end]
host=host.replace('let gamePid,measuredQuitRequestID=null;','let gamePid,measuredQuitRequestID=null;let cpuSampleHandle=null,cpuSampleDone=null;')
anchor=" const resultPath=path.join(data,'LuaUI/Config/v104-performance-result.json');const result=await until("
assert host.count(anchor)==1
host=host.replace(anchor,block+anchor)
anchor=" receipt.postMeasurementFixtures='excluded_from_existing_performance_only_scope';"
host=host.replace(anchor," if(cpuSampleDone)await cpuSampleDone;\n if(receipt.cpuSample?.exitCode===0&&fs.existsSync(receipt.cpuSample.output))receipt.cpuSample.sha256=hash(receipt.cpuSample.output);\n receipt.postMeasurementFixtures='excluded_from_sampled_observation_scope';")
anchor='finally{\n stopGuard=true;'
assert host.count(anchor)==1
host=host.replace(anchor,"finally{\n if(cpuSampleHandle&&cpuSampleHandle.exitCode===null&&cpuSampleHandle.signalCode===null){cpuSampleHandle.kill('SIGTERM');if(cpuSampleDone)await cpuSampleDone;}\n stopGuard=true;")
hostfile=folder/'effective-host.mjs';hostfile.write_text(host)
def repin(value):
    if isinstance(value,list):return [repin(x) for x in value]
    if isinstance(value,dict):
        d={k:repin(v) for k,v in value.items()}
        if 'path' in d and 'sha256' in d:d['sha256']=sha(d['path'])
        return d
    return value
plan=repin(plan);planfile=folder/'plan.json';save(planfile,plan)
subprocess.run(['/opt/homebrew/bin/node','--check',str(hostfile)],check=True,capture_output=True)
save(OUT/'preparation.json',{**prep,'plans':[{'ordinal':1,'role':'candidate','backend':'metal4','folder':str(folder),'schema':schema,'plan':pin(planfile),'host':pin(hostfile)}],'order':'One current candidate Metal4 observation,excluded from all FPS comparisons','hostChanges':'Existing macOS sampler lifecycle reused verbatim; frozen fullscreen benchmark host otherwise unchanged','sampleUsedForFPSComparison':False,'maximumGameSessions':1})
runner=(ROOT/'artifacts/validation/v104-remaining-c-cost-design-20261020/run-observation.py').read_text()
runner=runner.replace("len(prep['plans'])==2","len(prep['plans'])==1").replace("item['ordinal']<2","item['ordinal']<1").replace('len(results)==2','len(results)==1').replace("'maximumGameSessions':2","'maximumGameSessions':1")
(OUT/'run-observation.py').write_text(runner)
print(json.dumps({'status':'prepared','sessions':1,'sampledFPSExcluded':True}))
