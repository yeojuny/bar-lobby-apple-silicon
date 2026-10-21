# 화면 크기 조회 경량화 — 2026-10-20

C-REG 누적 후보 위에 두 엔진의 viewport/scissor 전용 live 창·drawable 크기 조회를 적용했다. 기존 전체 화면 배치·노치·Retina 정책과 자원·동기화 계약은 유지한다.

기존 전체 QueryDisplayGeometry는 변경하지 않았다. 새 QueryWindowDrawableSize는 logical 크기와 현재 CAMetalLayer drawableSize만 읽고, layer가 없거나 비어 있으면 기존 NativeCocoaDrawableScale을 적용한다. 캐시를 추가하지 않아 창 크기·화면·배율 변경은 매번 현재 값으로 읽는다. 별도 FBO는 기존 우회 경로, 좌표 반올림도 동일하다.

표시 버전은 두 앱 모두 **1.0.3**, 로컬 **v1.0.4 누적 후보**다. 기존 P1/P2/P3+B+C-T+C-M3+C-REG가 모두 들어 있다.

- 기존 앱: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/runtime/v104-c-reg-candidate-20261020/BAR.app`
- 수정 앱: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/runtime/v104-drawable-size-candidate-20261020/BAR.app`

기존 display CPU fixture53개를 현재 소스에 바인딩하고 실제 새 helper/viewport/scissor/scale 함수를 포함한 ASan/UBSan 검사 **각102개(두 엔진)**가 통과했다. SDL/Screen/GL은 mock이며 UpdateViewPortGeometry는 기존 single-screen prefix만 검사한다. 두 기존 native build에서 bridge와 GlobalRendering 각2개 object만 재컴파일·링크했고, 공식 sync identity와 BAR-1.0.3 표시는 동일하다. 독립 Astra+High 검수는 actionable findings0. 앱1194항목 중 엔진2개+서명2개만 달라졌으며 dependency closure211개와 deep strict signature를 확인했다.

## 같은 조건 성능 비교

실제 실행은 BAR.app→Lobby→bundled Lobby 엔진 경로다. Chobby 엔진은 이번 CPU·빌드·CLI·패키지 검증까지이며 새 Chobby 게임 검증으로 세지 않는다. AC 전원·Low Power ON, Ultra·AA Off·Spring·VSync Off·sound off. 게임 Fullscreen=1, 숨김 창 container1512×982, safe viewport1512×950, 기본1×drawable. 동일 Seths Ravine/BAR test31671·seed·frame240→1140·900simulationframes. 각 실행 독립 profile/cold cache. controller·guard·fullscreen adapter는 직전 비교와 byte-identical.

순서: **Metal4 parent,candidate,candidate,parent then Metal3 candidate,parent,parent,candidate**. CPU sampling은 이8회와 분리했다. 사용자가 측정 중 다른 작업을 하고 있다고 확인했다. 따라서 아래 값은 동시 작업 부하가 섞인 참고 결과이며 코드만의 인과적 FPS 개선율로 확정하지 않는다. 첫 기존 Metal4 값이 이전 비교보다 낮은 기록도 제외하지 않고 모두 보존했다.

| 백엔드 | 앱 | 1회 FPS | 2회 FPS | 평균 FPS | 실행별 p95 평균 ms |
|---|---|---:|---:|---:|---:|
| metal3 | 기존 C-REG 누적 | 44.25 | 42.41 | 43.33 | 44.12 |
| metal3 | 기존+화면 크기 조회 경량화 | 48.42 | 52.13 | 50.27 | 36.43 |
| metal4 | 기존 C-REG 누적 | 30.88 | 35.35 | 33.11 | 62.85 |
| metal4 | 기존+화면 크기 조회 경량화 | 27.89 | 37.31 | 32.60 | 63.92 |

Metal3 평균 FPS **+16.02%**, p95 **-17.42%**. Metal4 평균 FPS **-1.56%**, p95 **+1.70%**. 각 앱/백엔드2회이며 일반화·통계적 유의성·무위험 순이익은 주장하지 않는다. p95는 실행별 percentile의 평균이다.

SDL은 숨긴 창의 fullscreen 의도를 유지하면서 실제 macOS display/Space 전환은 표시될 때까지 유예한다. 실제 모니터 이동/Space전환/다른 Mac의 입력·표시 회귀를 이 숨김 비교로 검증했다고 주장하지 않는다. CPU fixture는 화면 크기·배율·safe-area 계산 동등성을, 실제 게임은 현재 고정 환경의 렌더링 진행과 설정·종료를 확인했다.

## 별도 비용 관찰

새 후보 Metal4만 기존 OS sample10초/1ms 요청으로 관찰했다. 수집과900-frame benchmark는 완료했지만, 이후 native 종료 callback·PID소멸 확인이15초 제한을 넘겼다. sampler 자체는 quit 요청 이전에 정상 종료했다. 원인은 제품 변경·sampler·동시 작업 어느 쪽으로도 확정하지 않았다. 이 실행의 FPS는 위 표에 포함하지 않고, 원본 실패 상태와 private cache를 보존하며 자동 재시도하지 않았다.

수집한 stack에서 default-framebuffer viewport/scissor 관측 2, 그 아래 전체 geometry 조회 0, WindowServer display-state 조회 0, 새크기helper 관측 2. 관측 수는 호출 횟수·시간·CPU비중·FPS기여율이 아니며 inlining과 짧은 표본의 한계가 있다. 남아 있는 전체 geometry 조회는 화면 배치 등 다른 경로일 수 있다. 이 표본은 종료까지 통과한 runtime acceptance로 세지 않는다.

## 보존

비교8회는 모두 정상 종료했다. 별도관찰1회는 위 종료확인 실패 뒤 기존 소유권 제한 cleanup이 시험 프로세스를 정리했으며 현재 소유 프로세스는 없다. 성공한8회의 private 재생성 캐시 48개 root/2662개 leaf/76955677 logical bytes만 정리했고 실패관찰profile/cache는 그대로 보존했다. raw 로그·결과·Markdown·앱·source·이전 raw engine도 보존했다. 물리 회수량은 측정하지 않았다. 실제 launcher HEAD/index/status, 사용자profile3개, 보호핀74개 및 빌드입력1271/1265개가 유지됐다. 공식 Release/Homebrew 갱신과 설치는 하지 않았다.

완료 기록: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/validation/v104-drawable-size-20261020/completion.json`. 성능 원본: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/validation/v104-drawable-size-performance-20261020/comparison-summary.json`. 관찰 원본: `/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/validation/v104-drawable-size-observation-20261020/sample-analysis.json`. GitHub 복원 보존은 별도 후속 기록으로 연결한다.
