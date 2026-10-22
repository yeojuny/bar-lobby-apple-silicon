from pathlib import Path
import hashlib,importlib.util,json,shutil,subprocess,sys
R=Path(__file__).resolve().parents[3];TASK=Path(__file__).resolve().parent;OLD=R/'artifacts/validation/v104-three-candidate-performance-20261020';mode=sys.argv[1];assert mode=='performance';O=TASK/'performance-idle-metal3-retest';O.mkdir(exist_ok=False)
read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();pin=lambda p:dict(path=str(p),sha256=sha(p))
def save(p,d):p.write_text(json.dumps(d,indent=2)+'\n')
old=read(OLD/'preparation.json')
for name in ['controller.lua','scene.txt','benchmark-bootstrap.cjs','metal-bootstrap.cjs','content-files.json','content-receipt.json','launcher-main-sha256.json','screen-guard-locked-allowed.py','libhidden-fullscreen.dylib','sdl-hidden-preflight.json','inventory-digest.mjs']:shutil.copy2(OLD/name,O/name)
shutil.copytree(OLD/'inputs',O/'inputs')
if mode=='diagnostic':
 p=O/'metal-bootstrap.cjs';s=p.read_text().replace("MVK_CONFIG_BACKEND_COST_STATS:'0'","MVK_CONFIG_BACKEND_COST_STATS:config.costDiagnostics?'1':'0'").replace('diagnosticsOff:true','diagnosticsOff:!config.costDiagnostics');p.write_text(s)
 apps={'E':R/'artifacts/runtime/v104-lookup-descriptor-diagnostic-20261020/BAR.app'};order=[('metal4','E',False),('metal4','E',True),('metal4','E',False)]
else:
 apps={'C':R/'artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app','Q':R/'artifacts/runtime/v104-quiescent-allocator-candidate-20261021/BAR.app'};order=[('metal3',r,False) for r in ['C','Q','Q','C']]
spec=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py');inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv);identities={};digests={}
for role,app in apps.items():
 contents=inv.inventory(app);expected=read(TASK/(role+'-inventory.json'));assert contents==expected
 save(O/(role+'-inventory.json'),contents);digest=subprocess.check_output(['/opt/homebrew/bin/node',str(O/'inventory-digest.mjs'),str(app)],text=True).strip();digests[str(app)]=digest;identities[role]=dict(app=str(app),version='1.0.3',localCandidate='v1.0.4',inventoryDigest=digest)
