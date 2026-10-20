from pathlib import Path
import json,hashlib,statistics,subprocess,math,importlib.util,datetime,re
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,d):
 with p.open('x') as f:json.dump(d,f,indent=2,ensure_ascii=False);f.write('\n')
initialOut=read(O/'outcome.json');initialPrep=read(O/'preparation.json');continuationOut=read(O/'continuation-outcome.json');continuationPrep=read(O/'continuation-preparation.json')
assert initialOut['status']=='stopped' and initialOut['results'][2]['fps'] is None
assert continuationOut['status']=='completed' and len(continuationOut['results'])==6
out={**continuationOut,'results':initialOut['results'][:2]+continuationOut['results']}
prep={**initialPrep,'plans':initialPrep['plans'][:2]+continuationPrep['plans']}
for journal in ('screen-guard.json','continuation-screen-guard.json'):
 g=read(O/journal);assert g['restored'] and g['awakeReleased'] and g['beforeIdleTime']==g['afterIdleTime']
guard=read(O/'continuation-screen-guard.json')
assert out['status']=='completed' and len(out['results'])==8 and not out['error'] and not out['screenFailures']
assert guard['restored'] and guard['awakeReleased'] and guard['beforeIdleTime']==guard['afterIdleTime']
rows=[];reference=None;widgets=None
for item,result in zip(prep['plans'],out['results']):
 assert sha(item['plan']['path'])==item['plan']['sha256'] and sha(item['host']['path'])==item['host']['sha256']
 plan=read(item['plan']['path']);receipt=read(result['receipt']);value=receipt['benchmark'];bench=value['benchmark'];stats=bench['drawIntervals']
 assert receipt['status']=='completed-not-promoted' and receipt['protectedInputsUnchanged'] and receipt['gracefulQuit'] and not receipt['remainingOwnedProcesses'] and receipt['powerConditionsPassed']
 assert receipt['loadedRuntimeLibraries']['verified'] and all(x['passed'] and x['isLowPowerModeEnabled'] for x in receipt['powerObservations'])
 assert value['status']=='complete' and not value.get('error') and bench['startFrame']==240 and bench['endFrame']==1140 and bench['simulationFrames']==900
 assert all(math.isclose(x['gameSpeed']['requested'],1) for x in bench['unitCounts'])
 assert math.isclose(result['fps'],stats['meanFPS'])
 current={k:value[k] for k in ('officialCommand','seed','frameTarget','workload','fixture','map','gameVersion','resolution','camera','quality')}
 if reference is None:reference=current
 assert current==reference,(item['ordinal'],'scene or quality drift')
 assert sha(receipt['benchmarkEvidence']['path'])==receipt['benchmarkEvidence']['sha256']
 for p in plan['sharedRuntime']:assert sha(p['path'])==p['sha256']
 log=Path(receipt['officialNativeReport']['nativeLog']['path']).read_text(errors='replace')
 assert '[barwidgets.lua] Error:' not in log and 'gui_run95_luavbo_layout_validation.lua' not in log and 'run95-vbo-request.txt' not in log
 assert not re.search(r'Error in |Failed to compile|failed to compile|Shader.*failed',log)
 loaded=[re.sub(r'^.*Loading widget from ','',line) for line in log.splitlines() if 'Loading widget from ' in line]
 if widgets is None:widgets=loaded
 assert widgets==loaded
 native=re.search(r'\[f=(\d+)\] Benchmark complete, #created = (\d+), #destroyed = (\d+)',log)
 ended=re.search(r'Benchmark ended, (\d+) units spawned over (\d+) gameframes',log)
 assert native and ended
 if item['backend']=='metal4':assert receipt['nativeMetal4']['proved'] and receipt['nativeMetal4']['requested']
 else:assert receipt['nativeMetal4']['activeQueues']==0 and not receipt['nativeMetal4']['requested']
 cleanup=read(O/f'{"continuation-" if item["ordinal"]>=3 else ""}arm-{item["ordinal"]}-cache-cleanup-completion.json');assert cleanup['allAbsent'] and cleanup['logsResultsAndMarkdownPreserved']
 rows.append({**result,'meanMs':stats['meanMs'],'sampleCount':stats['count'],'over50Ms':stats['over50Ms'],'over100Ms':stats['over100Ms'],'wallSeconds':bench['wallSeconds'],'created':int(native[2]),'destroyed':int(native[3]),'officialStopFrame':int(native[1]),'officialWorkloadFrames':int(ended[2]),'thermalStates':sorted({x['thermalState'] for x in receipt['powerObservations']}),'gameSpeed':bench.get('gameSpeed'),'receiptSHA256':sha(result['receipt'])})
