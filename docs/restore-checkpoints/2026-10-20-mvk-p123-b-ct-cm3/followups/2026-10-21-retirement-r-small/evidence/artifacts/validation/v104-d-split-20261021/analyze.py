from pathlib import Path
import json,statistics,hashlib,subprocess,importlib.util,datetime
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;P=O/'performance';read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();prep=read(P/'preparation.json');out=read(P/'outcome.json');assert out['status']=='completed' and len(out['results'])==12
rows=[];conditions=None;power=[]
for item,a in zip(prep['plans'],out['results']):
 r=read(a['receipt']);b=r['benchmark'];m=b['benchmark'];assert r['status']=='completed-not-promoted' and r['protectedInputsUnchanged'] and r['powerConditionsPassed'] and not r['remainingOwnedProcesses'];assert r['loadedRuntimeLibraries']['verified'] and r['runtimeEnvironment']['diagnosticsOff'];assert r['app']==prep['apps'][item['role']]['app'];assert b['resolution']==dict(width=1512,height=950) and b['camera']['name']=='spring';assert (m['startFrame'],m['endFrame'],m['simulationFrames'])==(240,1140,900)
 assert r['fullscreenMode']['window']==dict(width=1512,height=982) and r['fullscreenMode']['viewport']==dict(width=1512,height=950);assert all(r['fullscreenMode'][k] for k in ['gameFullscreen','SDLFullscreen','SDLHidden']);assert r['officialNativeReport']['present']
 actual={k:b[k] for k in ['quality','camera','resolution','seed','workload','officialCommand','game','map']}
 if conditions is None:conditions=actual
 assert actual==conditions
 plan=read(item['plan']['path']);expected={p['path']:p['sha256'] for p in plan['sharedRuntime']}
 for lib in r['loadedRuntimeLibraries']['libraries']:assert lib['sha256']==expected[lib['path']]
 native=r['nativeMetal4'];assert native['requested']==(item['backend']=='metal4')
 if item['backend']=='metal4':assert native['proved'] and native['activeQueues']>0
 else:assert native['activeQueues']==0
 for p in r['powerObservations']:assert p['passed'] and "'AC Power'" in p['battery'] and p['isLowPowerModeEnabled'];power.append(dict(ordinal=item['ordinal'],thermal=p['thermalState']))
 rows.append(dict(ordinal=item['ordinal'],role=item['role'],backend=item['backend'],app=r['app'],version='1.0.3',FPS=a['fps'],p95Ms=a['p95Ms'],p99Ms=a['p99Ms'],drawIntervals=m['drawIntervals']['count'],simulationFrames=900,receipt=a['receipt'],receiptSHA256=sha(a['receipt'])))
prior=read(R/'artifacts/validation/v104-lookup-descriptor-20261020/comparison-summary.json');assert conditions==prior['conditions']
groups={}
for backend in ['metal3','metal4']:
 g={}
 for role in ['C','L','S']:
  rr=[r for r in rows if r['backend']==backend and r['role']==role];assert len(rr)==2;g[role]=dict(FPS=[r['FPS'] for r in rr],meanFPS=statistics.mean(r['FPS'] for r in rr),meanP95Ms=statistics.mean(r['p95Ms'] for r in rr))
 for role in ['L','S']:g[role]['changeFromCPercent']=(g[role]['meanFPS']/g['C']['meanFPS']-1)*100
 groups[backend]=g
