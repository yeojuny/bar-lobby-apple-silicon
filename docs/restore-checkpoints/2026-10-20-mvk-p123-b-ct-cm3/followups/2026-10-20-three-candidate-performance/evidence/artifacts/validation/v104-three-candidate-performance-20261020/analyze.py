from pathlib import Path
import hashlib, importlib.util, json, statistics, subprocess

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
read = lambda p: json.loads(Path(p).read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
prep = read(O/'preparation.json'); outcome = read(O/'outcome.json')
assert outcome['status']=='completed' and len(outcome['results'])==12, outcome
rows=[]; power=[]; first=None
for result,item in zip(outcome['results'],prep['plans']):
    assert result['ordinal']==item['ordinal']
    receipt=read(result['receipt']); plan=read(item['plan']['path']); b=receipt['benchmark']; measurement=b['benchmark']
    assert receipt['status']=='completed-not-promoted' and receipt['protectedInputsUnchanged'] and receipt['powerConditionsPassed']
    assert not receipt['remainingOwnedProcesses'] and receipt['loadedRuntimeLibraries']['verified']
    assert receipt['app']==prep['apps'][item['role']]['app']
    assert b['resolution']=={'width':1512,'height':950} and b['camera']['name']=='spring'
    assert (measurement['startFrame'],measurement['endFrame'],measurement['simulationFrames'])==(240,1140,900)
    assert receipt['fullscreenMode']['window']=={'width':1512,'height':982}
    assert receipt['fullscreenMode']['viewport']=={'width':1512,'height':950}
    assert all(receipt['fullscreenMode'][k] for k in ('gameFullscreen','SDLFullscreen','SDLHidden'))
    assert receipt['officialNativeReport']['present'] and receipt['runtimeEnvironment']['diagnosticsOff']
    expected={p['path']:p['sha256'] for p in plan['sharedRuntime']}
    for lib in receipt['loadedRuntimeLibraries']['libraries']: assert expected[lib['path']]==lib['sha256']
    native=receipt['nativeMetal4']
    if item['backend']=='metal4': assert native['requested'] and native['activeQueues']>0 and native['proved']
    else: assert not native['requested'] and native['activeQueues']==0
    comparison={k:b[k] for k in ('quality','camera','resolution','seed','workload','officialCommand','game','map')}
    if first is None:first=comparison
    assert comparison==first, (item['ordinal'],'scene/quality difference')
    for p in receipt['powerObservations']:
        assert p['passed'] and "'AC Power'" in p['battery'] and p['isLowPowerModeEnabled']
        power.append({'ordinal':item['ordinal'],'thermal':p['thermalState'],'source':'AC','lowPower':True})
    rows.append(dict(ordinal=item['ordinal'],role=item['role'],backend=item['backend'],app=receipt['app'],
        version=prep['apps'][item['role']]['version'],fps=result['fps'],p95Ms=result['p95Ms'],p99Ms=result['p99Ms'],
        receipt=result['receipt'],receiptSHA256=sha(result['receipt']),drawIntervals=measurement['drawIntervals']['count'],
        loadedMvk=next(p for p in receipt['loadedRuntimeLibraries']['libraries'] if 'libMoltenVK' in p['path'])))
groups={}
for backend in ('metal3','metal4'):
    groups[backend]={}
    for role in ('A','B','C'):
        rr=[r for r in rows if r['backend']==backend and r['role']==role];assert len(rr)==2
        groups[backend][role]=dict(app=prep['apps'][role]['app'],version=prep['apps'][role]['version'],
            fps=[r['fps'] for r in rr],meanFPS=statistics.mean(r['fps'] for r in rr),
            meanP95Ms=statistics.mean(r['p95Ms'] for r in rr),meanP99Ms=statistics.mean(r['p99Ms'] for r in rr))
    g=groups[backend]
    for role in ('B','C'):
        previous='A' if role=='B' else 'B'
        g[role]['FPSChangeFromPreviousPercent']=(g[role]['meanFPS']/g[previous]['meanFPS']-1)*100
        g[role]['p95ChangeFromPreviousPercent']=(g[role]['meanP95Ms']/g[previous]['meanP95Ms']-1)*100
    g['C']['FPSChangeFromAPercent']=(g['C']['meanFPS']/g['A']['meanFPS']-1)*100
protected=read(O/'protected-inputs.json')
for p in protected['userState'].values():assert sha(p['path'])==p['sha256']
source=read(O/'protected-source-launcher.json')
for p,h in source['sourcePins'].items():assert sha(R/p)==h
launcher=R/'sources/bar-lobby'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==source['HEAD']
assert sha(launcher/'.git/index')==source['indexSHA256']
assert subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)==source['status']
spec=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py'); inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv)
for role,a in prep['apps'].items():assert inv.inventory(Path(a['app']))==read(O/(role+'-inventory.json'))
guard=read(O/'screen-guard.json');assert guard['restored'] and guard['awakeReleased']
cleanup=[read(O/f'arm-{n}-cache-cleanup-completion.json') for n in range(1,13)]
assert all(c['allAbsent'] and c['logsResultsAndMarkdownPreserved'] for c in cleanup)
summary=dict(status='completed-12-matched-hidden-fullscreen-sessions',apps=prep['apps'],groups=groups,executionOrder=rows,
    conditions=first,powerObservations=len(power),thermalStates=sorted(set(p['thermal'] for p in power)),
    screenRestored=True,awakeReleased=True,protectedAppsSourcesLauncherAndUserProfilesExact=True,
    cleanup=dict(roots=sum(c['rootsRemoved'] for c in cleanup),leaves=sum(c['leavesRemoved'] for c in cleanup),
        logicalBytes=sum(c['logicalBytesRemoved'] for c in cleanup),physicalBytesMeasured=False),
    nPerAppBackend=2,meanMethod='Arithmetic mean of two per-run FPS/p95/p99 summaries; percentiles are not pooled.',
    limitations=['Small n=2, hidden presentation with SDL native display/Space transition deferred.',
        'New games may complete normally without resolving the prior separate sampled-exit failure.',
        'Earlier concurrent-work FPS and native fixture timestamp mismatch are not pooled or claimed fixed.'],
    installed=False,appPromoted=False)
