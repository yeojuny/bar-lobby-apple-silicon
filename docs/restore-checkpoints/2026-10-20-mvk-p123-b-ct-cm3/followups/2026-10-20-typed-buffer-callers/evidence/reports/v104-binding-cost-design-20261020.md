# v1.0.4 후보: Metal4 그리기 준비·자원 바인딩 잔여 비용 설계

2026-10-20. 요청된 Astra + Max 분석·설계 단계. 제품 구현이나 새 측정은 수행하지 않았다.

**판정: 남은 Buffer 등록 호출부의 좁은 수정은 구현할 근거가 있다. descriptor 캐시 공유 확대는 아직 구현할 근거가 부족하다.** 후자는 실제 재사용 결과를 구분하는 최소 진단을 먼저 해야 한다. allocator·패스·동기화 변경은 이번 설계의 구현 대상이 아니다.

현재 구현에는 기록 내부의 완전 재사용, binding revision에 따른 부분 재사용, 기록 간 group/per-binding snapshot이 이미 있다. 이들을 다시 만들거나 현재 기록의 retention·residency를 이전 기록에서 가져오는 안은 제안하지 않는다. Metal3 성능을 낮춰 Metal4의 상대 성능을 개선하는 변경도 없다.

## 기준과 증거의 한계

- 기준 앱: `artifacts/runtime/v104-drawable-size-candidate-20261020/BAR.app`. 표시 버전은 1.0.3이며, P1/P2/P3+B+C-T+C-M3+C-REG+live window/drawable size helper를 포함한 **로컬 v1.0.4 누적 후보**다.
- 제출된 source/build/test 핀 22개와 일치한다. raw MVK SHA256은 `e60a7d6694d2c4a7fd02239d981342e0b3f86cab1e6e1d94d897fe9ce4ba101c`, 앱 MVK는 `79dfe6e5fe91e35c14751316d0acc5f96837516619945388c5c073e94295ebdc`와 실제 파일이 일치한다. 소스 checkpoint는 입력 receipt의 `7ca6c11f457f59681c0dde6a927aabea24ac9c50`이며, 이번에 원격을 다시 확인하지 않았다.
- [입력 및 조건](../artifacts/validation/v104-binding-cost-analysis-20261020/handoff.json), [소스 핀](../artifacts/validation/v104-binding-cost-analysis-20261020/source-pins.json), [기존 샘플 분석](../artifacts/validation/v104-binding-cost-analysis-20261020/existing-sample-analysis.json)을 사용했다. 현재 MVK는 `MVK_ENABLE_CUSTOM_DIAGNOSTICS=0`이다. 환경 변수만 바꿔 아래 세부 카운터를 얻을 수 없다.
- drawable-size FPS 실행 중 사용자의 다른 작업이 있었다. 보고된 M3 +16.02%/M4 -1.56%는 변경의 인과적 효과로 사용하지 않는다.
- 별도 M4 관찰에서 sampler의 10초 수집과 900-frame benchmark는 완료됐지만, 뒤의 **15초 native 종료 확인은 실패**했다. 원인은 미확정이다. 이 실행은 runtime acceptance/FPS 비교에 넣지 않는다. 수집된 호출 트리는 보조 증거로만 사용한다. 종료 실패를 sampler나 제품 회귀 탓으로 단정하거나 timeout을 늘려 통과시키지 않는다.

`spring:zfq0` thread 분모는 1,720개 관측이다. `prepareMetal4Draw` 110, `bindMetal4Resources` 75, 등록 함수 20, residency lease 7, group cache 2, texture cache 8, native render encoder 생성 45가 관측됐다. 명시적 allocator lifecycle과 이 thread의 mutex wait는 0이었다. condition wait 1,347은 제거 가능한 GPU 대기라는 증거가 아니다.

이 숫자는 **stack 관측 수**이며 호출 횟수·시간·CPU 사용률·FPS 기여율이 아니다. 범주가 중첩되고 inline/deduplicated symbol도 있다. 현재 샘플만으로 캐시 miss 비율이나 어느 준비 단계가 지배적인지 확정할 수 없다.

