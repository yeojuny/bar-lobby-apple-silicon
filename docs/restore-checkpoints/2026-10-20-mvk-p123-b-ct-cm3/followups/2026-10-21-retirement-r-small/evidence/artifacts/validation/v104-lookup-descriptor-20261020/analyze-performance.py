from pathlib import Path
import json,statistics,hashlib,subprocess,importlib.util
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;P=O/'performance';read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();prep=read(P/'preparation.json');out=read(P/'outcome.json');assert out['status']=='completed' and len(out['results'])==8
rows=[];conditions=None;power=[]
for item,a in zip(prep['plans'],out['results']):
 r=read(a['receipt']);b=r['benchmark'];m=b['benchmark'];assert r['status']=='completed-not-promoted' and r['protectedInputsUnchanged'] and r['powerConditionsPassed'] and not r['remainingOwnedProcesses'];assert r['loadedRuntimeLibraries']['verified'] and r['runtimeEnvironment']['diagnosticsOff'];assert r['app']==prep['apps'][item['role']]['app'];assert b['resolution']==dict(width=1512,height=950) and b['camera']['name']=='spring';assert (m['startFrame'],m['endFrame'],m['simulationFrames'])==(240,1140,900)
 assert r['fullscreenMode']['window']==dict(width=1512,height=982) and r['fullscreenMode']['viewport']==dict(width=1512,height=950);assert all(r['fullscreenMode'][k] for k in ['gameFullscreen','SDLFullscreen','SDLHidden']);assert r['officialNativeReport']['present']
 actual={k:b[k] for k in ['quality','camera','resolution','seed','workload','officialCommand','game','map']}
 if conditions is None:conditions=actual
 assert actual==conditions
 plan=read(item['plan']['path']);expected={p['path']:p['sha256'] for p in plan['sharedRuntime']}
 for lib in r['loadedRuntimeLibraries']['libraries']:assert lib['sha256']==expected[lib['path']]
 for p in r['powerObservations']:assert p['passed'] and "'AC Power'" in p['battery'] and p['isLowPowerModeEnabled'];power.append(dict(ordinal=item['ordinal'],thermal=p['thermalState']))
 rows.append(dict(ordinal=item['ordinal'],role=item['role'],backend=item['backend'],app=r['app'],version='1.0.3',FPS=a['fps'],p95Ms=a['p95Ms'],p99Ms=a['p99Ms'],drawIntervals=m['drawIntervals']['count'],simulationFrames=900,receipt=a['receipt'],receiptSHA256=sha(a['receipt'])))
groups={}
for backend in ['metal3','metal4']:
 g={}
 for role in ['C','D']:
  rr=[r for r in rows if r['backend']==backend and r['role']==role];assert len(rr)==2;g[role]=dict(FPS=[r['FPS'] for r in rr],meanFPS=statistics.mean(r['FPS'] for r in rr),meanP95Ms=statistics.mean(r['p95Ms'] for r in rr))
 g['changePercent']=(g['D']['meanFPS']/g['C']['meanFPS']-1)*100;groups[backend]=g
protected=read(P/'protected-inputs.json')
for p in protected['userState'].values():assert sha(p['path'])==p['sha256']
src=read(P/'protected-source-launcher.json');before=read(O/'before.json');expected={**before['sourcePins'],**before['additionalReadPins'],**read(O/'review-pins.json')}
for rel,h in expected.items():assert sha(R/rel)==h,rel
launcher=R/'sources/bar-lobby';assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==src['HEAD'];assert sha(launcher/'.git/index')==src['indexSHA256'];assert subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)==src['status']
spec=importlib.util.spec_from_file_location('inv',R/'tools/lib/run95_app_transaction.py');inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv)
for role,app in prep['apps'].items():assert inv.inventory(Path(app['app']))==read(P/(role+'-inventory.json'))
for mode in ['diagnostic','performance']:
 guard=read(O/mode/'screen-guard.json');assert guard['restored'] and guard['awakeReleased']
summary=dict(status='completed-eight-matched-release-OFF-sessions',groups=groups,executionOrder=rows,apps=prep['apps'],conditions=conditions,powerObservations=len(power),thermalStates=sorted(set(p['thermal'] for p in power)),CAndDAppInventoriesExact=True,userProfilesAndSourcePinsExact=True,launcherHEADIndexStatusExact=True,nPerAppBackend=2,meanMethod='Arithmetic mean of per-run FPS and p95 summaries; p95 is not pooled.',screenIdleRestored=True,awakeReleased=True,limitations=['Small sample n=2 per app/backend; OS and user background load not fully controlled.','Hidden SDL fullscreen rendering with native display/Space transition deferred; logical container1512x982 safeviewport1512x950 default1x.','Historical FPS not pooled; previous sampled native-exit failure and M3 timestamp mismatch are not claimed repaired.'])
(O/'comparison-summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False));print(json.dumps(groups,indent=2));print('All app/source/launcher/user profile preservation checks passed.')
