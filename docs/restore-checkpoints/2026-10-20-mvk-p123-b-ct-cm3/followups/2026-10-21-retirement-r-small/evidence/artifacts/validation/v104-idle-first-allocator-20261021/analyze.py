from pathlib import Path
import json, hashlib, statistics, subprocess, importlib.util, datetime

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
P = O / 'performance'
read = lambda p: json.loads(Path(p).read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
prep, outcome, before = read(P/'preparation.json'), read(P/'outcome.json'), read(O/'performance-before.json')
assert outcome['status'] == 'completed' and len(outcome['results']) == 4
assert [p['role'] for p in prep['plans']] == ['Q', 'R', 'R', 'Q']
assert subprocess.check_output(['/usr/bin/sw_vers'], text=True) == before['osSwVers']
rows, powers, conditions = [], [], None
for item, a in zip(prep['plans'], outcome['results']):
    assert item['backend'] == 'metal4'
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
    assert r['nativeMetal4']['requested'] and r['nativeMetal4']['proved'] and r['nativeMetal4']['activeQueues'] > 0
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
    rows.append(dict(ordinal=item['ordinal'], role=item['role'], backend='metal4', app=r['app'],
                     displayedVersion='1.0.3', localCandidate='v1.0.4', FPS=a['fps'], p95Ms=a['p95Ms'],
                     p99Ms=a['p99Ms'], drawIntervals=m['drawIntervals']['count'], simulationFrames=900,
                     receipt=a['receipt'], receiptSHA256=sha(a['receipt']),
                     benchmarkStartUnixMS=r['timing']['benchmarkStartUnixMS']))
groups = {}
for role in ['Q', 'R']:
    rr = [r for r in rows if r['role'] == role]; assert len(rr) == 2
    groups[role] = dict(FPS=[r['FPS'] for r in rr], meanFPS=statistics.mean(r['FPS'] for r in rr),
                        meanP95Ms=statistics.mean(r['p95Ms'] for r in rr))
groups['R']['changeFromQPercent'] = (groups['R']['meanFPS']/groups['Q']['meanFPS']-1)*100
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
cleanup = [read(P/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,5)]
assert all(c['allAbsent'] for c in cleanup)
summary = dict(status='completed-Q-R-idle-first-Metal4-comparison', groups=groups, executionOrder=rows,
               apps=prep['apps'], conditions=conditions, nPerApp=2, powerObservations=len(powers),
               thermalStates=sorted(set(p['thermal'] for p in powers)), osSwVers=before['osSwVers'],
               sourceBuildRPreserved=True, appsQRInventoriesExact=True, userProfilesAndLauncherExact=True,
               screenRestored=True, awakeReleased=True, selectedCandidate='Q-unchanged-before-decision',
               cleanup=dict(roots=sum(c['rootsRemoved'] for c in cleanup), leaves=sum(c['leavesRemoved'] for c in cleanup),
                            logicalBytes=sum(c['logicalBytesRemoved'] for c in cleanup), physicalBytesMeasured=False),
               limitations=['n2 per app; user/OS background load and clocks not fully controlled.',
                            'Same OS build throughout this comparison; recent RC update may affect historical absolute FPS.',
                            'No allocator frequency/time/peak memory benefit inferred from FPS.',
                            'Metal3 path unchanged; no unrelated Metal3 FPS suite repeated.',
                            'Existing sampled native-exit and timestamp mismatch cases not claimed repaired.'])
(O/'comparison-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
lines = ['# Q 이후 R — allocator idle 우선 선택', '',
         'R은 Q의 마지막 사용 종료 reset을 유지하고, available 최대8개 중 liveUses0인 allocator를 우선 선택한다. 마지막 항목이 idle이면 기존 빠른 경로, 모두 사용 중이면 기존 LIFO다. 소유권·reset 조건·기록32/growth2MiB/available8/idle64MiB·잠금·pass·동기화 정책은 그대로다.', '',
         '제품 변경은 MVKMetal4Submission.mm의 takeAllocatorLocked 한 함수다. 기존 CPU fixture의 실제 구현 ASan+UBSan1027 checks와 native6cases(기존12fill/readback/signal/reset + 새 독립 allocator 출력/미제출 기록 보존 사례)를 통과했다. 동결 Q에 동일 새 선택 검사를 대조하면 해당 선택 assertion에서 예상대로 실패하여 정책 차이를 구별했다.', '',
         '표시 버전 모두1.0.3/local v1.0.4 후보. AC+절전모드·Ultra·AA Off·Spring·VSync Off·sound off,1512×982 hidden SDL fullscreen/노치제외1512×950/default1x, 같은 scene/seed/controller/새 private profile/cold cache. 각900 simulation frames240→1140. diagnostics/sampler/capture OFF. OS macOS27.2 build26B118 전후 동일.', '',
         '| 순서 | 앱 | FPS | p95 ms | draw 간격 표본 | simulation frames |',
         '|---:|---|---:|---:|---:|---:|']
for r in rows: lines.append(f"| {r['ordinal']} | {r['role']} | {r['FPS']:.3f} | {r['p95Ms']:.3f} | {r['drawIntervals']} | 900 |")
lines += ['', '| 앱 | 두 실행 FPS | 평균 FPS | Q 대비 | p95 평균 ms |', '|---|---:|---:|---:|---:|']
for role, g in groups.items():
    change = '—' if role=='Q' else f"{g['changeFromQPercent']:+.3f}%"
    lines.append(f"| {role} | {g['FPS'][0]:.3f} / {g['FPS'][1]:.3f} | {g['meanFPS']:.3f} | {change} | {g['meanP95Ms']:.3f} |")
lines += ['', f"네 실행 전부 정상 종료, 전원관측{len(powers)}개/thermal{summary['thermalStates']}. 앱·소스·빌드·실제 로딩 runtime·launcher·사용자 프로필 보존 및 screen/awake 복구·성공 캐시 정리를 확인했다.", '',
          'n2의 관측값이며 반복 인과 효과·메모리 절감·다른 Mac/MP 안정성을 확정하지 않는다. macOS RC 업그레이드에 대한 사용자 관측은 과거 회차의 절대 FPS에 영향을 줄 수 있는 가설로 남기며, 이번 동일 OS의 Q/R 비교와 혼합하지 않는다. Metal3 FPS는 변경 경로 밖이라 반복하지 않았다.', '',
          '대조 검사·포장 준비의 초기 경로/include 오류 두 건은 실행 전 수정했으며 원본 오류·수정 근거를 preparation-corrections.json에 보존했다. 최종 제품·CPU·native·패키지 검증은 통과했다.', '']
for role, app in before['apps'].items(): lines.append('- '+role+': `'+app+'`')
report = R/'reports/v104-idle-first-allocator-20261021.md'; report.write_text('\n'.join(lines)+'\n')
(O/'completion.json').write_text(json.dumps(dict(status='R-implemented-validated-and-compared',
    completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), report=str(report),
    reportSHA256=sha(report), groups=groups, selectedCandidateBeforeDecision='Q', candidatePromoted=False),indent=2)+'\n')
print(json.dumps(groups,indent=2))
