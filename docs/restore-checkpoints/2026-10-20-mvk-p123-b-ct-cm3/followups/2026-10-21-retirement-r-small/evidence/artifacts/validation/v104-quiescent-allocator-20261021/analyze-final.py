from pathlib import Path
import json,statistics,hashlib,subprocess,importlib.util,datetime
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;P=O/'performance';read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();P=O/'performance';F=O/'performance-idle-metal4';base=read(P/'preparation.json');fresh=read(F/'preparation.json');priorOutcome=read(P/'outcome.json');freshOutcome=read(F/'outcome.json');T=O/'performance-idle-metal3-retest';retest=read(T/'preparation.json');retestOutcome=read(T/'outcome.json')
assert priorOutcome['status']=='completed' and len(priorOutcome['results'])==8
assert freshOutcome['status']=='completed' and len(freshOutcome['results'])==4
assert retestOutcome['status']=='completed' and len(retestOutcome['results'])==4
assert base['apps']==fresh['apps']==retest['apps']
idle=read(O/'human-idle-confirmation.json');grant=read(O/'additional-metal3-retest-grant.json');pairs=list(zip(fresh['plans'],freshOutcome['results']))+list(zip(retest['plans'],retestOutcome['results']))
plans=[];results=[]
for ordinal,(item,result) in enumerate(pairs,1):
 item=dict(item,sourceOrdinal=item['ordinal'],sourcePhase='fresh-metal4' if ordinal<=4 else 'fresh-metal3-retest',ordinal=ordinal)
 assert sha(item['plan']['path'])==item['plan']['sha256'] and sha(item['host']['path'])==item['host']['sha256']
 receipt=read(result['receipt']);assert receipt['timing']['benchmarkStartUnixMS']>=idle['confirmedIdleAtUnixMS']
 if ordinal>4:assert receipt['timing']['benchmarkStartUnixMS']>=grant['registeredUnixMS']
 plans.append(item);results.append(result)
prep=dict(apps=base['apps'],plans=plans);out=dict(results=results)
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
 rows.append(dict(ordinal=item['ordinal'],role=item['role'],backend=item['backend'],app=r['app'],version='1.0.3',FPS=a['fps'],p95Ms=a['p95Ms'],p99Ms=a['p99Ms'],drawIntervals=m['drawIntervals']['count'],simulationFrames=900,receipt=a['receipt'],receiptSHA256=sha(a['receipt']),sourcePhase=item['sourcePhase'],sourceOrdinal=item['sourceOrdinal'],benchmarkStartUnixMS=r['timing']['benchmarkStartUnixMS']))
prior=read(R/'artifacts/validation/v104-lookup-descriptor-20261020/comparison-summary.json');assert conditions==prior['conditions']
groups={}
for backend in ['metal3','metal4']:
 g={}
 for role in ['C','Q']:
  rr=[r for r in rows if r['backend']==backend and r['role']==role];assert len(rr)==2;g[role]=dict(FPS=[r['FPS'] for r in rr],meanFPS=statistics.mean(r['FPS'] for r in rr),meanP95Ms=statistics.mean(r['p95Ms'] for r in rr))
 for role in ['Q']:g[role]['changeFromCPercent']=(g[role]['meanFPS']/g['C']['meanFPS']-1)*100
 groups[backend]=g
