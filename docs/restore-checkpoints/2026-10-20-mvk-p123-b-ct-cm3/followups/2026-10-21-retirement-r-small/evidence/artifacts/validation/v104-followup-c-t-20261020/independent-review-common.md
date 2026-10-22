# C-T + C-M3 최종 변경분 독립 검수 — 2026-10-20

**결론: 새 고정핀의 변경분에서 수정이 필요한 결함을 찾지 못했다.** 범위는 제품 4파일과 기존 fixture 3파일이다. 이전 `independent-review.md`는 C-T 단독 단계의 기록으로 보존하며, 최종 공통 구현에는 이 보고서를 적용한다. 요청 설정은 Astra + High다. 검토자는 선행 설계 작성자이며 실제 구현자와 분리돼 있다.

## 고정 대상과 실제 적용 근거

`review-common-pins.json`의 7파일이 현재 파일과 일치한다. 보존된 7개 원본도 `before.json`과 일치하며, 전후 파일로 재구성한 diff는 `applied-common.patch`와 완전히 같다. 패치 SHA256은 `4a26fa01142c906215cc013973ac80e66d9d254472e74a398d3e86ebe021ddeb`다.

Zink의 실제 producer는 push-template entry에 context 내부 UBO offset을 넣고, 호출에는 context 시작 주소를 전달한다. 제공된 실제 Mesa 설정의 컴파일 상수와 원문을 확인했다: context 112768B, vertex UBO offset 58256B, fragment 61328B, compute 62096B, descriptor info 24B, write metadata 64B다. vertex singleton 예의 기존 capture 58280B에 비해 compact payload는 88B다. 여러 entry의 크기나 실제 호출 빈도는 따로 계산해야 하며, 모든 draw가 이 경로를 지난다는 뜻은 아니다. fbfetch 혼합·다른 descriptor mode에는 이 결론을 확대하지 않는다.

## 제품 동작 검토

- 생성 메타데이터는 소유 복사된 entry의 불변 형식·끝 위치만 요약한다. 생성 시 layout 포인터, 입력 데이터 포인터, 새 잠금·자원 소유 계층을 추가하지 않는다. 현재 layout의 타입·목적 배열 범위 확인은 계속 수행한다.
- Metal4는 `requireSmallerCapture=false`로 기존 compact 선택을 유지한다. 작은 입력을 이유로 Metal4를 generic으로 돌리거나 직접 기록 정책을 바꾸지 않는다.
- Metal3는 compact 저장 크기를 안전하게 계산한 뒤 **기존 generic 크기보다 엄격히 작을 때만** 선택한다. 같거나 더 크면 generic이다. 저장 크기 overflow도 M3는 generic으로 돌린다. 현재 64비트 대상의 uint32 entry count에서는 그 곱셈 한계에 도달하지 않지만 분기 자체는 안전하다.
- 정적 offset/base overflow 검사는 형식·현재 layout·M3 크기 적격성 판정 뒤에 있다. 부적격 입력의 기존 generic 선택을 이 새 검사로 바꾸지 않는다. 실제 compact 선택 입력에서 전체 최대 끝 위치 검사는 기존 개별 끝 위치 검사와 동치다. 일반 template 크기 계산 자체의 기존 stride 문제를 고쳤다고 주장하지 않는다.
- compact의 `VkWriteDescriptorSet`와 template replay는 동일한 CPU push 저장소 준비 및 `writeDescriptorSetCPUBufferDispatch`로 이어진다. UBO singleton은 source stride가 결과를 바꾸지 않으며, binding/배열 시작 위치/중복 목적지 순서는 보존된다. count>1·spill·혼합 형식은 그대로 generic이다.
- descriptor 값과 목적 메타데이터는 기록 시점에 command가 소유한다. 실제 uniform 버퍼 내용은 기존 encode/GPU 사용 시점에 읽는다. layout retain/release, pool 재사용, 저장 용량, 실패 node 회수, 제출·완료·GPU 자원 수명은 바꾸지 않았다. compact 성공 후 template 포인터를 없애도 replay에 필요한 메타데이터는 command에 남는다.
- foundation OFF에서도 같은 common 함수와 필드가 존재하며 Metal4 전용 API 호출을 새로 요구하지 않는다. template 크기는 ON/OFF 모두 **104→120B**다. OFF의 command 클래스에도 기존에 제외됐던 compact 상태 필드 두 개가 추가된다. command 전체 객체 크기·할당기 점유량은 이 기록에서 별도 측정하지 않았다.