## 현재 경로: 무엇을 이미 생략하며 무엇이 남는가

기준 파일은 [MVKCommandEncoderState.mm](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm:120), [prepared resource 구현](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4PreparedResource.h:109), [buffer preparation cache](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.h:520)다.

| 순서·경로 | 현재 실행과 재사용 범위 | 남아 있는 작업·필수 조건 |
|---|---|---|
| descriptor root | 현재 기록에서 등록했고 buffer/offset/table/slot revision이 같으면 등록과 setter 생략 | root 목록과 실제 slot 확인은 남음. helper·vertex/direct write 및 stride-mode 변경이 root를 덮을 수 있으므로 slot 검사를 제거할 근거 없음 |
| recording group exact hit | script/stage/set incarnation·revision/5종 epoch가 정확히 같으면 전체 indirect binding 목록 탐색 생략 | stamp 구성, 최대 16개 set 검사, map lookup은 남음. 이 hit에는 shared_ptr 복사나 개별 proof 순회가 없음 |
| recording group proof full hit | stamp가 달라도 같은 identity·covered binding revision·live proof·drawable 조건을 만족하고 다시 읽은 stamp가 안정적이면 full hit | covered revision/proof 검사. 이미 이 기록이 보유한 자원의 중복 retention은 하지 않음 |
| recording group partial hit | covered 항목을 유지하고 residual ordinal만 준비 | covered 중 하나의 revision이 바뀌면 해당 proof 전체가 miss다. 임의로 바뀐 항목만 골라 구제하는 구조는 아님 |
| pipeline group snapshot full replay | recording cache miss 뒤 CPU snapshot을 사용해 payload 해석을 생략 | 각 자원을 현재 live guard 아래 검증하고 **현재 기록의 새 retention·residency** 확보. 이는 snapshot 재사용 실패가 아니라 필요한 기록 경계 작업 |
| pipeline group snapshot partial replay | snapshot에 담긴 covered 자원을 새 기록에서 확보한 뒤 residual만 준비 | group replay 성공과 residual 작업이 함께 발생. 이후 같은 stamp에서는 residual이 있던 proof라도 recording exact hit가 전체 탐색을 생략할 수 있음 |
| per-binding buffer cache hit | incarnation/binding revision과 buffer generation 또는 안정적인 proof로 payload 순회 생략 | proof refresh는 generation 변경 때만. 최대 256 binding, proof는 최대 16 자원. 큰 binding의 generation-only 재사용도 이미 존재 |
| per-binding texture/sampler cache hit | incarnation/binding revision과 살아 있는 weak proof로 payload 순회 생략 | 최대 256 binding/16 자원. negative memo는 proof 재시도만 억제하며 자원 처리를 건너뛰지 않음 |
| descriptor binding snapshot replay | 위 cache miss 뒤 CPU snapshot으로 payload 해석 생략 | 현재 live guard/owner proof 확인과 fresh retention은 유지. snapshot mutex는 replay 동안 잡힘. 이번 샘플로 lock 경합을 입증하지 못했음 |
| slow payload | 실제 descriptor 수·stride·범위를 확인하고 객체를 읽어 등록. 가능한 경우 다음 snapshot/proof를 작성 | immutable sampler, InlineData, zero count, 지원되지 않는 shape, proof 실패, 크기 제한, 새 revision 등을 혼동하면 안 됨. 일부 성공 경로는 객체 순회가 전혀 없음 |
| direct operations | indirect group hit 뒤에도 `bindScript.ops`를 순회. dynamic offset 및 실제 payload는 현재 값 사용 | table setter는 이미 동일 객체/주소의 중복 Metal write를 줄임. 이 루프가 BAR에서 얼마나 실행되는지는 현재 통계로 모름 |
| implicit·vertex·상태 | implicit은 layout/길이/value/slot revision으로 byte upload 생략. vertex도 table 내부 address/stride 중복 write 생략 | vertex 목록·유효 범위 확인과 상태 준비는 남음. 이전 무이득 vertex memo를 새 근거 없이 되살리지 않음 |

