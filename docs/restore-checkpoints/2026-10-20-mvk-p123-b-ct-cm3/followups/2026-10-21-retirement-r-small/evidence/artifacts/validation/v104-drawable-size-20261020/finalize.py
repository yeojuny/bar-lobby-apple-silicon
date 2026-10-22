from pathlib import Path
import hashlib, importlib.util, json, plistlib, re, statistics, subprocess

ROOT=Path(__file__).resolve().parents[3]
IMPL=Path(__file__).resolve().parent
PERF=ROOT/'artifacts/validation/v104-drawable-size-performance-20261020'
OBS=ROOT/'artifacts/validation/v104-drawable-size-observation-20261020'
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,d):
    with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
prep=read(PERF/'preparation.json');outcome=read(PERF/'outcome.json')
assert outcome['status']=='completed' and len(outcome['results'])==8
records=[];conditions=[];thermal=[]
for row in outcome['results']:
    receipt=read(row['receipt']);b=receipt['benchmark']
    assert receipt['status']=='completed-not-promoted' and receipt['protectedInputsUnchanged'] and not receipt['remainingOwnedProcesses']
    assert receipt['powerConditionsPassed'] and receipt['strictHiddenWindow'] and receipt['loadedRuntimeLibraries']['verified']
    assert 'cpuSample' not in receipt
    assert b['benchmark']['simulationFrames']==900 and b['benchmark']['startFrame']==240 and b['benchmark']['endFrame']==1140
    assert b['resolution']=={'width':1512,'height':950}
    full=receipt['fullscreenMode'];assert full['gameFullscreen'] and full['SDLFullscreen'] and full['SDLHidden']
    assert full['viewport']==b['resolution'] and full['window']=={'width':1512,'height':982}
    assert b['quality']['ultraVerified'] and b['quality']['glSamples']==0
    native=receipt['nativeMetal4'];assert native['requested']==(row['backend']=='metal4')
    if row['backend']=='metal4':assert native['proved'] and native['activeQueues']>=1
    else:assert native['activeQueues']==0
    plan=read(PERF/f'{row["ordinal"]}-{row["role"]}-{row["backend"]}'/'plan.json')
    for lib in receipt['loadedRuntimeLibraries']['libraries']:assert lib in plan['sharedRuntime']
    actual_engine=Path(plan['lanes']['lobby']['engine']['path']);assert sha(actual_engine)==plan['lanes']['lobby']['engine']['sha256']
    for power in receipt['powerObservations']:
        assert power['passed'] and power['isLowPowerModeEnabled'] and "'AC Power'" in power['battery']
        thermal.append(power['thermalState'])
    condition={k:b[k] for k in ['camera','resolution','game','map','seed','officialCommand']}
    condition['qualityConfig']=b['quality']['config'];condition['qualityOptions']=b['quality']['optionValues'];conditions.append(condition)
    records.append({**row,'receiptSHA256':sha(row['receipt']),'engine':plan['lanes']['lobby']['engine'],'fullscreenMode':full,'drawIntervals':b['benchmark']['drawIntervals']})
assert all(x==conditions[0] for x in conditions),'Workload/quality/camera differs'
groups={}
for backend in ['metal3','metal4']:
    groups[backend]={}
    for role in ['parent','candidate']:
        rows=[x for x in records if x['backend']==backend and x['role']==role];assert len(rows)==2
        groups[backend][role]={'ordinals':[x['ordinal'] for x in rows],'fps':[x['fps'] for x in rows],'meanFPS':statistics.mean(x['fps'] for x in rows),'meanRunP95Ms':statistics.mean(x['p95Ms'] for x in rows),'meanRunP99Ms':statistics.mean(x['p99Ms'] for x in rows)}
    p,c=groups[backend]['parent'],groups[backend]['candidate']
    groups[backend]['deltaFPSPercent']=(c['meanFPS']/p['meanFPS']-1)*100
    groups[backend]['deltaP95Percent']=(c['meanRunP95Ms']/p['meanRunP95Ms']-1)*100
cleanup=[]
for base,count in [(PERF,8)]:
    result=read(base/'outcome.json');assert result['status']=='completed' and len(result['results'])==count
    guard=read(base/'screen-guard.json');assert guard['restored'] and guard['awakeReleased'] and guard['beforeIdleTime']==guard['afterIdleTime']
    for ordinal in range(1,count+1):
        item=read(base/f'arm-{ordinal}-cache-cleanup-completion.json');assert item['allAbsent'];cleanup.append(item)