for p in read(P/'protected-inputs.json')['userState'].values():assert sha(p['path'])==p['sha256']
src=read(P/'protected-source-launcher.json');before=read(O/'performance-before.json');expected=before['sourcePins']
for rel,h in expected.items():assert sha(R/rel)==h,rel
assert sha(R/'build/metal4-mvk-20261002/CMakeCache.txt')==before['CMakeCacheSHA256']
assert read(R/'artifacts/runtime/v104-local-candidate.json')==before['currentCandidate']
for role,f in before['packageSHA256'].items():assert sha(Path(before[role+'Package']))==f
assert sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib')==before['rawSHA256']
launcher=R/'sources/bar-lobby';assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==src['HEAD'];assert sha(launcher/'.git/index')==src['indexSHA256'];assert subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)==src['status']
spec=importlib.util.spec_from_file_location('inv',R/'tools/lib/run95_app_transaction.py');inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv)
for role,app in prep['apps'].items():assert inv.inventory(Path(app['app']))==read(P/(role+'-inventory.json'))
guard=read(P/'screen-guard.json');secondGuard=read(F/'screen-guard.json');assert all(g['restored'] and g['awakeReleased'] for g in [guard,secondGuard,read(T/'screen-guard.json')])
cleanup=[read(P/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,9)]+[read(F/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,5)]+[read(T/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,5)];assert len(cleanup)==16 and all(d['allAbsent'] for d in cleanup)
s=dict(status='completed-8-C-Q-quiescent-comparison-sessions',groups=groups,executionOrder=rows,apps=prep['apps'],conditions=conditions,powerObservations=len(power),thermalStates=sorted(set(p['thermal'] for p in power)),sourceBuildQPreserved=True,appsCQInventoriesExact=True,userProfilesAndLauncherExact=True,screenRestored=True,awakeReleased=True,sourceBindings=read(O/'performance-before.json'),cleanup=dict(roots=sum(d['rootsRemoved'] for d in cleanup),leaves=sum(d['leavesRemoved'] for d in cleanup),logicalBytes=sum(d['logicalBytesRemoved'] for d in cleanup),physicalBytesMeasured=False),nPerAppBackend=2,limitations=['Small n2 per app/backend, OS/user background load not fully controlled.','All diagnostics compiled OFF. Q changes only genuine quiescent last-use reset; no peak-memory benefit inferred from FPS.','Historical FPS not pooled; timestamp and sampled-exit unresolved cases not claimed repaired.','SDL native display/Space transition deferred while hidden; 1512x950 safe default1x drawable.'])
s['humanBackgroundInterference']=read(O/'human-background-interference.json');s['idleConfirmation']=idle;s['comparisonSelection']='All four fresh Metal4 sessions plus all four fresh Metal3 retest sessions; previous original eight are reference only. User explicitly requested new Metal3; old primary preserved in pre-metal3-rerun.';s['metal3RetestGrant']=grant;s['totalCompletedSessions']=16;s['primarySessions']=8;s['referenceSessions']=8;s['limitations'].append('Human confirmed own work finished; no claim all OS/background load is zero. Metal3 differences are not direct effects of the Metal4-only allocator policy.')
(O/'comparison-summary.json').write_text(json.dumps(s,indent=2));print(json.dumps(groups,indent=2))
lines=['# C/Q Metal3·4 새 재측정 — 2026-10-21','', 'C 기준에 마지막 사용 종료 시 allocator 초기화 조건만 추가한 Q다. 기록 수32/growth2MiB/available8/idle64MiB를 유지하며 E1/E2/E3와 D 변경은 포함하지 않는다. C 재빌드 raw가 기존C와 byte-exact임을 먼저 확인했고, Q 제품 diff는 submission.mm 한 hunk다.','', 'CPU ASan+UBSan 실제 구현 916checks(기존 count/growth 경계와 새7cases), 실제 Metal native5cases(반복fill/readback/signal12회와회수12회, blocked/cancel/poison/다중제출/대기중수명)를 통과했다. 추가 collector는 없다. Q1194 app entries, MVK와서명3파일변경,211closure/strictdeep signature 검증을 마쳤다.','', '표시 버전 모두1.0.3/local v1.0.4 후보다. AC+절전모드, Ultra/AA Off/Spring/VSync Off/sound off,1512×950 safe viewport/1512×982 hidden SDL fullscreen/default1x, 동일privateprofile/coldcache/scene/seed/controller, 각900simulationframes240→1140, sampler/collector/capture OFF.','']
for backend,g in groups.items():
 lines+=['| backend | 앱 | 두 실행 FPS | 평균 FPS | C 대비 | p95 평균 ms |','|---|---|---:|---:|---:|---:|']
 for role in ['C','Q']:
  a=g[role];change='—' if role=='C' else f"{a['changeFromCPercent']:+.3f}%";lines.append(f"| {backend} | {role} | {a['FPS'][0]:.3f} / {a['FPS'][1]:.3f} | {a['meanFPS']:.3f} | {change} | {a['meanP95Ms']:.3f} |")
 lines+=['']
lines+=['| 순서 | backend | 앱 | FPS | draw 간격 표본 | simulation frames |','|---:|---|---|---:|---:|---:|']
for a in rows:lines.append(f"| {a['ordinal']} | {a['backend']} | {a['role']} | {a['FPS']:.3f} | {a['drawIntervals']} | 900 |")
lines+=['',f"전원관측{s['powerObservations']}개 thermal{s['thermalStates']},8회 정상 종료. 앱/backend별 n2이며 평균은 per-run FPS/p95 산술평균이다. 배경 부하가 완전히 통제되지 않아 작은 차이를 확정 이득·회귀로 판정하지 않는다. FPS로 peak memory/MP/다른 Mac 안정성을 입증하지 않는다. 소스/빌드·launcher/사용자프로필·앱 원문/실제 로딩 runtime·screen/awake 복구·성공 캐시 정리를 확인했다.",'']
lines+=['사용자가 다른 작업 종료를 확인한 뒤 새로 측정한 Metal4 4회와, Metal3도 다시 측정하라는 추가 지시 후 새로 측정한 Metal3 4회를 본 비교로 사용했다. 순서는 Metal4 C→Q→Q→C, Metal3 C→Q→Q→C이며 각4회 전부 포함했다. 모든 측정 구간의 시작 시각이 작업 종료 확인 이후이고 새 Metal3는 추가 지시 등록 이후임을 검증했다. 최초8회와 기존합산본은 참고 기록으로 보존했다. 총16회 정상실행 중 최종8회만 본 비교에 포함했다. OS 전체 무부하나 작은 FPS 차이의 인과성을 입증하지 않는다.','']
for role,app in prep['apps'].items():lines.append('- '+role+': `'+app['app']+'`')
lines+=['','판정: C를 기준 후보로 유지하고 Q는 실험 후보로 보존한다. 새 Metal3 평균은 C52.654/Q52.597(-0.109%), 새 Metal4 평균은 C46.568/Q46.952(+0.823%)다. 각2회만으로 지속적인 성능 이득이나 회귀를 확정할 수 없다. 특히 Metal3 차이는 Metal4 전용 allocator 조건의 직접 효과로 볼 수 없다. 메모리 절감은 계측하지 않았다. 현재 소스/빌드는 검증한 Q 상태로 동결되어 있고, 실제 선택 후보 포인터는 C 그대로다. 이전 E64의 원래 소스와 raw 스냅샷도 보존했다.','']
report=R/'reports/v104-quiescent-allocator-20261021.md';report.write_text('\n'.join(lines)+'\n');(O/'completion.json').write_text(json.dumps(dict(status='Q-implementation-fresh-metal3-metal4-retest-complete',completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),report=str(report),reportSHA256=sha(report),groups=groups,currentCandidateUnchanged=True,candidatePromoted=False),indent=2));print(report)