groups={}
for backend in ('metal3','metal4'):
 group={}
 for role in ('parent','candidate'):
  rr=[x for x in rows if x['backend']==backend and x['role']==role];assert len(rr)==2
  group[role]={'runFPS':[x['fps'] for x in rr],'meanFPS':statistics.mean(x['fps'] for x in rr),'runP95Ms':[x['p95Ms'] for x in rr],'meanP95Ms':statistics.mean(x['p95Ms'] for x in rr),'runP99Ms':[x['p99Ms'] for x in rr],'meanP99Ms':statistics.mean(x['p99Ms'] for x in rr)}
 group['fpsChangePercent']=(group['candidate']['meanFPS']/group['parent']['meanFPS']-1)*100;groups[backend]=group
spec=importlib.util.spec_from_file_location('inv',R/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for label in ('parent','candidate'):assert m.inventory(Path(prep[label]))==read(O/(label+'-inventory.json'))
for path,pin in read(R/'artifacts/validation/v104-followup-c-t-20261020/review-common-pins.json').items():assert sha(R/path)==pin
for key,pin in read(O/'protected-inputs.json')['userState'].items():assert sha(pin['path'])==pin['sha256']
launcher=R/'sources/bar-lobby';initial=read(R/'artifacts/validation/v103-performance-p1-p3-20261020/before.json')['launcher']
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==initial['head'] and sha(launcher/'.git/index')==initial['index']
assert subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)==initial['status']
cleanup={'previousSelectionAlreadyRetired':True,'newDeletionBeforeThisRerun':False,'priorEvidence':str(R/'artifacts/validation/v104-descriptor-performance-comparison-20261020/pre-measurement-cleanup-completion.json')};ongoing=[read(O/f'{"continuation-" if i>=3 else ""}arm-{i}-cache-cleanup-completion.json') for i in range(1,9)]
summary={'status':'complete','completedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'parentApp':prep['parent'],'candidateApp':prep['candidate'],'comparison':'P1/P2/P3+B versus P1/P2/P3+B+C-T+C-M3; A and vertex cache absent','displayVersionBoth':'1.0.3; local v1.0.4 candidate labels only','conditions':reference,'groups':groups,'samples':rows,'samplesPerAppBackend':2,'average':'Arithmetic average of run FPS; p95/p99 values average per-run quantiles, not pooled percentiles.','widgetCount':len(widgets),'thermalStates':sorted({t for x in rows for t in x['thermalStates']}),'power':'AC Power + Low Power ON throughout','screenRestored':True,'awakeReleased':True,'appsSourcesLauncherAndUserPinsExact':True,'cleanupBefore':cleanup,'cleanupDuring':{'rootsRemoved':sum(x['rootsRemoved'] for x in ongoing),'leavesRemoved':sum(x['leavesRemoved'] for x in ongoing),'logicalBytesRemoved':sum(x['logicalBytesRemoved'] for x in ongoing),'logsResultsPreserved':True},'limitations':['Two runs per app/backend; descriptive differences, no statistical significance or equivalence established.','Hidden 1432x902, audio off, VSync off, cold private shader cache each time. Filesystem/global driver cache and background work are not fully controlled.','900 simulation frames measured at requested speed 1x. Official queued stop acknowledgments recorded separately; FPS uses sampler frame240..1140.','One map/workload/Lobby lane; no public multiplayer or other-Mac acceptance.','C-T/C-M3 cumulative effect only; no isolated contribution or vertex-cache interaction measured.']}
previous=read(R/'artifacts/validation/v104-descriptor-performance-comparison-20261020/summary.json')
summary['previousComparison']={'path':str(R/'artifacts/validation/v104-descriptor-performance-comparison-20261020/summary.json'),'groups':previous['groups']}
observations=[read(O/'preflight.json')['desktop']]+[json.loads(line)['desktop'] for name in ('screen-observations.jsonl','continuation-screen-observations.jsonl') for line in (O/name).read_text().splitlines()]
summary['consoleLockStates']=sorted({str(x['consoleLocked']) for x in observations})
summary['preGameStartupFailure']={'preserved':initialOut['results'][2],'replacementMeasuredSamples':0,'preGameContinuationAttempts':1,'fix':'Only safe read-only stable Lobby readiness; measured controller unchanged'}
summary['limitations'].append('Reverse batch permitted locked console at human direction; prior batch required unlocked console. Lock state may affect OS scheduling; between-batch differences cannot be attributed solely to app order.')
save(O/'summary.json',summary)
lines=['# C-T·C-M3 누적 후보 역순 성능 비교 — 2026-10-20','','이전 P1/P2/P3+B 후보와 C-T/C-M3 추가 후보를 전원 연결·저전력 ON의 동일 조건에서 새로 비교했다. 정점 바인딩 캐시는 어느 쪽에도 없다. 이전의 다른 후보 측정값은 평균에 섞지 않았다.','','| 백엔드 | 이전 후보 평균 FPS | C-T·C-M3 후보 평균 FPS | 변화 | 이전 p95 ms | 신규 p95 ms |','|---|---:|---:|---:|---:|---:|']
for name,g in groups.items():lines.append(f"| {name} | {g['parent']['meanFPS']:.2f} | {g['candidate']['meanFPS']:.2f} | {g['fpsChangePercent']:+.2f}% | {g['parent']['meanP95Ms']:.2f} | {g['candidate']['meanP95Ms']:.2f} |")
lines+=['','각 칸은 실행 두 번의 산술평균이다. p95는 실행별 백분위의 평균이며 pooled percentile이 아니다. FPS는 높을수록 좋고 지연 ms는 낮을수록 좋다. 작은 표본이므로 안정적 개선·동등성·회귀는 단정하지 않는다.','','| 순서 | 백엔드 | 앱 | FPS | p95 ms | p99 ms | >100ms 프레임 |','|---:|---|---|---:|---:|---:|---:|']
for row in rows:lines.append(f"| {row['ordinal']} | {row['backend']} | {'이전 P1/P2/P3+B' if row['role']=='parent' else '신규 +C-T/C-M3'} | {row['fps']:.2f} | {row['p95Ms']:.2f} | {row['p99Ms']:.2f} | {int(row['over100Ms'])} |")
lines+=['','## 실행한 앱','','- 이전: '+prep['parent'],'- 신규: '+prep['candidate'],'- 두 앱 메타데이터는 1.0.3이며 정식 배포판 번호가 아니다. 엔진/launcher/콘텐츠와 다른 runtime은 같고 MoltenVK만 다르다. 두 라이브러리의 build-prefix UUID는 f52facf7으로 같지만, 각 앱의 서로 다른 SHA256 및 실제 로딩 경로를 확인했다.','','## 조건과 검증','','- 각 backend 순서는 신규→이전→이전→신규. 앱·backend 조합당 측정 두 번, 총8회. 세 번째 앱 시작의 로비 제어 연결 실패는 게임 실행 전이었고, 그 실패를 보존한 뒤 한 번 이어 실행했다. 완료한 성능 표본은 재측정하지 않았다.','- AC 전원·저전력 ON. 관측 thermal state: '+str(summary['thermalStates'])+'.','- 기존 성공 batch7과 동일 controller/scene/설정. Ultra 실제 옵션·AA Off·FoW 대각선0·Spring 카메라·VSync Off. 실제 drawable1432×902, 숨김 BAR.app Lobby 경로, 무음.','- Beyond All Reason test-31671-ad2e1b7 / Seths Ravine Remake1.3.1. 공식 armbull armbull 80 8 1400, seed31443/7654321, 1x요청, frame240→1140, 900 simulation frames. 매 실행 새 private shader cache.','- 시작 카메라·품질·장면 필드와 로딩 위젯 '+str(len(widgets))+'개 목록이 모두 일치. 불필요한 VBO 점검 위젯 없음, sandbox/위젯·shader 오류 검사 통과.','- Metal4 actual native queue/완료 증거, Metal3 native backend 미선택, 실제 runtime library mapping 검증. 통계·비용 instrumentation은 OFF.','- 요청 속도는 모두1x이나 실제 시작 속도는 '+str([x['gameSpeed']['start']['actual'] for x in rows])+'이다. 종료 속도는 '+str([x['gameSpeed']['finish']['actual'] for x in rows])+'이며 전체 구간의 실제속도가 정확히1x였다는 주장은 하지 않는다. 동일900시뮬레이션프레임과 요청조건으로 비교하며 시작속도 상승 구간도 포함한다.','- 공식 gadget stop acknowledgment는 '+str([x['officialStopFrame'] for x in rows])+' 프레임이다. FPS sampler는 모두1140에서 먼저 끝났으며 공식 별도 timer 합계를 FPS로 사용하지 않았다.','- 두 앱1194-entry 인벤토리, 최종 descriptor 소스 핀, 실제launcher HEAD/index/dirty status와 원래 사용자 설정 핀 보존. 시험소유프로세스 종료, screensaver/awake 상태 복구.','','## 실험 흔적 정리와 복원','','- 앞선 측정에서 지운 캐시는 재삭제하지 않았다. 이번 역순 측정 전에는 추가 삭제하지 않았으며, 정상종료 뒤 생긴 시험 전용 캐시만 정리한다.','- 이번8회도 각 정상종료 뒤 shader/browser cache를 정리했다. 합계 논리'+str(summary['cleanupDuring']['logicalBytesRemoved'])+'바이트. 기존 host가 지우는 private content clone과 별도다. APFS 실물 회수량으로 환산하지 않는다.','- 로그·결과·소스·앱·Markdown과 복원 근거는 유지한다. MVK GitHub 배포관리 담당에 checkpoint 업로드를 요청했으며, 압축·전송은 측정과 겹치지 않도록 측정 종료 후 재개한다.','','## 해석 범위','','한 지도·한 초기 전투·900프레임·숨김창/무음 결과이며 foreground/fullscreen·audio·Chobby/MP·다른 Mac으로 확대하지 않는다. 각2표본의 분산과 global driver/filesystem cache·외부 OS작업은 통제되지 않았다. shader compilation과 전투 증가 비용도 포함한다. C-T/C-M3의 기여를 분리하거나 정점 캐시의 상승효과를 검증한 결과가 아니다.','','상세 수치와 hash: '+str(O/'summary.json'),'개별 receipt 및 cache 정리 선택·완료: '+str(O),'']
lines+=['','## 잠금 상태와 시작 실패 기록','','화면 잠금 상태에서 진행하라는 사용자 지시를 반영했다. 잠금 해제·인증 설정 변경은 하지 않았고 실제 렌더링 진행 검증은 유지했다. 관측 잠금 상태: '+str(summary['consoleLockStates'])+'. 앞선 배치는 잠금 해제를 요구했으므로 배치 간 차이를 실행 순서만의 영향으로 단정하지 않는다.','','세 번째 앱 시작에서 renderer execution context가 교체되어 제어 연결이 끊겼다. 그래픽 게임 자식 프로세스와 성능 표본이 생성되기 전이었다. 원본 실패 receipt/log를 보존하고, 로비의 읽기 전용 준비 확인만 안정화한 뒤 남은 여섯 측정을 진행했다. 게임 시작 요청은 각 앱 실행당 한 번이며 완료한 측정값을 버리거나 재추첨하지 않았다.','']
lines+=['','## 앞선 순서와 비교','','| 백엔드 | 순서 | 이전 평균 FPS | 신규 평균 FPS | 변화 |','|---|---|---:|---:|---:|']
for backend in ('metal3','metal4'):
 for label,gg in (('이전→신규→신규→이전',previous['groups'][backend]),('신규→이전→이전→신규',groups[backend])):
  lines.append(f"| {backend} | {label} | {gg['parent']['meanFPS']:.2f} | {gg['candidate']['meanFPS']:.2f} | {gg['fpsChangePercent']:+.2f}% |")
lines+=['','각 배치별 두 표본의 평균이다. 실행 순서와 시간 경과의 영향을 분리하는 확증 실험은 아니며, 두 배치를 임의로 합쳐 단일 개선율로 표시하지 않았다.','']
report=R/'reports/v104-descriptor-performance-reverse-20261020.md'
with report.open('x') as f:f.write('\n'.join(lines))
save(O/'completion.json',{'status':'completed','report':str(report),'reportSHA256':sha(report),'summary':str(O/'summary.json'),'summarySHA256':sha(O/'summary.json'),'screenRestored':True,'awakeReleased':True,'appsSourcesLauncherAndUserPinsExact':True,'noInstallOrPublication':True})
print(json.dumps({'groups':groups,'report':str(report)},indent=2))