`prepareMetal4Draw`는 vertex와 fragment stage의 binder를 호출하고, compute dispatch도 같은 binder를 사용한다. stage 방문 수는 draw 수와 같지 않다. primitive conversion, indirect draw 및 multiview 때문에 단순히 2배로 환산해서도 안 된다.

새 기록 token을 보면 `_metal4OwnedBuffers/Objects/Textures`, per-binding cache와 stage preparation은 초기화된다. submission의 group cache도 기록 수명에 속한다. 반면 descriptor snapshot과 pipeline group snapshot은 **CPU metadata만** 유지한다. native 객체·descriptor-pool owner를 강하게 잡는 공유 캐시가 아니다.

### 변경에서 반드시 유지할 계약

1. set 포인터/Metal 주소만으로 동일성을 판정하지 않는다. incarnation, binding revision, overflow 시 비활성화와 layout identity를 유지한다.
2. snapshot 재생은 live guard 아래 현재 owner proof를 확인하고, guard를 놓기 전에 현재 기록 소유권을 확보한다. 이전 기록의 lease를 현재 기록의 증거로 사용하지 않는다.
3. ordinary texture proof와 drawable registration generation을 구분한다. drawable·view·heap 중첩·외부 import·proof revocation 예외를 버리지 않는다.
4. root/implicit 캐시는 table identity와 실제 slot revision을 지킨다. 동일 주소라도 address-only setter와 stride setter를 같은 상태로 취급하지 않는다.
5. 등록 실패는 즉시 기존 오류 경로로 반환한다. 실패한 준비를 성공 캐시로 게시하지 않는다. 부분 replay 뒤 fallback할 수 있다는 현재 동작도 보존한다.
6. recording 소유권, pool 취소/retirement, 동시 접근 lock 순서 및 query/attachment/제출 의존성은 이번 작은 변경 대상이 아니다.

## 기존 카운터를 그대로 읽을 때의 함정

[통계 정의](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.h:103)와 실제 증가 위치를 대조했다.

| 카운터 | 실제 분모·의미 | 알 수 없는 것 |
|---|---|---|
| `indirectGroupChecks/Hits/Preparations` | recording group lookup 직후, pipeline snapshot replay **전**에 집계. setMask가 있는 stage 검사 단위 | Preparations는 slow payload 수가 아님. 나중의 snapshot full hit까지 여기에 포함됨. exact/proof full/partial도 분리되지 않음 |
| `textureBindingVisits` | 실제 `prepareBinding`까지 내려온 texture/sampler binding 방문 | group hit로 생략한 binding은 포함하지 않음. 전체 draw의 texture cache hit율 분모로 쓸 수 없음 |
| `textureCacheEligible/Hits/Misses` | eligible lookup 단위이며 Hits+Misses=Eligible | group replay/per-binding snapshot으로 해결한 작업량 및 buffer cache 결과 |
| `textureProofAttempts/NegativeMemoSkips` | miss 중 새 proof 시도 또는 negative memo | 실패가 모두 자원 문제라는 뜻이 아님. cache가 없거나 revision이 바뀐 경우도 Attempt |
| `textureProofReady/Rejected` | slow payload 끝의 proof 결과. Ready는 remember 호출 전이며 bounded cache 삽입 성공을 보장하지 않음 | per-binding snapshot hit는 이 두 증가 위치 전에 반환한다. Attempts=Ready+Rejected라는 등식은 성립하지 않음 |
| `textureHitResourceSlots` | cache hit가 생략한 논리적 자원 slot 수 | 고유 자원 수·실제 GPU 접근·절약 시간 |
| `directTextureBindings` | 직접 texture setter를 시도한 element 수 | 전체 direct opcode/Buffer/Sampler/bytes 경로의 비용, setter가 실제 Metal write를 했는지 |

