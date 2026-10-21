from pathlib import Path
import json,hashlib,shutil,subprocess,importlib.util
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
OLD=R/'artifacts/validation/v104-descriptor-performance-order3-20261020'
read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
 with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(OLD/'preparation.json')
for name in ('controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','sdl-hidden-preflight.json','protected-inputs.json','parent-inventory.json','candidate-inventory.json','screen-guard-locked-allowed.py'):
 shutil.copy2(OLD/name,O/name)
shutil.copytree(OLD/'inputs',O/'inputs')
save(O/'authorization.json',{'humanTask':'이미 완료한 것은 제외하고, 실제 BAR 경로에서 남은 비용을 확인한 뒤 근거가 있는 항목만 상세 설계','scope':'Two bounded current-candidate BAR.app observations: Metal4 then Metal3. Existing fixed scene/controller with one 10-second OS CPU sample per game. No product/source/build changes.','consoleLockAllowed':True,'power':'AC/LowPower ON','maximumGameSessions':2,'measuredPerformanceComparison':False,'runtimeCounters':'Compiled out in frozen app; kept OFF. OS sample only.','cleanup':'Only generated private shader/browser caches after owned shutdown; all logs/sample evidence retained.'})
sampleCode='''
 // Observation only: existing macOS sampler; no runtime/library instrumentation.
 const cpuSampleFile=path.join(run,'cpu-sample.txt'),cpuSampleStderr=path.join(run,'cpu-sample-stderr.txt');
 const sampleFD=fs.openSync(cpuSampleStderr,'wx');
 receipt.cpuSample={tool:'/usr/bin/sample',targetPID:gamePid,durationSeconds:10,intervalMilliseconds:1,startUnixMs:Date.now(),startStatus:status(),output:cpuSampleFile,stderr:cpuSampleStderr,usedForFPSComparison:false};
 cpuSampleHandle=spawn('/usr/bin/sample',[String(gamePid),'10','1','-mayDie','-file',cpuSampleFile],{stdio:['ignore',sampleFD,sampleFD]});fs.closeSync(sampleFD);
 cpuSampleDone=new Promise(resolve=>{cpuSampleHandle.once('error',e=>{receipt.cpuSample.error=String(e);resolve();});cpuSampleHandle.once('exit',(code,signal)=>{receipt.cpuSample.exitCode=code;receipt.cpuSample.signal=signal;receipt.cpuSample.endUnixMs=Date.now();receipt.cpuSample.endStatus=status();resolve();});});
'''
plans=[]
for ordinal,backend in enumerate(('metal4','metal3'),1):
 old=next(x for x in prep['plans'] if x['role']=='candidate' and x['backend']==backend)
 folder=O/f'{ordinal}-candidate-{backend}';folder.mkdir();schema=f'v104-c-cost-{ordinal}-candidate-{backend}-v1'
 def adapt(s):return s.replace(old['folder'],str(folder)).replace(str(OLD),str(O)).replace(old['schema'],schema)
 plan=json.loads(adapt(Path(old['plan']['path']).read_text()));plan.update(testIdentity=folder.name,authorization=pin(O/'authorization.json'))
 host=adapt(Path(old['host']['path']).read_text())
 host=host.replace('let gamePid,measuredQuitRequestID=null;', 'let gamePid,measuredQuitRequestID=null;let cpuSampleHandle=null,cpuSampleDone=null;')
 assert host.count('benchmarkStartAt=Date.now();')==1
 host=host.replace('benchmarkStartAt=Date.now();','benchmarkStartAt=Date.now();'+sampleCode)
 host=host.replace(" receipt.postMeasurementFixtures='excluded_from_existing_performance_only_scope';", " if(cpuSampleDone)await cpuSampleDone;\n if(receipt.cpuSample?.exitCode===0&&fs.existsSync(receipt.cpuSample.output))receipt.cpuSample.sha256=hash(receipt.cpuSample.output);\n receipt.postMeasurementFixtures='excluded_from_cost_observation_scope';")
 host=host.replace(' stopGuard=true;if(watcher)await watcher;', " if(cpuSampleHandle&&cpuSampleHandle.exitCode===null&&cpuSampleHandle.signalCode===null){cpuSampleHandle.kill('SIGTERM');if(cpuSampleDone)await cpuSampleDone;}\n stopGuard=true;if(watcher)await watcher;")
 assert 'cpuSampleDone=new Promise' in host
 hostfile=folder/'effective-host.mjs';hostfile.write_text(host)
 def repin(v):
  if isinstance(v,list):return [repin(x) for x in v]
  if isinstance(v,dict):
   d={k:repin(x) for k,x in v.items()}
   if 'path' in d and 'sha256' in d:d['sha256']=sha(d['path'])
   return d
  return v
 plan=repin(plan);planfile=folder/'plan.json';save(planfile,plan)
 subprocess.run(['/opt/homebrew/bin/node','--check',str(hostfile)],check=True,capture_output=True)
 plans.append({'ordinal':ordinal,'role':'candidate','backend':backend,'folder':str(folder),'schema':schema,'plan':pin(planfile),'host':pin(hostfile)})
runner=(OLD/'run-comparison.py').read_text().replace("len(prep['plans'])==8","len(prep['plans'])==2").replace("len(results)==8","len(results)==2").replace("'maximumGameSessions':8","'maximumGameSessions':2").replace("item['ordinal']<8","item['ordinal']<2")
(O/'run-observation.py').write_text(runner)
save(O/'preparation.json',{**prep,'plans':plans,'order':'Current candidate Metal4 then Metal3; one OS CPU sample each','hostChanges':'Paths/schema plus scoped OS sample observer only; same controller/scene/settings/runtime','localGuard':pin(O/'screen-guard-locked-allowed.py')})
spec=importlib.util.spec_from_file_location('screen',O/'screen-guard-locked-allowed.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0};assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(O/'preflight.json',{'power':screen.power(),'desktop':screen.desktop(),'existingScreenIdle':screen.idle(),'syntaxChecks':2,'productsModified':False,'customDiagnosticsCompiledOut':True,'OSSamplingOnly':True})
print('Prepared two current-app observations; runtime diagnostics remain OFF; OS sampling is scoped to the owned native game.',flush=True)
