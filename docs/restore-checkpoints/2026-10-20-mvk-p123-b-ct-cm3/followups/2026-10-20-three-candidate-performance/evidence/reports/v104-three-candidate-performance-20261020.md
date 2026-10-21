# 세 후보 성능 비교 — 2026-10-20

A는 C-REG까지, B는 A+화면 크기 조회 최적화, C는 B+typed Buffer 등록 호출부 수정이다. 표시 버전은 모두 1.0.3이며 로컬 v1.0.4 후보들이다.

AC 전원·절전모드 ON, Ultra·AA Off·Spring·VSync Off·sound off. 실제 BAR.app→Lobby→번들 엔진, 동일 장면·seed·900 simulation frames(240→1140), 실행마다 private profile/cold cache. logical container 1512×982, safe viewport 1512×950, 기본 1× drawable, Fullscreen=1 및 SDL fullscreen intent를 유지하면서 창만 숨겼다. SDL native display/Space 전환은 숨긴 동안 유예된다.

| backend | 앱 | 버전 | 1회 FPS | 2회 FPS | 평균 FPS | p95 평균 ms |
|---|---|---|---:|---:|---:|---:|
| metal3 | A | 1.0.3 | 46.74 | 45.43 | **46.09** | 37.46 |
| metal3 | B | 1.0.3 | 50.89 | 52.14 | **51.51** | 28.09 |
| metal3 | C | 1.0.3 | 50.25 | 52.85 | **51.55** | 27.65 |
| metal4 | A | 1.0.3 | 40.07 | 38.91 | **39.49** | 44.60 |
| metal4 | B | 1.0.3 | 45.69 | 45.25 | **45.47** | 30.23 |
| metal4 | C | 1.0.3 | 46.93 | 46.45 | **46.69** | 29.14 |

| 변경 | Metal3 평균 FPS 변화 | Metal4 평균 FPS 변화 |
|---|---:|---:|
| A→B 화면 크기 조회 | +11.78% | +15.14% |
| B→C 버퍼 등록 | +0.08% | +2.68% |

B의 두 실행은 두 backend에서 모두 A의 두 실행보다 높았다. Metal4의 C 두 실행도 B 두 실행보다 높았고, Metal3의 C/B는 실행별 방향이 엇갈려 추가 이익을 구분하기 어렵다. 이 장면의 n=2 관측이며 다른 부하·장면으로 일반화하지 않는다.

| 순서 | backend | 앱 | simulation frames | 렌더 간격 표본 수 | 평균 FPS |
|---:|---|---|---:|---:|---:|
| 1 | metal3 | A | 900 | 1400 | 46.74 |
| 2 | metal3 | B | 900 | 1525 | 50.89 |
| 3 | metal3 | C | 900 | 1515 | 50.25 |
| 4 | metal3 | C | 900 | 1584 | 52.85 |
| 5 | metal3 | B | 900 | 1562 | 52.14 |
| 6 | metal3 | A | 900 | 1361 | 45.43 |
| 7 | metal4 | C | 900 | 1406 | 46.93 |
| 8 | metal4 | B | 900 | 1369 | 45.69 |
| 9 | metal4 | A | 900 | 1201 | 40.07 |
| 10 | metal4 | A | 900 | 1166 | 38.91 |
| 11 | metal4 | B | 900 | 1356 | 45.25 |
| 12 | metal4 | C | 900 | 1392 | 46.45 |

900은 simulation frame 수(240→1140)이고, 렌더 간격 표본 수는 해당 구간에 수집한 DrawScreen 간격 수다. GPU draw call 수나 고유 자원 수가 아니다.

각 후보 경로:
- A: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/runtime/v104-c-reg-candidate-20261020/BAR.app`
- B: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/runtime/v104-drawable-size-candidate-20261020/BAR.app`
- C: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app`

실행 순서: M3 A→B→C→C→B→A, M4 C→B→A→A→B→C. 12회 모두 정상 종료했고 실제 backend·라이브러리 해시·뷰포트·품질·보호 입력을 검증했다.
전원 관측 110개, thermalState [0]. 시험 종료 후 화면 보호 설정과 awake assertion을 복원했다. 성공 실행의 재생성 가능한 private cache 72 roots/3996 leaves/115443398 logical bytes를 정리했다. 물리 회수량으로 해석하지 않는다. 각 실행의 임시 content clone 정리는 execution receipt에 별도 기록돼 있다.

표본은 후보·backend별 2회다. 평균 FPS 및 percentile은 실행별 값의 산술 평균이며 전체 프레임을 합친 percentile이 아니다. 역순으로 완화했지만 OS/사용자 동시 부하까지 통제한 실험은 아니다. 과거 동시 작업이 섞인 수치와 합산하지 않는다. 이전 sampled 종료 실패와 Metal3 timestamp fixture 불일치는 이번 비교로 원인이 해소됐다고 보지 않는다.

원본 결과·조건·로드된 앱/라이브러리 및 정상 종료 근거는 `artifacts/validation/v104-three-candidate-performance-20261020/`에 있다. 제품 코드/앱 수정·설치는 없었다.
