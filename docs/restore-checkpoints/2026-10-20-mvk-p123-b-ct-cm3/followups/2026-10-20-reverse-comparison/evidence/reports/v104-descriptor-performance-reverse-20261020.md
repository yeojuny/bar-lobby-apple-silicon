# C-T·C-M3 누적 후보 역순 성능 비교 — 2026-10-20

이전 P1/P2/P3+B 후보와 C-T/C-M3 추가 후보를 전원 연결·저전력 ON의 동일 조건에서 새로 비교했다. 정점 바인딩 캐시는 어느 쪽에도 없다. 이전의 다른 후보 측정값은 평균에 섞지 않았다.

| 백엔드 | 이전 후보 평균 FPS | C-T·C-M3 후보 평균 FPS | 변화 | 이전 p95 ms | 신규 p95 ms |
|---|---:|---:|---:|---:|---:|
| metal3 | 49.38 | 50.43 | +2.12% | 31.18 | 30.50 |
| metal4 | 39.54 | 43.90 | +11.01% | 37.97 | 31.86 |

각 칸은 실행 두 번의 산술평균이다. p95는 실행별 백분위의 평균이며 pooled percentile이 아니다. FPS는 높을수록 좋고 지연 ms는 낮을수록 좋다. 작은 표본이므로 안정적 개선·동등성·회귀는 단정하지 않는다.

| 순서 | 백엔드 | 앱 | FPS | p95 ms | p99 ms | >100ms 프레임 |
|---:|---|---|---:|---:|---:|---:|
| 1 | metal3 | 신규 +C-T/C-M3 | 50.86 | 29.59 | 40.71 | 0 |
| 2 | metal3 | 이전 P1/P2/P3+B | 48.72 | 32.84 | 53.95 | 1 |
| 3 | metal3 | 이전 P1/P2/P3+B | 50.03 | 29.53 | 41.31 | 0 |
| 4 | metal3 | 신규 +C-T/C-M3 | 49.99 | 31.40 | 41.53 | 0 |
| 5 | metal4 | 신규 +C-T/C-M3 | 44.10 | 32.06 | 45.08 | 0 |
| 6 | metal4 | 이전 P1/P2/P3+B | 43.33 | 32.98 | 46.15 | 1 |
| 7 | metal4 | 이전 P1/P2/P3+B | 35.76 | 42.95 | 61.03 | 0 |
| 8 | metal4 | 신규 +C-T/C-M3 | 43.70 | 31.66 | 47.20 | 0 |

## 실행한 앱

- 이전: $WORKSPACE/artifacts/runtime/v104-performance-ab-candidate-20261020/BAR.app
- 신규: $WORKSPACE/artifacts/runtime/v104-descriptor-candidate-20261020/BAR.app
- 두 앱 메타데이터는 1.0.3이며 정식 배포판 번호가 아니다. 엔진/launcher/콘텐츠와 다른 runtime은 같고 MoltenVK만 다르다. 두 라이브러리의 build-prefix UUID는 f52facf7으로 같지만, 각 앱의 서로 다른 SHA256 및 실제 로딩 경로를 확인했다.

## 조건과 검증

- 각 backend 순서는 신규→이전→이전→신규. 앱·backend 조합당 측정 두 번, 총8회. 세 번째 앱 시작의 로비 제어 연결 실패는 게임 실행 전이었고, 그 실패를 보존한 뒤 한 번 이어 실행했다. 완료한 성능 표본은 재측정하지 않았다.
- AC 전원·저전력 ON. 관측 thermal state: [0].
- 기존 성공 batch7과 동일 controller/scene/설정. Ultra 실제 옵션·AA Off·FoW 대각선0·Spring 카메라·VSync Off. 실제 drawable1432×902, 숨김 BAR.app Lobby 경로, 무음.
- Beyond All Reason test-31671-ad2e1b7 / Seths Ravine Remake1.3.1. 공식 armbull armbull 80 8 1400, seed31443/7654321, 1x요청, frame240→1140, 900 simulation frames. 매 실행 새 private shader cache.
- 시작 카메라·품질·장면 필드와 로딩 위젯 235개 목록이 모두 일치. 불필요한 VBO 점검 위젯 없음, sandbox/위젯·shader 오류 검사 통과.
- Metal4 actual native queue/완료 증거, Metal3 native backend 미선택, 실제 runtime library mapping 검증. 통계·비용 instrumentation은 OFF.
- 요청 속도는 모두1x이나 실제 시작 속도는 [1, 1, 1, 1, 1, 1, 1, 1]이다. 종료 속도는 [1, 1, 1, 1, 1, 1, 1, 1]이며 전체 구간의 실제속도가 정확히1x였다는 주장은 하지 않는다. 동일900시뮬레이션프레임과 요청조건으로 비교하며 시작속도 상승 구간도 포함한다.
- 공식 gadget stop acknowledgment는 [1140, 1140, 1140, 1140, 1140, 1140, 1140, 1140] 프레임이다. FPS sampler는 모두1140에서 먼저 끝났으며 공식 별도 timer 합계를 FPS로 사용하지 않았다.
- 두 앱1194-entry 인벤토리, 최종 descriptor 소스 핀, 실제launcher HEAD/index/dirty status와 원래 사용자 설정 핀 보존. 시험소유프로세스 종료, screensaver/awake 상태 복구.

