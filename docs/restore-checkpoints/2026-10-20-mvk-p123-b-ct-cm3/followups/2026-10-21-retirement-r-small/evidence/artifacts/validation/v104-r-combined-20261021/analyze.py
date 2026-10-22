from pathlib import Path
import json, hashlib, statistics, subprocess, importlib.util, datetime

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
P = O / 'performance'
read = lambda p: json.loads(Path(p).read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
prep, outcome, before = read(P/'preparation.json'), read(P/'outcome.json'), read(O/'performance-before.json')
assert outcome['status'] == 'completed' and len(outcome['results']) == 8
assert [p['role'] for p in prep['plans']] == ['R', 'Combined', 'Combined', 'R', 'Combined', 'R', 'R', 'Combined']
assert subprocess.check_output(['/usr/bin/sw_vers'], text=True) == before['osSwVers']
rows, powers, conditions = [], [], None
for item, a in zip(prep['plans'], outcome['results']):
    assert item['backend'] == ('metal3' if item['ordinal']<=4 else 'metal4')
    for key in ['plan', 'host']:
        assert sha(item[key]['path']) == item[key]['sha256']
    plan, r = read(item['plan']['path']), read(a['receipt'])
    b = r['benchmark']; m = b['benchmark']
    assert r['status'] == 'completed-not-promoted' and r['protectedInputsUnchanged']
    assert r['powerConditionsPassed'] and not r['remainingOwnedProcesses']
    assert r['loadedRuntimeLibraries']['verified'] and r['runtimeEnvironment']['diagnosticsOff']
    assert r['app'] == before['apps'][item['role']]
    assert (m['startFrame'], m['endFrame'], m['simulationFrames']) == (240, 1140, 900)
    assert b['resolution'] == dict(width=1512, height=950) and b['camera']['name'] == 'spring'
    assert r['fullscreenMode']['window'] == dict(width=1512, height=982)
    assert r['fullscreenMode']['viewport'] == dict(width=1512, height=950)
    assert all(r['fullscreenMode'][k] for k in ['gameFullscreen', 'SDLFullscreen', 'SDLHidden'])
    assert r['officialNativeReport']['present']
    if item['backend']=='metal4':
        assert r['nativeMetal4']['requested'] and r['nativeMetal4']['proved'] and r['nativeMetal4']['activeQueues'] > 0
    else:
        assert not r['nativeMetal4']['requested'] and r['nativeMetal4']['activeQueues'] == 0
    actual = {k:b[k] for k in ['quality', 'camera', 'resolution', 'seed', 'workload', 'officialCommand', 'game', 'map']}
    if conditions is None: conditions = actual
    assert actual == conditions
    expected = {p['path']:p['sha256'] for p in plan['sharedRuntime']}
    for lib in r['loadedRuntimeLibraries']['libraries']:
        assert lib['sha256'] == expected[lib['path']]
    for p in r['powerObservations']:
        assert p['passed'] and p['isLowPowerModeEnabled'] and "'AC Power'" in p['battery']
        powers.append(dict(ordinal=item['ordinal'], thermal=p['thermalState']))
    assert a['fps'] == m['drawIntervals']['meanFPS']
    rows.append(dict(ordinal=item['ordinal'], role=item['role'], backend=item['backend'], app=r['app'],
                     displayedVersion='1.0.3', localCandidate='v1.0.4', FPS=a['fps'], p95Ms=a['p95Ms'],
                     p99Ms=a['p99Ms'], drawIntervals=m['drawIntervals']['count'], simulationFrames=900,
                     receipt=a['receipt'], receiptSHA256=sha(a['receipt']),
                     benchmarkStartUnixMS=r['timing']['benchmarkStartUnixMS']))
groups = {}
for backend in ['metal3','metal4']:
    g={}
    for role in ['R','Combined']:
        rr=[r for r in rows if r['role']==role and r['backend']==backend];assert len(rr)==2
        g[role]=dict(FPS=[r['FPS'] for r in rr],meanFPS=statistics.mean(r['FPS'] for r in rr),meanP95Ms=statistics.mean(r['p95Ms'] for r in rr))
    g['Combined']['changeFromRPercent']=(g['Combined']['meanFPS']/g['R']['meanFPS']-1)*100
    groups[backend]=g
for rel, h in before['sourcePins'].items(): assert sha(R/rel) == h, rel
assert sha(R/'build/metal4-mvk-20261002/CMakeCache.txt') == before['CMakeCacheSHA256']
assert sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib') == before['rawSHA256']
assert read(R/'artifacts/runtime/v104-local-candidate.json') == before['currentCandidate']
for role, app in before['apps'].items(): assert sha(Path(app)/before['libraryRelativePath']) == before['packageSHA256'][role]
for p in read(P/'protected-inputs.json')['userState'].values(): assert sha(p['path']) == p['sha256']
src = read(P/'protected-source-launcher.json'); launcher = R/'sources/bar-lobby'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip() == src['HEAD']
assert sha(launcher/'.git/index') == src['indexSHA256']
assert subprocess.check_output(['git','status','--short'],cwd=launcher,text=True) == src['status']
spec = importlib.util.spec_from_file_location('inv',R/'tools/lib/run95_app_transaction.py')
inv = importlib.util.module_from_spec(spec); spec.loader.exec_module(inv)
for role, app in before['apps'].items(): assert inv.inventory(Path(app)) == read(O/(role+'-inventory.json'))
guard = read(P/'screen-guard.json'); assert guard['restored'] and guard['awakeReleased']
cleanup = [read(P/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,9)]
assert all(c['allAbsent'] for c in cleanup)
summary = dict(status='completed-R-versus-R-D-E1-E2-E3-Metal3-Metal4-comparison', groups=groups, executionOrder=rows,
               apps=prep['apps'], conditions=conditions, nPerApp=2, powerObservations=len(powers),
               thermalStates=sorted(set(p['thermal'] for p in powers)), osSwVers=before['osSwVers'],
               sourceBuildCombinedPreserved=True, appsRCombinedInventoriesExact=True, userProfilesAndLauncherExact=True,
               screenRestored=True, awakeReleased=True, selectedCandidate='R-unchanged-before-decision',
               cleanup=dict(roots=sum(c['rootsRemoved'] for c in cleanup), leaves=sum(c['leavesRemoved'] for c in cleanup),
                            logicalBytes=sum(c['logicalBytesRemoved'] for c in cleanup), physicalBytesMeasured=False),
               limitations=['n2 per app; user/OS background load and clocks not fully controlled.',
                            'Same OS build throughout this comparison; recent RC update may affect historical absolute FPS.',
                            'No allocator frequency/time/peak memory benefit inferred from FPS.',
                            'Both Metal3 and Metal4 are newly benchmarked; no earlier FPS pooled.',
                            'Existing sampled native-exit and timestamp mismatch cases not claimed repaired.'])
(O/'comparison-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
lines = ['# R 대 R+D+E1+E2+E3 통합 후보 비교', '',
         '기준 R과 R+전체(D+E1+E2+E3)를 비교했다. 추가 변경은 D 자원등록 lookup 재사용/compile-OFF 계측 소스, E1 불변 binding 준비 계획, E2 최종 Metal4 render descriptor 직접 구성, E3 같은 compute encoder의 이미 발행한 prior-queue barrier 범위 재사용이다. Q의 genuine last-use reset과 R의 idle-first 선택을 유지하고 allocator32/growth2MiB/available8/idle64MiB를 바꾸지 않았다.', '',
         '네 단위를 exact context로 순서대로 적용하고 각 단계 전후 hash를 기존 단위와 대조했다. E32의 비allocator9파일과 PreparedResource D가 일치하며, Submission.mm는 동결D+R의 두 allocator 함수와 byte-exact임을 독립 검수했다. 따라서 기존 E32만 실행한 결과가 아니다.', '',
         '새 통합 raw에서 관련 CPU/ASan/UBSan·foundation/private guard syntax 및 실제 Metal/Vulkan 검사를 실행했다. E1 plan432, E2 descriptor parity20728, 기존descriptor629/OFF134, visibility3구성, E3 actual emission2097163 및 dependency524606/prepared4916882 확인을 통과했다. D allocation14/registration416/diagnosticsOFF3, allocatorCPU1027/native6(12fill/signal/guard완료와12reset 및idle선택), native resource등록6, Vulkan15개씩Metal3/4, prepared3와compacttemplate각backend1사례를 통과했다. 테스트 수는 해당 CPU/mock/actual GPU 범위이며 전체 conformance를 뜻하지 않는다.', '',
         '앱 모두표시1.0.3/local v1.0.4 후보. AC+절전모드·Ultra·AA Off·Spring·VSync Off·sound off,1512×982 hidden SDL fullscreen/노치제외1512×950/default1x. 같은 scene/seed/controller·실행별새privateprofile/coldcache, 각900simulationframes240→1140. diagnostics compile/runtime OFF, sampler/capture OFF. macOS27.2 build26B118 전후동일.', '',
         '| 순서 | 경로 | 앱 | FPS | p95 ms | draw 간격 표본 | simulation frames |',
         '|---:|---|---|---:|---:|---:|---:|']
for r in rows:
    label='R+전체' if r['role']=='Combined' else 'R'
    lines.append(f"| {r['ordinal']} | {r['backend']} | {label} | {r['FPS']:.3f} | {r['p95Ms']:.3f} | {r['drawIntervals']} | 900 |")
lines+=['', '| 경로 | 앱 | 두 실행 FPS | 평균 FPS | R 대비 | p95 평균 ms |','|---|---|---:|---:|---:|---:|']
for backend,g in groups.items():
    for role,a in g.items():
        change='—' if role=='R' else f"{a['changeFromRPercent']:+.3f}%";label='R+전체' if role=='Combined' else 'R'
        lines.append(f"| {backend} | {label} | {a['FPS'][0]:.3f} / {a['FPS'][1]:.3f} | {a['meanFPS']:.3f} | {change} | {a['meanP95Ms']:.3f} |")
lines+=['',f"총8회모두정상종료. 전원관측{len(powers)}개/thermal{summary['thermalStates']}. 소스·빌드·앱inventory/실제로딩runtime·launcherHEAD/index/status·사용자프로필 보존, screen/awake복구 및 성공cache정리를 확인했다.",'',
        '추가 prepared fixture의 첫 컴파일은 MVKFoundation 헤더 경로 누락으로 실행 전에 중단됐고, 활성 Ninja의 실제 includes/defines를 추가한 두 번째 컴파일 후 통과했다. 최초 오류와 수정 명령을 보존했다. 제품 빌드는 첫 시도에 통과했고 제품/fixture source는 검증 중 변경하지 않았다.','',
        '각앱/backend n2이며 평균FPS/p95는 실행별 요약의 산술평균이다. OS/사용자부하/클럭을 완전히 통제하지 않았으며 반복인과효과·메모리절감·MP/다른Mac안정성을 확정하지 않는다. 묶음의 순효과를 비교했으며 D/E1/E2/E3 개별기여와 시너지를 분리 입증하지 않는다. 기존timestamp mismatch와sampled-exit 실패는이번결과로해결됐다고주장하지않는다.','']
for role,app in before['apps'].items():lines.append('- '+('R+전체' if role=='Combined' else 'R')+': `'+app+'`')
report=R/'reports/v104-r-combined-20261021.md';report.write_text('\n'.join(lines)+'\n')
(O/'completion.json').write_text(json.dumps(dict(status='R-combined-implemented-validated-compared',completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),report=str(report),reportSHA256=sha(report),groups=groups,currentCandidateUnchanged=True,candidatePromoted=False),indent=2)+'\n')
print(json.dumps(groups,indent=2))