통계는 `beginMetal4Recording`에서 초기화하고 `finishMetal4Recording`에서 submission으로 합친다. backend-cost는 **통계가 전달된 host 시각**의 1초 bin에 넣으며 최대 300초다. `encoding_record_count`는 전달 횟수이지 draw·제출·GPU 완료 수가 아니다. 취소됐거나 GPU에 도달하지 않은 기록도 CPU encoding 통계에 포함될 수 있다. CPU/GPU 시간과 이 encoding bin을 frame별 인과 관계처럼 연결하지 않는다.

## 바로 구현할 수 있는 좁은 변경: 남은 Buffer 등록 호출부

**기존 C-REG 공통 구현을 다시 고치는 작업이 아니다.** 현재도 generic 경로로 들어가는, 타입이 이미 증명된 호출부만 기존 `addBufferResource`에 연결한다.

| 호출부 | 타입 근거·증거 | 제안 범위 |
|---|---|---|
| [indexed draw](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdDraw.mm:1150) | Vulkan index binding의 `id<MTLBuffer>`. 샘플 line4468–4480 아래 protocol 판별 관측 5 | `addResource(binding.mtlBuffer, &error)`를 기존 typed Buffer 진입점으로 연결 |
| [buffer copy](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdTransfer.mm:1334) | source/destination 모두 `getMTLBuffer()`의 `id<MTLBuffer>`. 샘플 line4648–4653의 protocol 관측 1 | 두 buffer가 generic transfer helper에서 타입을 잃지 않게 연결. image/mixed transfer 호출은 generic 유지 |
| [query 결과 복사](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKQueryPool.mm:231) | result buffer와 destination이 명시적인 `id<MTLBuffer>`. 샘플 line4723–4731의 protocol 관측 1 | 두 등록만 typed 연결. getResultBuffer·availability·copy 선택·timestamp 완료 경계 변경 없음 |
| [transfer compute helper](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdTransfer.mm:97) | initializer_list의 원소가 `pair<id<MTLBuffer>, NSUInteger>`. 현재 코드상 재분류는 확실하지만 이 호출부의 sample 비용은 분리 확인하지 못함 | 같은 transfer 단위의 typed 연결에 포함 가능. actual BAR 비용 확인 항목과 구분해 기록 |

**이익은 첫 등록/아직 resident가 아닌 버퍼에 한정된다.** [addResourceWithKind](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.mm:2180)는 이미 resident인 동일 버퍼이면 protocol 검사 **전에 반환**한다. 따라서 매 indexed draw마다 분류 비용이 발생한다고 주장할 수 없다. 샘플의 7개 관측을 7회 호출이나 FPS 절약분으로 환산하지 않는다. 기대 효과는 작은 CPU 재분류 제거이며, Metal3/4 성능 차이를 이것 하나로 설명하지 않는다.

### API·순서·경계

- `MVKMetal4Submission.h/.mm`의 기존 `addBufferResource`와 `NonTexture` 의미를 그대로 사용한다. 새 cache, global map, ownership flag, protocol 결과 저장은 필요 없다.
- `MVKCmdDraw.mm`와 `MVKQueryPool.mm`는 해당 등록 호출만 교체한다. nil/type/range/overflow 검사, error 초기화, short-circuit 순서, 실패 메시지를 그대로 둔다.
- transfer helper는 한 공통 본문을 유지한다. 구현 예시는 `mvkMetal4TransferResource<Kind = Unknown>`의 compile-time 선택으로, `NonTexture` specialization만 기존 Buffer API를 호출하고 기본값은 기존 generic API를 호출하게 하는 것이다. buffer copy 두 호출만 명시적으로 NonTexture를 선택한다. runtime protocol 분기나 새로운 상태 기계를 추가하지 않는다. type 선택 때문에 오류 처리 본문을 복제하지 않는다.
- transfer compute helper의 명시적 Buffer pair는 곧바로 `addBufferResource`를 호출한다. 다른 image/view/resolve용 generic helper 입력을 포괄 cast하지 않는다.
- 공통 등록은 기존 Recording phase → nil/device 확인 → 현재 identity/lease/retention 순서를 유지한다. typed 연결은 kind만 전달하며 mutex, heap registry, fresh-recording ownership, error/cancellation/retirement를 생략하지 않는다.
- foundation OFF와 runtime Metal3는 기존 분기를 유지한다. 엔진/Mesa/Lua/shader/sync identity 변경이 없다.