작은 M3 입력도 적격성 확인 비용은 추가로 거친다. 크기 기준은 payload 저장 증가를 피하는 기준이지 CPU 시간·FPS의 순이익 증명이 아니다. 큰 Zink 입력의 복사 감소 근거는 충분하지만 성능 수치는 실제 비교로 판단해야 한다.

## 검사 변경과 기존 결과 확인

CPU fixture의 실제 template 클래스·constructor·accessor 및 capture 메서드 추출과 입력 해시를 확인했다. 대체 layout/state/vector/pool 및 generic size stub 한계는 유지된다. wrapper가 count 조회마다 production template을 재생성하므로 이 검사를 실제 생성 빈도나 성능 측정으로 해석하면 안 된다.

기존 결과는 ASan/UBSan **ON 629 assertions, OFF 134 assertions** 통과다. 작은 크기·같은 크기·1바이트 큰 크기의 strict 선택, sparse 입력의 command 소유 복사, generic↔compact 전환을 포함한다. 실제 두 translation unit의 foundation ON/OFF 문법 검사 4개 및 증분 링크 완료도 확인했다. 검수자는 중복 실행하지 않았다.

GPU fixture의 `Context.initialize` 기본 기대값은 여전히 native Metal4다. 기존 무인자 suite는 Metal4 환경을 강제하고 실제 큐·argument-buffer 선택·native 완료 counter 검사를 유지한다. 추가 M3 옵션만 명시적으로 기대값을 false로 바꾸며, 실제 legacy 큐임을 확인하고 Vulkan fence 및 queue idle 완료 뒤 결과를 읽는다. M3에서 읽는 진단 counter는 legacy 큐에도 안전하게 접근하는 기존 함수이며, native counter 증가를 M3의 성공 조건으로 사용하지 않는다.

구현자가 제공한 GPU 결과와 현재 라이브러리 해시를 대조했다.

| 대상 | 확인된 기존 결과 |
|---|---|
| 원래 native Metal4 suite | 6/6, 실제 native 큐·완료 counter 유지 |
| 공통 template Metal3 | 6회 cycle 및 graphics 결과, 실제 `native_queue=false` |
| 공통 template Metal4 | 같은 사례, 실제 `native_queue=true` |

공통 사례는 sparse/unaligned·stride 0/8/정상/4096, 중복 목적지·부분 배열 위치, mixed fallback, 취소 node 재사용, 기록 뒤 descriptor 입력 변경, mapped 최신 값, query/helper, graphics 소비를 확인한다. Metal API Validation 활성 로그가 있고 관련 실행 exitCode는 모두 0이다. 현재 raw 라이브러리 SHA256은 native receipt의 `443cae49eeca6814a7374cf510178416660e07238715e1ceb451f648e92eb60a`와 일치한다.

GPU 실행은 foundation ON 라이브러리의 M3/M4 선택 결과다. foundation OFF 라이브러리로 GPU 실행한 증거는 아니다. GPU 시험의 argument-buffer 환경은 0이며 모든 결합 모드·BAR 게임·전체 스택·FPS를 검증한 것으로 확대하지 않는다.

## 남은 범위

새 수명·동시성 재설계가 필요하다는 근거는 발견하지 못했다. 정점 binding cache는 이번 패치에 없고, 이 검수에서 재도입을 승인하거나 상승효과를 입증하지 않았다. C-T/C-M3로 상대 병목 비중이 바뀔 수 있지만 encode 단계의 정점 cache 유효성 계약 자체를 개선한 것은 아니다.

검수자는 제품·fixture·공유 기록을 수정하거나 앱·게임·새 검사를 실행하지 않았다. 이 보고서와 [고정핀·증거 기록](independent-review-common.json)만 작성했다. 패키징과 FPS 효과는 별도 결과로 보고해야 한다.
