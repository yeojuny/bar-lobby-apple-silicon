# 입력 유휴 재비교 guard 독립 검수

**수정본 코드 검수 통과: 남은 차단 문제0건입니다.** 아직 adapter 준비·실제 batch 실행은 검수한 것이 아닙니다. 현재 FPS batch에는 영향을 주지 않았습니다. 검토 대상은 idle-input-guard.py, prepare-idle-performance.py, analyze-idle-performance.py 및 원래 runner입니다.

초기 지적 두 건은 해결됐습니다. wait_ready는 monitor failures/stop을 받는 cancellation predicate를 loop와 반환 전에 확인하고, runner도 반환 직후 다시 확인합니다. 기존처럼 긴 idle 대기 동안 monitor가 실패한 뒤 뒤늦게 앱을 실행하는 경로를 막습니다.

입력창은 start 직전·finish 직후 관찰을 모두 요구하고 endpoint 거리 및 내부 gap을6초 이하로 확인합니다. pass는 모든 추정 last-input이 start−0.5초 이전일 때만 허용합니다. 확실한 측정 내부 입력과 near-boundary/첫 post-end 전 입력을 구분하여 후자는 불명확으로 중단합니다. post-end 입력이 미관찰 마지막 순간을 가릴 수 있어 이 보수적 처리는 타당합니다. 원결과를 보존하며 자동 재실행하지 않습니다.

HID idle60초, 개별CPU25% 미만 및 전체합50% 미만의 관찰된 quiet30초 gate는 arm 전에만 적용합니다. benchmark 중에는 입력·CPU 기록만 하므로 높은 게임 CPU 자체로 결과를 선별하지 않습니다. top10 truncation도25% 이상 프로세스 존재를 가리지 않고, aggregate는 전체 파싱 행을 합산합니다.8회 정방향과 전체 순서 반전8회, 각 앱/backend n2 및 과거 FPS 평균 합산 없음이 코드와 맞습니다.

runner/helper SHA 고정, analyzer의 frozen helper를 이용한 입력창 재검산과 실제 runtime/backend·계측OFF·900frames·전원/해상도/조건·소스/포인터 보존 검사는 적절합니다. 이전 비교 파일은 조건 비교에만 사용하고 FPS 계산에 포함하지 않습니다.

남은 작은 권고는 rows를 atUnix로 정렬하여 두 thread의 append 순서 차이에 대비하는 것, CPU cache를 immutable snapshot/작은 lock으로 일관되게 읽는 것, quiet duration에 monotonic을 쓰는 것입니다. 최종 analyzer에서 ordinal1..8과 p95/p99 원문 일치까지 확인하면 더 견고합니다. 현재 benchmark 구간은 보통 단일 monitor이고 preparer도 올바른 순서를 생성하므로 이를 새 차단 문제로 확대하지 않습니다. 최종 데이터 검수 때 전체8회 원문을 다시 확인해야 합니다.

CPU15초·HID 명목2초는 sampled observation이며 연속 부하 통제가 아닙니다. 명령 지연·캐시 재사용, GPU/I/O/clocks의 미통제 한계를 유지해야 합니다. 입력창 통과도 정의된 관찰·보수적 경계 기준이지 장치 이벤트 전체의 직접 기록은 아닙니다.

독립 검수는 읽기/논리 검토뿐입니다. 테스트·OS sampling·GPU·앱/게임·큰 inventory·설정/서비스 변경·정리·재실행은0회이며 이 두 검수 기록만 저장했습니다. 초기 지적과 이전 입력 핀은 JSON의 resolvedInitialReview에 보존했습니다.