새로 확인한 `MVKCmdDraw.mm`, `MVKCmdTransfer.mm`, `MVKQueryPool.mm`의 현재 hash는 최종 receipt에 추가했다. 기존 22개 핀 밖의 파일이므로 구현자가 이 세 파일을 다시 고정한 뒤 적용해야 한다. 다른 generic 호출은 이번 범위에 자동 포함하지 않는다. 특히 argument-table의 `setBytes` generic 등록은 recording 종료 뒤의 **오류 경로**이고, 정상 동일-byte hit는 이미 등록을 생략한다. 이를 draw 비용으로 집계하지 않는다.

### 필요한 검증과 중단 조건

기존 C-REG의 전체 lifetime 검증을 반복할 필요는 없다. 변경한 호출 연결에 맞는 확인만 한다.

- affected translation unit 증분 빌드와 foundation OFF 확인. 기존 CPU 등록 fixture의 nil/wrong-device/ended/duplicate/새 기록 사례를 재사용하여 generic과 typed의 결과 및 retain/resident 수가 같음을 확인한다. 이미 검증된 공통 API 자체를 새 fake 구현으로 재작성하지 않는다.
- 기존 Vulkan/native fixture에서 indexed draw 출력, buffer copy의 aligned/byte-helper 출력, query 결과 복사의 값·availability를 확인한다. `metal4-primitive-conversion.mm`, `metal4-transfer-edge.mm`, `metal4-prepared-recording-vulkan.mm`의 관련 사례를 우선 사용한다. 부족한 실제 호출 경로만 기존 fixture에 추가한다. 함수명 치환 문자열 검사만으로 GPU 동등성을 주장하지 않는다.
- **Metal3 음성 대조:** M3에서도 실행 가능한 동일 Vulkan 입력의 출력과 기존 분기를 확인한다. fixture의 M4 전용 prepared-recording·native completion-count 조건을 M3에 강요하지 않는다. M3가 느려졌다는 결과를 Metal4 이익으로 계산하거나 FPS 변동을 임의로 보정하지 않는다.
- 성능 비교는 진단 OFF인 현재 후보/변경 후보를 동일 장면·전원·캐시 정책으로 비교한다. 과거 부하가 섞인 표본은 합치지 않는다. 기존 30초 절차와 순서 반전 반복을 재사용하고 sample 실행은 FPS 비교에 섞지 않는다. 새로운 BAR 실행은 이번 설계 작업에서 예약하지 않았다.
- 속도 차이가 반복 변동 안이면 “중복 분류 제거, FPS 순이익 미확정”이다. 수명·query/transfer 순서 변경이 필요해지거나 새 cache/lock이 필요하면 이 단위에서 중단한다. 위 native 종료 확인 실패가 다시 발생하면 원본을 보존하고 성능 합격으로 처리하지 않는다.

## descriptor 구조 변경 전의 최소 진단안

위 작은 호출부 수정에는 이 계측을 선행할 필요가 없다. **더 큰 descriptor 준비 변경을 선택할 때만** 다음 계측 단위를 별도로 진행한다. 현재로서는 특정 cache 확대·vector 재배치가 BAR의 반복 비용을 줄인다고 확정할 수 없다.

### 정적으로 확인되었지만 빈도가 미확정인 후보