protected=read(OLD/'protected-inputs.json');protected['apps']=digests
for v in protected['userState'].values():v['sha256']=sha(v['path'])
save(O/'protected-inputs.json',protected)
launcher=R/'sources/bar-lobby';save(O/'protected-source-launcher.json',dict(sourcePins=read(TASK/'review-pins.json'),HEAD=subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip(),indexSHA256=sha(launcher/'.git/index'),status=subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)))
save(O/'authorization.json',dict(humanTask='User explicitly requests fresh Metal3 remeasurement as well, after work has finished; run C Q Q C four new sessions and combine with the completed fresh Metal4 four. Compare frozen C with C plus quiescent last-use reset Q, Metal3/4 two sessions each, matched AC+Low Power safe-fullscreen hidden conditions. Product is frozen; no compilation or GPU fixtures during FPS.',order=order,maximumGameSessions=len(order),automaticRetry=False,mode=mode))
plans=[]
for ordinal,(backend,role,cost) in enumerate(order,1):
 t=next(x for x in old['plans'] if x['role']=='C' and x['backend']==backend);folder=O/f'{ordinal}-{role}-{backend}';folder.mkdir();schema=f'v104-quiescent-idle-metal3-retest-{mode}-{ordinal}-{role}-{backend}-v1';app=apps[role];templateApp=old['apps']['C']['app']
 def adapt(s):return s.replace(t['folder'],str(folder)).replace(str(OLD),str(O)).replace(t['schema'],schema).replace(templateApp,str(app))
 plan=json.loads(adapt(Path(t['plan']['path']).read_text()));plan.update(benchmarkRole={'C':'parent','Q':'r41'}[role],comparisonVariant=role,testIdentity=folder.name,authorization=pin(O/'authorization.json'),protectedApps=[dict(app=a,inventorySha256=h) for a,h in digests.items()],costDiagnostics=cost,limits=['Same qualified scene/seed/controller/settings/cache/900 sim frames','All final comparison builds cost statistics compiled OFF; no new allocator collector','C baseline preserved; Q changes only genuine zero-use reset policy and keeps count32/growth2MiB/available8/idle64MiB; no historical FPS pooled']);plan['app']=dict(app=str(app),inventorySha256=digests[str(app)])
 for data in plan['lanes'].values():data['engine']['sha256']=sha(data['engine']['path']);data['engine']['bytes']=Path(data['engine']['path']).stat().st_size
 plan['buildDigest']=plan['lanes']['lobby']['engine']['sha256']
 host=adapt(Path(t['host']['path']).read_text())
 host=host.replace('receipt.timing.hostBenchmarkElapsedMs=benchmarkFinishAt-benchmarkStartAt;','receipt.timing.hostBenchmarkElapsedMs=benchmarkFinishAt-benchmarkStartAt;receipt.timing.benchmarkStartUnixMS=benchmarkStartAt;receipt.timing.benchmarkFinishUnixMS=benchmarkFinishAt;')
 if mode=='diagnostic':
  host=host.replace('nativeMetal4:plan.nativeMetal4,disableAsyncWait:','nativeMetal4:plan.nativeMetal4,costDiagnostics:plan.costDiagnostics,disableAsyncWait:')
  host=host.replace("if(/\\[mvk-(?:metal4-(?:queue-)?stats|backend-cost)/.test(text))throw Error('Unexpected runtime performance diagnostics during ordinary benchmark');","if(/\\[mvk-metal4-(?:queue-)?stats/.test(text))throw Error('Unexpected batch/queue stats'); if(plan.costDiagnostics!==/\\[mvk-backend-cost/.test(text))throw Error('Cost collector requested/actual mismatch');")
  host=host.replace('routes[0].diagnosticsOff!==true','routes[0].diagnosticsOff!==!plan.costDiagnostics')
 hostfile=folder/'effective-host.mjs';hostfile.write_text(host)
 def repin(v):
  if isinstance(v,list):return [repin(x) for x in v]
  if isinstance(v,dict):
   z={k:repin(x) for k,x in v.items()}
   if 'path' in z and 'sha256' in z:z['sha256']=sha(z['path'])
   return z
  return v
 plan=repin(plan);save(folder/'plan.json',plan);subprocess.run(['/opt/homebrew/bin/node','--check',str(hostfile)],check=True,capture_output=True);plans.append(dict(ordinal=ordinal,role=role,backend=backend,costDiagnostics=cost,folder=str(folder),schema=schema,plan=pin(folder/'plan.json'),host=pin(hostfile)))
runner=(OLD/'run-comparison.py').read_text();runner=runner.replace("assert len(prep['plans'])==12",f"assert len(prep['plans'])=={len(order)}").replace("item['ordinal']<12",f"item['ordinal']<{len(order)}").replace('len(results)==12',f'len(results)=={len(order)}').replace("'maximumGameSessions':12",f"'maximumGameSessions':{len(order)}");(O/'run-comparison.py').write_text(runner)
save(O/'preparation.json',dict(plans=plans,apps=identities,order=order,mode=mode,noSampler=True,resolution=dict(width=1512,height=950),previousEvidence=str(OLD),hostChanges='Private paths/pins/roles plus Unix benchmark boundary timestamps. Diagnostic only: explicit collector opt-in and actual-route/absence validation. No shutdown/measurement/controller change.'))
print('Prepared',mode,len(plans),'sessions')
