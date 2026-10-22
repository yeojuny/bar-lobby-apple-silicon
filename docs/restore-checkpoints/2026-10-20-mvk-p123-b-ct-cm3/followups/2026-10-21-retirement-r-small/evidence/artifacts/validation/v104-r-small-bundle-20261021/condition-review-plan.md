# 실행별 조건 검토 계획

각 정·역방향 batch의8회를 **실행 전 gate, 실제 측정창, 종료 후 검증**으로 나누어 원문을 대조합니다. 기존8회는 background-overlap-note에 따라 채택 근거와 새 평균에서 제외합니다. 색인이 원인이었다고 확정한 기록은 아닙니다.

| 구간 | 실제 관찰·검증 | 해석 경계 |
| --- | --- | --- |
| host 시작 전 | HID유휴60초, 관찰된 개별CPU<25%·전체합<50%의 quiet30초, LowPower·saver/console 및 중단 상태 | CPU15초 표본 기반이며 실제 benchmark 직전 재gate는 아님 |
| 앱 준비·측정 직전 | 동결 앱/입력·loaded runtime, scene frame240·Ultra/AAoff/VSync0·Spring·safe1512×950 hidden fullscreen, AC/절전·thermal·awake | 초기화 중 색인이 재개할 수 있음. thermal은 기록이며 매 표본0을 강제하는 gate는 아님 |
| 측정 중 | HID 명목2초, top10 PID/name/CPU와 전체합15초, host 전원·thermal·awake15초, draw 진행 | CPU 기준으로 중간 결과를 자동 배제하지 않음. 게임 자신의 CPU도 전체합에 포함됨 |
| 측정 뒤 | 시작 직전/종료 직후 입력표본·최대6초 gap, inside/ambiguous 구분,900sim frames·실제 M3/M4·계측OFF, 종료/소유 프로세스·보존·전원 | 입력/경계 불명확·기능 실패는 원문 보존 후 나머지 중단, 자동 재실행 없음 |
| batch 종료 | 전체8순서·receipt/산식·핀·소스/프로필/포인터·캐시 정리·화면 복구, 각 배치 평균 | 기존 analyzer는 색인 부하를 자동 요약하지 않으므로 별도 원문 주석을 결합 |

실제16회 데이터 검수 때 각 receipt의 benchmarkStart/FinishUnixMS를 CPU 기록에 맞춥니다. **CPUSampledAtUnix로 캐시 중복을 제거**하여 fresh 표본 수와 시간, 전체합 최대/범위, 색인으로 보이는 기록된 PID/이름/CPU, 주요 다른 작업을 실행별로 정리합니다. 시작 전 오래 기다린 시간이나 앱 전체 수명의 부하를900frame 측정창의 부하로 대체하지 않습니다.

mds/mds_stores/mdworker 등 실제 남은 이름을 원문 그대로 제시합니다. top10에 없다고 색인이 없었다고 하거나, 이름만으로 구체 작업을 확정하지 않습니다. 기존 owned-child/PID 기록으로 게임·lobby를 구분할 수 있는 범위에서만 외부 부하를 분리합니다. 전체CPU가 높은 이유가 게임 FPS 상승 자체일 수 있으므로 전체합을 배경CPU로 부르지 않습니다.

각 실행의 FPS·p95/p99와 fresh CPU 표본·색인/타작업·AC/절전/thermal·입력 coverage를 나란히 봅니다. 높은 부하와 낮은 FPS가 겹쳐도 인과 증명은 아닙니다. 수치를 본 뒤 유리한 회차만 삭제하거나 조정 FPS를 만들지 않습니다. 정방향·역방향을 먼저 별도 비교하고, 사전에 정한 유효8회 전체를 포함합니다.

한계는15초 사이의 짧은 CPU burst, 상위10/2% 필터 밖의 작업, GPU 점유율·CPU/GPU clock·전력 governor, 디스크/네트워크 I/O·메모리 압력·스케줄링·캐시 효과입니다. CPU가 낮아도 색인 I/O가 영향을 줄 수 있습니다. HID도 간접 표본이며 raw event 전체 추적이 아닙니다. thermal은 coarse한 기록이고 실제 present mode/physical refresh도 미관찰입니다. 기존 backgroundLoadFullyControlled=false 한계를 유지합니다.

최신 helper의 status 중복키 수정과 rows.sort를 확인했습니다. root와 양 prepared helper는 SHA `9d54ec76cae44cc2b5f29851e53dcbc494ba9def38710abd4aca8786b8df0edb`, 양 runner는 `b35553e86542a302d476c0e3eebcd8242e46c89f6ac1867274fb8e754a1b5425`로 preparation pin과 일치합니다. 최초 출력 오류의 게임0회 기록도 보존돼 있습니다. 이전 guard 검수서는 수정하지 않았습니다.

이 작업은 기존 파일의 가벼운 읽기뿐입니다. 새 OS sampling·GPU·앱/게임·빌드/테스트·큰 inventory·제품/fixture/helper/프로필/포인터/서비스/화면 설정 변경은0회이며, 이 계획 두 파일만 저장했습니다. 실제16회 완료 뒤 별도 독립 데이터 검수가 필요합니다.
