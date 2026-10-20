# C-T 변경분 독립 검수 — 2026-10-20

**결론: 검토한 변경분에서 수정이 필요한 결함을 찾지 못했다.** 제품 3파일과 기존 CPU fixture 1파일의 패치에 대한 판단이다. C-M3 및 정점 binding cache는 미적용이며 이 결과의 승인 대상이 아니다. 요청 설정은 Astra + High다. 검토자는 선행 C 설계 작성자이며, 이번 제품 구현자와 분리돼 있다.

## 검토 대상을 고정한 근거

- `review-pins.json`의 현재 4파일 해시를 확인했다. `before/`의 같은 4파일은 `before.json`과 일치한다.
- 이 전후 파일로 다시 구성한 unified diff가 `applied.patch` 전체와 일치한다. 패치 SHA256은 `5c24d9835a08ed8163747cbef767cb571ee944c943301c43bbc186fb5ceca284`다.
- CPU receipt의 입력 10파일도 현재 소스와 일치한다. 전체 스택이나 앱의 재검수로 확대하지 않는다.

## 동작과 오류 처리

생성자가 소유 복사하는 entry에서 singleton UBO 여부, offset 덧셈 overflow, 최대 읽기 끝 위치만 요약한다. 생성 이후 이 정보에 쓰는 경로가 없고, template 외부 포인터·layout·GPU 자원·새 잠금을 추가하지 않는다.

빈 template은 기존 count 검사에서 제외된다. mixed/array template의 부적격 판정은 이전처럼 generic 경로로 이어진다. 새 코드는 전체 형식 판정을 layout 순회보다 먼저 수행하므로 검사 방문 순서는 달라지지만, 유효한 Vulkan 입력에서 기존 binding 조회는 읽기뿐이며 payload 복사·오류 보고 전에 같은 generic 선택으로 끝난다. 잘못된 Vulkan 입력의 기존 잘못된 접근까지 동일하게 보존한다고 주장하지 않는다.

적격 singleton template에서는 이번 호출의 layout binding 타입·배열 범위 검사를 그대로 수행하고, 그 뒤에만 크기·저장된 offset overflow·현재 입력 주소 overflow를 검사한다. 호환되지 않는 현재 layout을 offset 오류보다 먼저 generic으로 보내는 순서는 유지된다. 생성 때의 layout을 현재 layout 대신 사용하는 변경도 없다.

Apple Silicon의 64비트 size_t/uintptr_t에서, 모든 offset 끝 위치가 표현 가능하면 `base <= UINTPTR_MAX - max(end)`는 기존 각 entry에 대한 동일 부등식의 논리곱과 같다. 정적 overflow가 있으면 먼저 실패한다. stride와 entry 순서는 이 최대값의 의미를 바꾸지 않는다. maxReadEnd 범위 전체를 복사하는 것이 아니며 실제 singleton memcpy·목적지 순서·정렬은 그대로다.

count에 따른 저장 크기, 할당 실패, command-local capacity, layout retain/release, generic↔compact 재사용, Metal4 Deferred 정책, 제출·완료·GPU 보유 계약은 변경되지 않았다. 일반 template `_size`의 기존 stride 계산은 이번 수정이나 검수의 해결 대상이 아니다.

## Metal3 비용과 빌드 경계

foundation ON이면 런타임 Metal3에서도 template 생성 때 새 메타데이터를 계산한다. 제공된 실제 헤더의 LLVM 출력과 이전 헤더 VFS 매핑을 대조했으며 `sizeof(MVKDescriptorUpdateTemplate)`는 **104→120바이트**다. foundation OFF는 **104→104바이트**로 유지된다. 이는 객체 크기이며 할당기의 실제 점유 증가량이나 FPS 비용을 측정한 값은 아니다.

Metal3의 기록·복사 경로는 기존 그대로다. 따라서 이 변경을 Metal3 성능 개선이나 양쪽 모두 비용이 없는 수정으로 설명하면 안 된다. 생성 시 추가 계산·객체 저장 비용과 Metal4 반복 검사 감소의 교환이며, 현재 변경에서 정확성 결함으로 볼 근거는 없다. 단순히 M3 상대 성능을 낮추려는 변경으로도 해석하지 않는다.

## 검증 기록의 적절성과 한계

- 기존 CPU 결과는 ASan/UBSan foundation ON **607 assertions**, OFF **115 assertions** 통과다. 검수자는 재실행하지 않고 receipt·실행 로그·현재 입력 해시를 대조했다.
- 새 fixture는 실제 template 클래스·생성자·accessor를 이름만 바꿔 추출한다. 생성된 C++ 본문에 실제 클래스와 메서드가 들어 있고 receipt 해시가 일치함을 확인했다. 요약값을 테스트에서 하드코딩한 형태가 아니다.
- fixture wrapper는 `getNumberOfEntries()`마다 ProductionTemplate을 재생성한다. 따라서 이 결과를 실제 객체 생성 빈도·성능·모든 수명 통합 검증으로 해석하면 안 된다. vector/base/layout/state/pool 대체 구현과 generic size stub 한계는 receipt에 명시돼 있다. 실제 metadata의 생성·불변성은 제품 코드와 함께 검토했다.
- 기존 bounds/live/admission 추출의 brace 범위가 현재 생산 코드의 해당 블록을 담는지 확인했다. 이 제한된 추출 방식은 일반 C++ parser가 아니지만 현재 추출 본문에서 범위가 잘못 잡힌 문제는 찾지 못했다.
- 구현자의 증분 빌드 로그는 최종 라이브러리 링크 완료를 포함한다. 실제 두 변경 translation unit의 foundation ON/OFF 문법 검사 4개는 모두 exitCode 0이다. 이 검수에서 빌드·검사를 중복 실행하지 않았다.

이번 독립 검수는 새 GPU·게임·FPS 실행을 하지 않았고, GPU 출력이나 성능 향상을 인증하지 않는다. 관련 native 결과와 통합 후보 확인은 구현 채팅이 별도로 마무리할 범위다. 새로운 수명·동시성 재설계가 필요하다는 근거는 발견하지 못했다.

제품·fixture·공유 기록은 수정하지 않았다. 이 보고서와 [해시·범위 기록](independent-review.json)만 작성했다.
