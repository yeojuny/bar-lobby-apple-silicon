from pathlib import Path
import json,hashlib,subprocess
O=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):return {'path':str(p),'sha256':sha(p)}
def save(p,d):
 with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(O/'preparation.json');out=read(O/'outcome.json')
assert len(out['results'])==3 and out['results'][-1]['fps'] is None
failed=read(out['results'][-1]['receipt']);events=(Path(out['results'][-1]['receipt']).parent/'events.jsonl').read_text()
assert not failed['remainingOwnedProcesses'] and failed['protectedInputsUnchanged'] and '"event":"owned-child"' not in events
save(O/'continuation-authorization.json',{'humanTask':'다시 해봐 순서 바꿔서 / 그냥 해봐 화면 필요없잖아','scope':'Complete remaining requested reverse-order samples; preserve all failed attempts and successful performance samples.','failedAttempt':out['results'][-1],'reason':'Lobby renderer execution context destroyed before any graphical game process.','retryMeasuredSamples':False,'additionalPreGameAttempt':1,'maximumRemainingGameSessions':6,'productChanges':False})
items=[]
for item in prep['plans'][2:]:
 oldfolder=Path(item['folder']);folder=oldfolder if item['ordinal']!=3 else O/'3-parent-metal3-startup-continuation'
 if folder!=oldfolder:folder.mkdir()
 plan=read(item['plan']['path']);host=Path(item['host']['path']).read_text()
 schema=item['schema'] if item['ordinal']!=3 else item['schema'].replace('-v1','-startup-continuation-v1')
 if folder!=oldfolder:
  host=host.replace(str(oldfolder),str(folder)).replace(item['schema'],schema)
  plan=json.loads(json.dumps(plan).replace(str(oldfolder),str(folder)).replace(item['schema'],schema));plan['testIdentity']=folder.name
 # Only read-only startup readiness checks may repeat; launchScript is invoked exactly once.
 old=' await renderer(\'(async()=>{for(let i=0;i<150&&!window.game?.launchScript;i++)await new Promise(r=>setTimeout(r,100));if(!window.game?.launchScript)throw Error("Lobby preload unavailable");return true;})()\');'
 new=''' // Wait for two stable read-only ready observations before the one launch action.
 { const end=Date.now()+30000;let previous=null,stable=0;
   while(Date.now()<end){
     try{const q=await renderer('({ready:document.readyState,api:typeof window.game?.launchScript,url:location.href})',5000);
       if(q.ready==='complete'&&q.api==='function'&&q.url===previous)stable++;else stable=0;
       previous=q.url;if(stable>=2)break;
     }catch(e){if(!String(e).includes('Execution context was destroyed'))throw e;stable=0;previous=null;}
     await delay(1000);
   }
   if(stable<2)throw Error('Stable read-only Lobby readiness unavailable');
 }
'''.rstrip()
 assert old in host;host=host.replace(old,new)
 hostfile=folder/'effective-host.mjs'
 if folder==oldfolder:
  # These hosts have never run; retain their original bytes before the startup-only repair.
  (folder/'effective-host.pre-startup-fix.mjs').write_bytes(hostfile.read_bytes())
  (folder/'plan.pre-startup-fix.json').write_bytes((folder/'plan.json').read_bytes())
 hostfile.write_text(host);subprocess.run(['/opt/homebrew/bin/node','--check',str(hostfile)],check=True,capture_output=True)
 plan.update(authorization=pin(O/'continuation-authorization.json'));plan['executionFiles'][0]=pin(hostfile)
 planfile=folder/'plan.json';planfile.write_text(json.dumps(plan,indent=2,ensure_ascii=False)+'\n')
 items.append({**item,'folder':str(folder),'schema':schema,'plan':pin(planfile),'host':pin(hostfile)})
continuation={**prep,'plans':items,'startupReadinessFix':'Only repeat safe read-only document readiness checks; one launchScript call. No benchmark/controller/render changes.'}
save(O/'continuation-preparation.json',continuation)
runner=(O/'run-comparison.py').read_text().replace("base/'preparation.json'","base/'continuation-preparation.json'").replace("len(prep['plans'])==8","len(prep['plans'])==6").replace("base/'outcome.json'","base/'continuation-outcome.json'").replace("base/'screen-guard.json'","base/'continuation-screen-guard.json'").replace("base/'screen-observations.jsonl'","base/'continuation-screen-observations.jsonl'").replace("base/'owned-runner.json'","base/'continuation-owned-runner.json'").replace("base/'screen-stop.json'","base/'continuation-screen-stop.json'")
runner=runner.replace("p=base/name","p=base/('continuation-'+name)").replace("len(results)==8","len(results)==6").replace("'maximumGameSessions':8","'maximumGameSessions':6")
(O/'run-continuation.py').write_text(runner)
print('Pre-game failure retained. Remaining six requested samples prepared with read-only stable Lobby readiness.')