observed=read(read(OBS/'outcome.json')['results'][0]['receipt'])
assert observed['status']=='failed' and observed['protectedInputsUnchanged'] and not observed['remainingOwnedProcesses']
assert read(OBS/'outcome.json')['status']=='stopped'
observation_guard=read(OBS/'screen-guard.json')
assert observation_guard['restored'] and observation_guard['awakeReleased'] and observation_guard['beforeIdleTime']==observation_guard['afterIdleTime']
boundary=read(OBS/'exit-boundary-review.json')
assert boundary['samplerHadExitedBeforeQuit'] and boundary['cause'].startswith('Not established')
sample=observed['cpuSample'];assert sample['exitCode']==0 and not sample['usedForFPSComparison'] and sha(sample['output'])==sample['sha256']
text=Path(sample['output']).read_text()
stack=[];active=False;coordinate=0;full_below=0;ipc_below=0;fast=0;full_total=0;relevant=[]
for line_number,line in enumerate(text.splitlines(),1):
    if line=='Call graph:':active=True;continue
    if line.startswith('Total number in stack'):break
    if not active:continue
    match=re.match(r'^([ +!:\|]*?)(\d+) (.*)$',line)
    if not match:continue
    prefix,count,frame=match.groups();depth=len(prefix);count=int(count)
    while stack and stack[-1][0]>=depth:stack.pop()
    hot=bool(re.search(r'CGlobalRendering::LoadDefaultFramebuffer(?:Viewport|Scissor)\(',frame))
    inside=any(s[1] for s in stack)
    if hot and not inside:coordinate+=count
    if 'MacSDL3EGL::QueryWindowDrawableSize(' in frame:fast+=count
    if 'MacSDL3EGL::QueryDisplayGeometry(' in frame:
        full_total+=count
        if inside:full_below+=count
    if 'get_current_display_system_state(' in frame and inside:ipc_below+=count
    if hot or 'QueryWindowDrawableSize' in frame or ('QueryDisplayGeometry' in frame and inside):relevant.append({'line':line_number,'count':count,'frame':frame})
    stack.append((depth,hot,frame))
sample_summary={'sample':sample,'exitBoundary':boundary,'observationRuntimeAcceptance':False,'coordinateConversionInclusiveObservations':coordinate,'fastSizeInclusiveObservations':fast,'fullGeometryObservationsBelowCoordinateConversion':full_below,'windowServerObservationsBelowCoordinateConversion':ipc_below,'fullGeometryInclusiveObservationsAllPaths':full_total,'relevantFrames':relevant,'limitations':['Sample collection and benchmark completed, but the separate run exceeded the15-second native exit boundary; cause unresolved, sampled process had already exited before quit.','One short sample of hidden fullscreen Metal4 only; not native display/Space transition testing.','Stack observations are not calls, milliseconds or FPS attribution. Inlining and sampling can hide short functions.','FPS from this sampled run is excluded from comparison; remaining full-geometry callers are intentional.']}
save(OBS/'sample-analysis.json',sample_summary)
before=read(IMPL/'before.json');pins=read(IMPL/'review-pins.json');review=read(IMPL/'independent-review.json')
assert review['verdict']=='PASS' and not review['actionableFindings'] and not review['blockers']
binding=read(PERF/'review-and-package-binding.json')
assert sha(IMPL/'independent-review.json')==binding['independentReview']['sha256']
assert sha(IMPL/'package-receipt.json')==binding['package']['sha256']
assert review['reviewedPins']['currentSources']==pins
for relative,h in {**before['protectedPins'],**pins}.items():assert sha(ROOT/relative)==h,relative
for info in before['lanes'].values():
    for name in ['CMakeCache.txt','build.ninja']:
        relative=info['build']+'/'+name;assert sha(ROOT/relative)==before['selectedFiles'][relative],relative
for lane in before['lanes']:
    for relative,h in read(IMPL/(lane+'-build-input-pins.json')).items():assert sha(ROOT/relative)==h,relative