| 후보 | 실제 남아 있는 계산·복사 | 지금 바로 구조 변경하지 않는 이유 |
|---|---|---|
| immutable binding 해석 | slow/partial 경로가 layout index, resource shape, CPU stride·offset을 다시 해석 | group full hit에서는 이 작업 자체를 하지 않음. variable descriptor count, 현재 revision·범위·dynamic offset은 immutable로 옮길 수 없음 |
| proof/snapshot 임시 vector | slow preparation의 proof push, snapshot resource 수집, group append/copy. snapshot replay도 현재 recording proof vector를 채울 수 있음 | 비어 있는 vector 선언만으로 heap 할당을 단정할 수 없음. group capture는 반복 descriptor 조합과 크기 제한 아래에서만 실행. 정상 full hit는 이 수집을 하지 않음 |
| group partial 구제 확대 | covered binding 하나가 바뀌면 group proof miss 후 개별 cache/snapshot에 의존 | 어느 revision/ownership 조건이 실제 miss를 일으키는지 모름. 새 부분 계획은 순서·proof·bounded metadata 검토가 필요 |
| 직접 binding script 순회 | direct ops의 current payload·offset 계산과 등록/setter 진입 | script는 이미 pipeline 생성 시 준비됨. 실제 Metal write는 setter가 중복 제거. direct ops가 비어 있는 BAR 경로에 새 cache를 추가할 수 없음 |
| per-binding snapshot lock | replay 중 snapshot mutex와 live/registration 작업 | lock wait는 이번 worker 샘플에서 확인되지 않음. lock 범위를 옮기려면 immutable snapshot ownership 계약이 바뀌므로 별도 수명 검토 필요 |

### 26개 이하의 고정 카운터만 추가

현재 53개 encoding counter/기존 serializer/merge/collector를 재사용한다. 새 tracing framework, per-resource map, pointer 기록, hot-path 로그·clock·atomic·추가 lock·sampling thread를 만들지 않는다. 새 필드는 diagnostics ON에만 포함하여 shipping OFF의 객체 크기와 실행 경로를 유지한다. 기존 `sizeof(MVKBackendCostStats) < 256 * 1024` 상한도 올리지 않는다.

| 집계 묶음 | 새 필드 수 | 단위와 분류 |
|---|---:|---|
| binder entry/error | 2 | shader-stage binder 진입/실패. outer 함수 단위이며 draw 수가 아님 |
| root visit/reuse | 2 | 유효 root를 처리한 횟수와 exact-slot skip. 둘의 차이는 등록 시도이며 성공 Metal write 수가 아님 |
| recording lookup outcome | 6 | exact full / proof full / proof partial / no reusable entry / descriptor identity-or-revision / ownership-or-stability. 기존 group check와 같은 setMask 조건에서 한 번만 분류 |
| pipeline group snapshot outcome | 5 | tried / full hit / partial hit / miss / failed. 4개 결과의 합=tried |
| binding visit/result/residual | 6 | visits / buffer hit / per-binding snapshot hit / slow success / failed / residual-origin visits. texture hit는 기존 counter 재사용 |
| direct operations | 2 | opcode 방문과 그 아래 실제 sink 호출 시도. Buffer/Texture/Sampler/bytes/UseResource 포함. native write 수 아님 |
| implicit visit/reuse | 2 | 대상 implicit 방문과 layout/slot memo hit. byte upload 성공 수와 구분 |
| slow payload resource slots | 1 | 실제 slow loop에서 descriptor 객체 값을 읽은 slot 수. immutable sampler·zero-count/inline 성공을 큰 payload walk로 오해하지 않도록 보조 |

recording lookup의 miss 분류는 **기존에 최초로 실패한 검사만** 기록한다. no-entry/invalid stamp/없는 proof는 no-reusable-entry, set identity나 covered revision 실패는 descriptor, drawable/proof expiry/최종 stamp 변화는 ownership-or-stability에 넣는다. 후자를 무조건 “과잉 무효화”로 부르지 않는다. full hit가 나오면 miss 원인 조사를 위해 proof를 다시 읽지 않는다.

`MVKMetal4PreparedGroupCache::lookup`의 기존 return 지점에서 optional diagnostic outcome을 제공하고 binder에서 지역 counter를 증가시키면 된다. compound 조건을 나눌 때 평가 순서와 short-circuit을 보존한다. observer를 위해 추가 map lookup, `proof.valid()`, generation read, revision lookup을 수행하지 않는다. diagnostic OFF에서는 observer 자체가 compile-out되어야 한다.

per-binding 결과는 wrapper에서 **한 terminal outcome만** 집계한다. 성공 buffer/texture/snapshot hit와 slow success, 실패를 구분하여 다음 등식을 검사한다.