(O/'comparison-summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n')
lines=['# 세 후보 성능 비교 — 2026-10-20','',
    'A는 C-REG까지, B는 A+화면 크기 조회 최적화, C는 B+typed Buffer 등록 호출부 수정이다. 표시 버전은 모두 1.0.3이며 로컬 v1.0.4 후보들이다.',
    '', 'AC 전원·절전모드 ON, Ultra·AA Off·Spring·VSync Off·sound off. 실제 BAR.app→Lobby→번들 엔진, 동일 장면·seed·900 simulation frames(240→1140), 실행마다 private profile/cold cache. logical container 1512×982, safe viewport 1512×950, 기본 1× drawable, Fullscreen=1 및 SDL fullscreen intent를 유지하면서 창만 숨겼다. SDL native display/Space 전환은 숨긴 동안 유예된다.',
    '', '| backend | 앱 | 버전 | 1회 FPS | 2회 FPS | 평균 FPS | p95 평균 ms |',
    '|---|---|---|---:|---:|---:|---:|']
for backend,g in groups.items():
    for role,d in g.items():
        lines.append(f"| {backend} | {role} | {d['version']} | {d['fps'][0]:.2f} | {d['fps'][1]:.2f} | **{d['meanFPS']:.2f}** | {d['meanP95Ms']:.2f} |")
lines+=['','| 변경 | Metal3 평균 FPS 변화 | Metal4 평균 FPS 변화 |','|---|---:|---:|']
for role,label in [('B','A→B 화면 크기 조회'),('C','B→C 버퍼 등록')]:
    lines.append(f"| {label} | {groups['metal3'][role]['FPSChangeFromPreviousPercent']:+.2f}% | {groups['metal4'][role]['FPSChangeFromPreviousPercent']:+.2f}% |")
lines+=['', 'B의 두 실행은 두 backend에서 모두 A의 두 실행보다 높았다. Metal4의 C 두 실행도 B 두 실행보다 높았고, Metal3의 C/B는 실행별 방향이 엇갈려 추가 이익을 구분하기 어렵다. 이 장면의 n=2 관측이며 다른 부하·장면으로 일반화하지 않는다.',
    '', '| 순서 | backend | 앱 | simulation frames | 렌더 간격 표본 수 | 평균 FPS |',
    '|---:|---|---|---:|---:|---:|']
for row in rows:
    lines.append(f"| {row['ordinal']} | {row['backend']} | {row['role']} | 900 | {row['drawIntervals']} | {row['fps']:.2f} |")
lines+=['', '900은 simulation frame 수(240→1140)이고, 렌더 간격 표본 수는 해당 구간에 수집한 DrawScreen 간격 수다. GPU draw call 수나 고유 자원 수가 아니다.', '', '각 후보 경로:']
for role,app in prep['apps'].items():lines.append(f"- {role}: `{app['app']}`")
lines+=['', '실행 순서: M3 A→B→C→C→B→A, M4 C→B→A→A→B→C. 12회 모두 정상 종료했고 실제 backend·라이브러리 해시·뷰포트·품질·보호 입력을 검증했다.',
    f"전원 관측 {len(power)}개, thermalState {summary['thermalStates']}. 시험 종료 후 화면 보호 설정과 awake assertion을 복원했다. 성공 실행의 재생성 가능한 private cache {summary['cleanup']['roots']} roots/{summary['cleanup']['leaves']} leaves/{summary['cleanup']['logicalBytes']} logical bytes를 정리했다. 물리 회수량으로 해석하지 않는다. 각 실행의 임시 content clone 정리는 execution receipt에 별도 기록돼 있다.",
    '', '표본은 후보·backend별 2회다. 평균 FPS 및 percentile은 실행별 값의 산술 평균이며 전체 프레임을 합친 percentile이 아니다. 역순으로 완화했지만 OS/사용자 동시 부하까지 통제한 실험은 아니다. 과거 동시 작업이 섞인 수치와 합산하지 않는다. 이전 sampled 종료 실패와 Metal3 timestamp fixture 불일치는 이번 비교로 원인이 해소됐다고 보지 않는다.',
    '', '원본 결과·조건·로드된 앱/라이브러리 및 정상 종료 근거는 `artifacts/validation/v104-three-candidate-performance-20261020/`에 있다. 제품 코드/앱 수정·설치는 없었다.']
(R/'reports/v104-three-candidate-performance-20261020.md').write_text('\n'.join(lines)+'\n')
print(json.dumps(dict(groups=groups,powerObservations=len(power),thermalStates=summary['thermalStates'],cleanup=summary['cleanup']),indent=2))