for p in read(P/'protected-inputs.json')['userState'].values():assert sha(p['path'])==p['sha256']
src=read(P/'protected-source-launcher.json');before=read(O/'before.json');expected={**before['originalSourcePins'],**before['sourcePins']}
for rel,h in expected.items():assert sha(R/rel)==h,rel
assert sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib')==before['rawSHA256']
launcher=R/'sources/bar-lobby';assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==src['HEAD'];assert sha(launcher/'.git/index')==src['indexSHA256'];assert subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)==src['status']
spec=importlib.util.spec_from_file_location('inv',R/'tools/lib/run95_app_transaction.py');inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv)
for role,app in prep['apps'].items():assert inv.inventory(Path(app['app']))==read(P/(role+'-inventory.json'))
assert inv.inventory(Path(before['DApp']))==read(O/'D-inventory.json');guard=read(P/'screen-guard.json');assert guard['restored'] and guard['awakeReleased']
cleanup=[read(P/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,13)];assert all(d['allAbsent'] for d in cleanup)
s=dict(status='completed-12-single-patch-comparison-sessions',groups=groups,executionOrder=rows,apps=prep['apps'],conditions=conditions,powerObservations=len(power),thermalStates=sorted(set(p['thermal'] for p in power)),sourceBuildDExactRestored=True,appsCLSDInventoriesExact=True,userProfilesAndLauncherExact=True,screenRestored=True,awakeReleased=True,buildComparison=read(O/'build-comparison.json'),cleanup=dict(roots=sum(d['rootsRemoved'] for d in cleanup),leaves=sum(d['leavesRemoved'] for d in cleanup),logicalBytes=sum(d['logicalBytesRemoved'] for d in cleanup),physicalBytesMeasured=False),nPerAppBackend=2,limitations=['Small n2 per app/backend, OS/user background load not fully controlled.','Stats-only compile OFF removes new counts; standard text/data sections equal C but linker stub differences exist.','Historical FPS not pooled; timestamp and sampled-exit unresolved cases not claimed repaired.','SDL native display/Space transition deferred while hidden; 1512x950 safe default1x drawable.'])
(O/'comparison-summary.json').write_text(json.dumps(s,indent=2));print(json.dumps(groups,indent=2))
lines=['# D 두 변경의 개별 비교 — 2026-10-21','', 'C는 기존 typed Buffer까지, L은 C+동일등록 lookup 재사용만, S는 C+9개 계측 소스만(compile OFF)이다. D는 기존 두 패치 결합 후보이며 이번에는 C/L/S를 실제 비교했다. 표시 버전 모두1.0.3인 local v1.0.4 후보다. E 큰 구조 설계는 별도 진행이며 이 비교에 포함되지 않는다.','', 'C/L/S/D는 하나의 기존 source/build lane에서 순차 빌드했다. C 재빌드 raw는 기존C와 byte-exact, 마지막D 복구 raw도 기존D와 byte-exact. S와C의 __TEXT,__text 및 일반 data sections는 동일하고, L과D도 동일하다. 두 쌍 모두 linker stub sections만 차이가 있고 dyld fixup 목록은 동일했다. 따라서 S를 새 counter가 실행돼서 드는 비용으로 해석하지 않는다. 전체 바이너리가 byte-exact라는 주장도 하지 않는다.','', 'AC+LowPower, Ultra/AA Off/Spring/VSync Off/sound off,1512x950 safe/default1x hidden SDL fullscreen, private profile/cold cache, same scene/seed/controller,900simframes240→1140, sampler/collector/capture OFF.','', '| backend | 앱 | 두 실행 FPS | 평균 FPS | C 대비 | p95 평균 ms |','|---|---|---:|---:|---:|---:|']
for backend,g in groups.items():
 for role in ['C','L','S']:
  a=g[role];change='—' if role=='C' else f"{a['changeFromCPercent']:+.3f}%";lines.append(f"| {backend} | {role} | {a['FPS'][0]:.3f} / {a['FPS'][1]:.3f} | {a['meanFPS']:.3f} | {change} | {a['meanP95Ms']:.3f} |")
lines+=['','| 순서 | backend | 앱 | FPS | draw 간격 표본 | simulation frames |','|---:|---|---|---:|---:|---:|']
for a in rows:lines.append(f"| {a['ordinal']} | {a['backend']} | {a['role']} | {a['FPS']:.3f} | {a['drawIntervals']} | 900 |")
lines+=['', f"전원관측{s['powerObservations']}개 thermal{s['thermalStates']},12회정상종료. 앱/backend별n2, 평균은 per-run FPS/p95 산술평균이며 pooled percentile이 아니다. 원문/앱·실제runtime·소스D복구·launcher/userprofile·screen/awake·성공cache정리를 검증했다. 큰 구조E는 이 자료에 섞지 않았다."]
for role,app in prep['apps'].items():lines.append('- '+role+': `'+app['app']+'`')
report=R/'reports/v104-d-split-20261021.md';report.write_text('\n'.join(lines)+'\n');(O/'completion.json').write_text(json.dumps(dict(status='split-comparison-complete-E-work-separate',completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),report=str(report),reportSHA256=sha(report),groups=groups,currentCandidate='C',candidatePromoted=False),indent=2));print(report)