## 실험 흔적 정리와 복원

- 앞선 측정에서 지운 캐시는 재삭제하지 않았다. 이번 역순 측정 전에는 추가 삭제하지 않았으며, 정상종료 뒤 생긴 시험 전용 캐시만 정리한다.
- 이번8회도 각 정상종료 뒤 shader/browser cache를 정리했다. 합계 논리76973317바이트. 기존 host가 지우는 private content clone과 별도다. APFS 실물 회수량으로 환산하지 않는다.
- 로그·결과·소스·앱·Markdown과 복원 근거는 유지한다. MVK GitHub 배포관리 담당에 checkpoint 업로드를 요청했으며, 압축·전송은 측정과 겹치지 않도록 측정 종료 후 재개한다.

## 해석 범위

한 지도·한 초기 전투·900프레임·숨김창/무음 결과이며 foreground/fullscreen·audio·Chobby/MP·다른 Mac으로 확대하지 않는다. 각2표본의 분산과 global driver/filesystem cache·외부 OS작업은 통제되지 않았다. shader compilation과 전투 증가 비용도 포함한다. C-T/C-M3의 기여를 분리하거나 정점 캐시의 상승효과를 검증한 결과가 아니다.

상세 수치와 hash: $WORKSPACE/artifacts/validation/v104-descriptor-performance-reverse-20261020/summary.json
개별 receipt 및 cache 정리 선택·완료: $WORKSPACE/artifacts/validation/v104-descriptor-performance-reverse-20261020


## 잠금 상태와 시작 실패 기록

화면 잠금 상태에서 진행하라는 사용자 지시를 반영했다. 잠금 해제·인증 설정 변경은 하지 않았고 실제 렌더링 진행 검증은 유지했다. 관측 잠금 상태: ['True']. 앞선 배치는 잠금 해제를 요구했으므로 배치 간 차이를 실행 순서만의 영향으로 단정하지 않는다.

세 번째 앱 시작에서 renderer execution context가 교체되어 제어 연결이 끊겼다. 그래픽 게임 자식 프로세스와 성능 표본이 생성되기 전이었다. 원본 실패 receipt/log를 보존하고, 로비의 읽기 전용 준비 확인만 안정화한 뒤 남은 여섯 측정을 진행했다. 게임 시작 요청은 각 앱 실행당 한 번이며 완료한 측정값을 버리거나 재추첨하지 않았다.


## 앞선 순서와 비교

| 백엔드 | 순서 | 이전 평균 FPS | 신규 평균 FPS | 변화 |
|---|---|---:|---:|---:|
| metal3 | 이전→신규→신규→이전 | 44.95 | 48.36 | +7.59% |
| metal3 | 신규→이전→이전→신규 | 49.38 | 50.43 | +2.12% |
| metal4 | 이전→신규→신규→이전 | 38.68 | 34.89 | -9.80% |
| metal4 | 신규→이전→이전→신규 | 39.54 | 43.90 | +11.01% |

각 배치별 두 표본의 평균이다. 실행 순서와 시간 경과의 영향을 분리하는 확증 실험은 아니며, 두 배치를 임의로 합쳐 단일 개선율로 표시하지 않았다.