launcher=ROOT/'sources/bar-lobby'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==before['launcher']['HEAD']
assert sha(launcher/'.git/index')==before['launcher']['indexSHA256']
assert subprocess.check_output(['git','status','--porcelain'],cwd=launcher,text=True)==before['launcher']['status']
for item in read(PERF/'protected-inputs.json')['userState'].values():assert sha(item['path'])==item['sha256']
spec=importlib.util.spec_from_file_location('inventory',ROOT/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
versions={}
for role in ['parent','candidate']:
    app=Path(prep[role]);assert m.inventory(app)==read(PERF/(role+'-inventory.json'))
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes());versions[role]={'app':str(app),'CFBundleShortVersionString':info['CFBundleShortVersionString'],'CFBundleVersion':info['CFBundleVersion']}
summary={'status':'completed','resolution':conditions[0]['resolution'],'order':prep['order'],'groups':groups,'records':records,'conditions':conditions[0],'thermalStates':sorted(set(thermal)),'powerObservationCount':len(thermal),'nPerAppBackend':2,'sampledRunExcluded':True,'nativeSpaceTransitionDeferredWhileHidden':True,'concurrentUserWorkload':read(PERF/'user-workload-note.json'),'method':'Arithmetic means of two run FPS; p95/p99 are means of per-run percentiles, not pooled percentiles. Concurrent user workload: reference only, no isolated causal gain or statistical significance claimed.'}
save(PERF/'comparison-summary.json',summary)
result={'status':'implemented-reviewed-compared-observation-exit-unresolved','product':'Live window/drawable size query on cumulative P1/P2/P3+B+C-T+C-M3+C-REG','sourcePins':pins,'appVersions':versions,'validation':{'CPUChecksPerLane':102,'CPUASanUBSan':True,'nativeBuilds':2,'independentReview':'PASS;0 actionable findings','dependencyClosureEdges':211,'deepStrictSignature':True,'successfulReferenceGameRuns':8,'separateObservationExitAccepted':False},'review':{'path':str(IMPL/'independent-review.json'),'sha256':sha(IMPL/'independent-review.json')},'performance':{'path':str(PERF/'comparison-summary.json'),'groups':groups,'nPerAppBackend':2},'sample':sample_summary,'cacheCleanup':{'roots':sum(c['rootsRemoved'] for c in cleanup),'leaves':sum(c['leavesRemoved'] for c in cleanup),'logicalBytes':sum(c['logicalBytesRemoved'] for c in cleanup),'failedObservationCachesPreserved':True,'physicalReclaimNotMeasured':True},'protectedPinsAndSourcesExact':True,'parentAndCandidateInventoriesExact':True,'launcherHeadIndexStatusExact':True,'userProfilesExact':True,'formalReleasePublished':False,'restorationCheckpoint':'pending'}
save(IMPL/'completion.json',result)
lines=['# 화면 크기 조회 경량화 — 2026-10-20','',
       'C-REG 누적 후보 위에 두 엔진의 viewport/scissor 전용 live 창·drawable 크기 조회를 적용했다. 기존 전체 화면 배치·노치·Retina 정책과 자원·동기화 계약은 유지한다.','',
       '기존 전체 QueryDisplayGeometry는 변경하지 않았다. 새 QueryWindowDrawableSize는 logical 크기와 현재 CAMetalLayer drawableSize만 읽고, layer가 없거나 비어 있으면 기존 NativeCocoaDrawableScale을 적용한다. 캐시를 추가하지 않아 창 크기·화면·배율 변경은 매번 현재 값으로 읽는다. 별도 FBO는 기존 우회 경로, 좌표 반올림도 동일하다.','',
       '표시 버전은 두 앱 모두 **1.0.3**, 로컬 **v1.0.4 누적 후보**다. 기존 P1/P2/P3+B+C-T+C-M3+C-REG가 모두 들어 있다.','',
       f'- 기존 앱: `{prep["parent"]}`',f'- 수정 앱: `{prep["candidate"]}`','',
       '기존 display CPU fixture53개를 현재 소스에 바인딩하고 실제 새 helper/viewport/scissor/scale 함수를 포함한 ASan/UBSan 검사 **각102개(두 엔진)**가 통과했다. SDL/Screen/GL은 mock이며 UpdateViewPortGeometry는 기존 single-screen prefix만 검사한다. 두 기존 native build에서 bridge와 GlobalRendering 각2개 object만 재컴파일·링크했고, 공식 sync identity와 BAR-1.0.3 표시는 동일하다. 독립 Astra+High 검수는 actionable findings0. 앱1194항목 중 엔진2개+서명2개만 달라졌으며 dependency closure211개와 deep strict signature를 확인했다.','',
       '## 같은 조건 성능 비교','',
       '실제 실행은 BAR.app→Lobby→bundled Lobby 엔진 경로다. Chobby 엔진은 이번 CPU·빌드·CLI·패키지 검증까지이며 새 Chobby 게임 검증으로 세지 않는다. AC 전원·Low Power ON, Ultra·AA Off·Spring·VSync Off·sound off. 게임 Fullscreen=1, 숨김 창 container1512×982, safe viewport1512×950, 기본1×drawable. 동일 Seths Ravine/BAR test31671·seed·frame240→1140·900simulationframes. 각 실행 독립 profile/cold cache. controller·guard·fullscreen adapter는 직전 비교와 byte-identical.','',
       f'순서: **{prep["order"]}**. CPU sampling은 이8회와 분리했다. 사용자가 측정 중 다른 작업을 하고 있다고 확인했다. 따라서 아래 값은 동시 작업 부하가 섞인 참고 결과이며 코드만의 인과적 FPS 개선율로 확정하지 않는다. 첫 기존 Metal4 값이 이전 비교보다 낮은 기록도 제외하지 않고 모두 보존했다.','',
       '| 백엔드 | 앱 | 1회 FPS | 2회 FPS | 평균 FPS | 실행별 p95 평균 ms |','|---|---|---:|---:|---:|---:|']