`bindingVisits = bufferHits + textureCacheHits + bindingSnapshotHits + slowSuccess + bindingFailures`

`residualVisits <= bindingVisits`이며 서로 더할 범주가 아니다. snapshot miss 후 일부 객체를 이미 확보한 경우도 최종 결과는 slow success 또는 failure 하나다. group snapshot 도중의 failure는 binding loop 이전일 수 있으므로 binder failure와 별도다. 기존 `indirectGroupPreparations`나 `textureProofReady` 의미는 조용히 바꾸지 않는다. 새 필드/schema 주석으로 구분한다.

### 구현 파일·검사·수집 조건

진단 구현 예상 파일은 `MVKCommandEncoderState.mm`, `MVKMetal4PreparedResource.h`, `MVKMetal4Submission.h/.mm` 네 개다. 새 count를 기존 field table과 saturation merge에 등록하고 serializer에 포함한다. `MVKBackendTimeline`의 대형 timeline/epoch/control 기능은 건드리지 않는다.

기존 `metal4-r44-backend-cost-cpu.mm`에서 필드 누락·sum/overflow·delivery-bin·ON/OFF를 확인하고, 기존 production helper fixture에서 exact/proof full/partial/no-entry/revision/owner 만료/stability 변경 및 실패의 상호 배타성을 확인한다. full binder의 roots/direct/implicit/result 경로는 현재 `metal4-prepared-recording-vulkan.mm` 관련 사례에서 결과와 카운터를 함께 확인한다. helper를 다시 구현한 모형으로 실제 binder의 집계 위치를 증명했다고 하지 않는다. collector 단위 검사만으로 native/게임 합격을 주장하지 않는다.

진단 자료는 기존 `MVK_CONFIG_BACKEND_COST_STATS=1` 모드를 이용한다. per-batch stats·queue stats·timeline·capture는 OFF로 두어 매 제출 로그와 별도 collector가 섞이지 않게 한다. 시작·종료 host anchor로 warmup 이후의 **완전히 포함된 1초 delivery bin**만 선택한다. 경계에 걸친 bin은 제외하고 제외 범위도 기록한다. 그 수치를 정확한 simulation frame/GPU 실행 frame의 카운트라고 부르지 않는다. 300초 밖이면 현재 collector로 판단 불가이며 window를 조용히 늘리지 않는다.

### 진단 자체의 비용과 복원

1. source/build owner 하나가 현재 핀·빌드 옵션·raw dylib·packaged 후보를 고정한다. 진단 수정 전에 보호 대상 baseline을 receipt에 기록한다. 새 source checkout/의존성 복제/전체 build backup을 만들지 않는다.
2. 같은 active MVK build lane에서 일시적으로 diagnostics ON 빌드. **이름이 분리된 진단 산출물**로 보관하며 현재 후보 앱의 library를 덮어쓰지 않는다. 다른 source/build 작업과 동시에 configure하지 않는다.
3. 같은 ON 바이너리에서 runtime OFF/ON을 비교한다. 단, ON 컴파일의 layout/분기 영향도 있으므로 원래 release OFF 후보를 별도 대조한다. 최소 묶음은 `release-OFF → diagnostic-runtime-OFF → diagnostic-runtime-ON → diagnostic-runtime-OFF → release-OFF`의 동일 짧은 구간이다. 새 GPU sampler를 동시에 켜지 않는다. 이것은 **조건이 정리되고 별도로 실행할 후속 계획**이지 이번 실행 예약이 아니다.
4. ON의 FPS·p95/p99·제출 CPU 시간이 OFF 반복 범위를 일관되게 벗어나거나 순위가 바뀌면 시간/FPS 귀속에 사용하지 않는다. 그때 counter는 조건부 빈도 정보로만 남기고, 계측을 더 쌓아 정확도를 가장하지 않는다. 마지막 최적화 성능 판정은 release OFF끼리 한다.
5. 수집 후 일시 진단 패치를 제거하고 원래 C/CXX/OBJC/OBJCXX flags로 configure·증분 재빌드한다. `CMakeCache.txt`만 복사해 빌드 규칙까지 복원됐다고 하지 않는다. 소스/빌드 옵션 핀을 대조하고 새 raw hash를 기록한다. 비결정적 rebuild가 원래 hash와 다르면 exact 복원이라고 주장하지 않으며, 보존한 기존 packaged 후보는 계속 불변 기준이다.
6. runtime acceptance에는 기존 종료 조건도 필요하다. 현재 미해결 종료 실패를 고치려는 추측 변경, 강제 종료, timeout 완화, 실패 표본 폐기로 넘어가지 않는다. 재발하면 raw 자료를 보존하고 별도 종료 조사로 넘긴다. 과거 다른 작업이 섞인 FPS와 새 표본을 합산하지 않는다.

