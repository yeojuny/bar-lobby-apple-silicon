# C-T·C-M3 누적 후보 성능 비교 — 2026-10-20

이전 P1/P2/P3+B 후보와 C-T/C-M3 추가 후보를 전원 연결·저전력 ON의 동일 조건에서 새로 비교했다. 정점 바인딩 캐시는 어느 쪽에도 없다. 이전의 다른 후보 측정값은 평균에 섞지 않았다.

| 백엔드 | 이전 후보 평균 FPS | C-T·C-M3 후보 평균 FPS | 변화 | 이전 p95 ms | 신규 p95 ms |
|---|---:|---:|---:|---:|---:|
| metal3 | 44.95 | 48.36 | +7.59% | 35.67 | 32.73 |
| metal4 | 38.68 | 34.89 | -9.80% | 40.52 | 54.35 |

각 칸은 실행 두 번의 산술평균이다. p95는 실행별 백분위의 평균이며 pooled percentile이 아니다. FPS는 높을수록 좋고 지연 ms는 낮을수록 좋다. 작은 표본이므로 안정적 개선·동등성·회귀는 단정하지 않는다.

| 순서 | 백엔드 | 앱 | FPS | p95 ms | p99 ms | >100ms 프레임 |
|---:|---|---|---:|---:|---:|---:|
| 1 | metal3 | 이전 P1/P2/P3+B | 44.10 | 36.98 | 65.46 | 11 |
| 2 | metal3 | 신규 +C-T/C-M3 | 51.63 | 30.03 | 45.29 | 7 |
| 3 | metal3 | 신규 +C-T/C-M3 | 45.09 | 35.43 | 48.75 | 2 |
| 4 | metal3 | 이전 P1/P2/P3+B | 45.81 | 34.36 | 50.31 | 2 |
| 5 | metal4 | 이전 P1/P2/P3+B | 39.15 | 38.69 | 52.38 | 1 |
| 6 | metal4 | 신규 +C-T/C-M3 | 37.35 | 49.38 | 70.32 | 3 |
| 7 | metal4 | 신규 +C-T/C-M3 | 32.44 | 59.33 | 93.56 | 7 |
| 8 | metal4 | 이전 P1/P2/P3+B | 38.21 | 42.35 | 57.13 | 0 |

## 실행한 앱

- 이전: $WORKSPACE/artifacts/runtime/v104-performance-ab-candidate-20261020/BAR.app
- 신규: $WORKSPACE/artifacts/runtime/v104-descriptor-candidate-20261020/BAR.app
- 두 앱 메타데이터는 1.0.3이며 정식 배포판 번호가 아니다. 엔진/launcher/콘텐츠와 다른 runtime은 같고 MoltenVK만 다르다. 두 라이브러리의 build-prefix UUID는 f52facf7으로 같지만, 각 앱의 서로 다른 SHA256 및 실제 로딩 경로를 확인했다.

## 조건과 검증

- 각 backend 순서는 이전→신규→신규→이전. 앱·backend 조합당 두 번, 총8회, 실패 후 재시도 없음.
- AC 전원·저전력 ON. 관측 thermal state: [0].
- 기존 성공 batch7과 동일 controller/scene/설정. Ultra 실제 옵션·AA Off·FoW 대각선0·Spring 카메라·VSync Off. 실제 drawable1432×902, 숨김 BAR.app Lobby 경로, 무음.
- Beyond All Reason test-31671-ad2e1b7 / Seths Ravine Remake1.3.1. 공식 armbull armbull 80 8 1400, seed31443/7654321, 1x요청, frame240→1140, 900 simulation frames. 매 실행 새 private shader cache.
- 시작 카메라·품질·장면 필드와 로딩 위젯 235개 목록이 모두 일치. 불필요한 VBO 점검 위젯 없음, sandbox/위젯·shader 오류 검사 통과.
- Metal4 actual native queue/완료 증거, Metal3 native backend 미선택, 실제 runtime library mapping 검증. 통계·비용 instrumentation은 OFF.
- 요청 속도는 모두1x이나 실제 시작 속도는 [0.819999992847, 0.899999976158, 1, 1, 1, 1, 1, 1]이다. 종료 속도는 [0.999994516373, 0.999996960163, 1, 1, 1, 1, 1, 1]이며 전체 구간의 실제속도가 정확히1x였다는 주장은 하지 않는다. 동일900시뮬레이션프레임과 요청조건으로 비교하며 시작속도 상승 구간도 포함한다.
- 공식 gadget stop acknowledgment는 [1140, 1140, 1140, 1140, 1140, 1140, 1140, 1140] 프레임이다. FPS sampler는 모두1140에서 먼저 끝났으며 공식 별도 timer 합계를 FPS로 사용하지 않았다.
- 두 앱1194-entry 인벤토리, 최종 descriptor 소스 핀, 실제launcher HEAD/index/dirty status와 원래 사용자 설정 핀 보존. 시험소유프로세스 종료, screensaver/awake 상태 복구.

## 실험 흔적 정리와 복원

- 측정 전 지난 시험 캐시108개 root/4689leaf, 논리141251537바이트 제거. 결과·로그 등751개 기록 해시 보존. 성능 상승이 컸던 라인·앱·소스·build는 선택하지 않았다.
- 이번8회도 각 정상종료 뒤 shader/browser cache를 정리했다. 합계 논리76945145바이트. 기존 host가 지우는 private content clone과 별도다. APFS 실물 회수량으로 환산하지 않는다.
- 로그·결과·소스·앱·Markdown과 복원 근거는 유지한다. MVK GitHub 배포관리 담당에 checkpoint 업로드를 요청했으며, 압축·전송은 측정과 겹치지 않도록 측정 종료 후 재개한다.

## 해석 범위

한 지도·한 초기 전투·900프레임·숨김창/무음 결과이며 foreground/fullscreen·audio·Chobby/MP·다른 Mac으로 확대하지 않는다. 각2표본의 분산과 global driver/filesystem cache·외부 OS작업은 통제되지 않았다. shader compilation과 전투 증가 비용도 포함한다. C-T/C-M3의 기여를 분리하거나 정점 캐시의 상승효과를 검증한 결과가 아니다.

상세 수치와 hash: $WORKSPACE/artifacts/validation/v104-descriptor-performance-comparison-20261020/summary.json
개별 receipt 및 cache 정리 선택·완료: $WORKSPACE/artifacts/validation/v104-descriptor-performance-comparison-20261020

## 이번 판정

Metal3는 44.953480→48.363235 FPS(+7.5851%)이지만 신규 51.633270/45.093201의 차이가 커 안정적인 개선은 미확정이다. Metal4는 38.681036→34.891876 FPS(−9.7959%)이며 신규 두 번 모두 기준 두 번보다 낮고 p95/p99도 악화됐다. 적은 표본만으로 안정적인 소스 인과 회귀를 확정하지 않지만, 이번 배치의 Metal4 하락은 명시적인 우려로 다룬다. 두 backend에 공통된 성능 개선으로 채택할 근거는 아니다. 빠른 값과 느린 값 모두 제외하지 않았고, 두 후보를 복원 가능하게 유지한다. C-T/C-M3별 기여와 정점 캐시 상호작용은 측정하지 않았다.