for backend in ['metal3','metal4']:
    for role,label in [('parent','기존 C-REG 누적'),('candidate','기존+화면 크기 조회 경량화')]:
        g=groups[backend][role];lines.append(f'| {backend} | {label} | {g["fps"][0]:.2f} | {g["fps"][1]:.2f} | {g["meanFPS"]:.2f} | {g["meanRunP95Ms"]:.2f} |')
lines+=['',f'Metal3 평균 FPS **{groups["metal3"]["deltaFPSPercent"]:+.2f}%**, p95 **{groups["metal3"]["deltaP95Percent"]:+.2f}%**. Metal4 평균 FPS **{groups["metal4"]["deltaFPSPercent"]:+.2f}%**, p95 **{groups["metal4"]["deltaP95Percent"]:+.2f}%**. 각 앱/백엔드2회이며 일반화·통계적 유의성·무위험 순이익은 주장하지 않는다. p95는 실행별 percentile의 평균이다.','',
        'SDL은 숨긴 창의 fullscreen 의도를 유지하면서 실제 macOS display/Space 전환은 표시될 때까지 유예한다. 실제 모니터 이동/Space전환/다른 Mac의 입력·표시 회귀를 이 숨김 비교로 검증했다고 주장하지 않는다. CPU fixture는 화면 크기·배율·safe-area 계산 동등성을, 실제 게임은 현재 고정 환경의 렌더링 진행과 설정·종료를 확인했다.','',
        '## 별도 비용 관찰','',
        f'새 후보 Metal4만 기존 OS sample10초/1ms 요청으로 관찰했다. 수집과900-frame benchmark는 완료했지만, 이후 native 종료 callback·PID소멸 확인이15초 제한을 넘겼다. sampler 자체는 quit 요청 이전에 정상 종료했다. 원인은 제품 변경·sampler·동시 작업 어느 쪽으로도 확정하지 않았다. 이 실행의 FPS는 위 표에 포함하지 않고, 원본 실패 상태와 private cache를 보존하며 자동 재시도하지 않았다.','',
        f'수집한 stack에서 default-framebuffer viewport/scissor 관측 {coordinate}, 그 아래 전체 geometry 조회 {full_below}, WindowServer display-state 조회 {ipc_below}, 새크기helper 관측 {fast}. 관측 수는 호출 횟수·시간·CPU비중·FPS기여율이 아니며 inlining과 짧은 표본의 한계가 있다. 남아 있는 전체 geometry 조회는 화면 배치 등 다른 경로일 수 있다. 이 표본은 종료까지 통과한 runtime acceptance로 세지 않는다.','',
        '## 보존','',
        f'비교8회는 모두 정상 종료했다. 별도관찰1회는 위 종료확인 실패 뒤 기존 소유권 제한 cleanup이 시험 프로세스를 정리했으며 현재 소유 프로세스는 없다. 성공한8회의 private 재생성 캐시 {result["cacheCleanup"]["roots"]}개 root/{result["cacheCleanup"]["leaves"]}개 leaf/{result["cacheCleanup"]["logicalBytes"]} logical bytes만 정리했고 실패관찰profile/cache는 그대로 보존했다. raw 로그·결과·Markdown·앱·source·이전 raw engine도 보존했다. 물리 회수량은 측정하지 않았다. 실제 launcher HEAD/index/status, 사용자profile3개, 보호핀74개 및 빌드입력1271/1265개가 유지됐다. 공식 Release/Homebrew 갱신과 설치는 하지 않았다.','',
        f'완료 기록: `{IMPL/"completion.json"}`. 성능 원본: `{PERF/"comparison-summary.json"}`. 관찰 원본: `{OBS/"sample-analysis.json"}`. GitHub 복원 보존은 별도 후속 기록으로 연결한다.']
report=ROOT/'reports/v104-drawable-size-20261020.md'
with report.open('x') as f:f.write('\n'.join(lines)+'\n')
print(json.dumps({'groups':groups,'observation':{k:v for k,v in sample_summary.items() if k not in ['sample','relevantFrames','limitations']},'report':str(report)},ensure_ascii=False))