### 다음 구현을 선택하는 기준

- recording/pipeline group full hit가 주류이고 slow slot이 적으면 descriptor 해석/vector 최적화는 중단한다. root/direct/implicit의 실제 방문 결과만 보며 cache를 한 겹 더 추가하지 않는다.
- residual/slow 방문과 실제 slot 처리량이 충분히 반복되고 OS call tree에서도 해당 준비·복사 작업이 다시 보일 때만 immutable 해석 축소나 bounded scratch 재사용 설계를 구체화한다. 빈도만으로 시간 비중을 추정하지 않는다.
- snapshot replay가 주류라면 payload 해석은 이미 생략되고 있다. 다음 기록의 live validation/retention을 지우는 방향은 제외한다.
- ownership/revision 변화가 주류라면 실제 descriptor 갱신과 수명 변경을 먼저 설명한다. 이것이 곧 불필요한 invalidation이라는 결론은 아니다.
- 이 최소 분류로 후보가 나오지 않으면 “선정 근거 없음”으로 종료한다. 전면 계측/감사 프로젝트로 확대하지 않는다.

## 별도 후속으로 남는 것

| 영역 | 현재 상태 | 재개에 필요한 근거 |
|---|---|---|
| 기록 간 공유 확대 | CPU snapshot 공유와 fresh ownership 분리 구현은 있음. 그 이상의 안전한 변경 설계는 미완료 | 위 실제 miss/slow 경로 결과와 시간 근거 |
| allocator 정책 확대 | 기존 공유 epoch 구현은 완료. 추가 상향 설계는 없음 | 실제 create/reuse/reset/seal 사유·메모리 peak와 CPU 비용 |
| pass 병합/중간 resolve | encoder 생성 관측은 있음. 중복 경계라는 증거 없음 | 종료 사유·attachment/subresource·load/store/resolve·query/alias/producer-consumer 분류 |
| barrier/wait 축소 | 이번에 새 제거 대상 확정 안 됨 | 정확한 의존 대상과 critical-path blocked time. worker idle wait와 구분 |
| native 종료 실패 | 기존 관찰의 실패 사실 유지, 원인 미확정 | 해당 callback/PID 종료 경계의 별도 조사. 이번 binding 수정 효과로 해소됐다고 간주하지 않음 |

후속 구현은 **SOL 6.1 + High**로 위 작은 typed 호출부부터 가능하다. 이후 독립 검수는 **Astra + High**로 변경 범위만 확인한다. descriptor snapshot 수명·동시성이나 공유 정책 재설계가 실제로 필요해지면 **Astra + Max**에서 다시 설계한다. 이는 작업별 권장이며 현재 runtime 모델을 조회했다는 주장은 아니다.

이번 산출물은 이 문서와 [설계 receipt](../artifacts/validation/v104-binding-cost-analysis-20261020/design-receipt.json) 두 개다. 제품·fixture·빌드 설정·앱·프로필·공유 조정 기록을 수정하지 않았고 빌드/테스트/게임/업로드/정리/다른 채팅 메시지를 실행하지 않았다. receipt의 파일 hash 대조는 해당 파일 범위의 확인이며 전체 앱·전체 workspace 무변경 검사로 확대하지 않는다.
