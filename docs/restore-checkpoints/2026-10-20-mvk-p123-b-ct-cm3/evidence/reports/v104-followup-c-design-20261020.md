# v1.0.4 후속 C 설계 검토

2026-10-20. 요청 설정 Astra + Max로 현재 소스와 기존 완료 기록을 대조했다. **권장 다음 구현은 descriptor 준비·복사 두 항목을 묶는 것이다.** GPU 수명이나 동기화 계약을 바꾸는 큰 작업보다 먼저, template의 불변 메타데이터를 생성 때 계산하고 기존 Metal4의 정확한 입력 복사를 Metal3에도 제한적으로 적용하는 설계를 제안한다. 두 번째는 이번 검토에서 구체화한 추가 제안이며 아직 구현하지 않았다.

이번 산출물은 설계 문서와 입력 해시 기록뿐이다. 제품·fixture 수정, 빌드, CPU/native/GPU 검사, 앱·게임 실행, 설정·설치·게시·정리는 하지 않았다. 독립 검수자가 별도로 검수한 결과가 아니다.

## 출발점

- 동결 기준은 healthbar/tracker 호환을 포함한 v1.0.3이다.
- 현재 누적 후보는 [P1~P3와 B를 반영한 앱]($WORKSPACE/artifacts/runtime/v104-performance-ab-candidate-20261020/BAR.app)이다. 표시 버전은 1.0.3이고 정식 v1.0.4 배포판이 아니다.
- A는 선택 콘텐츠에서 개선 대상 호출이 확인되지 않아 제외했다. B의 작은 배열 변경은 완료됐으며 현재 `MVKCmdDraw.mm` SHA256 `2e2ffdb95b7ce8ccdd04ea8ceecd5756d10d0d7af04f9bb37fcddcb2952ad2a8`이 인계값과 일치한다. B의 FPS 효과는 미측정이다. [A/B 완료 및 패키징](v104-followup-ab-20261020.md)
- 최신 P1~P3 비교는 Metal3 45.37→44.67 FPS, Metal4 39.10→39.12 FPS, 각각 두 표본이다. 확정 개선·회귀 판단에 충분하지 않다. AA Off, 실제 EGL sampleBuffers=0 조건이다. 과거 4×MSAA 결과와 같은 조건으로 취급하지 않는다. [최신 비교](v104-performance-retest-20261020.md)

## 후보 묶음과 우선순위

| 구분 | 소유 계층과 변경 | 판단 |
|---|---|---|
| **C-T 불변 template 준비** | MVK descriptor template 생성 때 singleton UBO 여부와 정확한 최대 읽기 끝 위치를 계산. 명령 기록 때 같은 형식·offset 검사를 반복하지 않음 | 다음 구현 우선. 기존 C2-T 설계를 현재 소스에 다시 확인하고 오류·fallback 경계를 구체화 |
| **C-M3 정확한 입력 복사 공통화** | Metal4에서 이미 쓰는 singleton UBO compact capture를 Metal3에도 적용하되, 기존 capture보다 저장·복사 범위가 작은 경우에만 선택 | C-T와 같은 descriptor 묶음으로 제안. Metal3 실제 경로의 새 검증이 필요 |
| **C-L layout 분류 저장** | 직접 기록이 허용되는 layout의 flags·타입 분류를 생성 때 한 bit로 저장 | 미적용 후보지만 후순위. 일반 Zink push가 먼저 Deferred로 전환시키면 뒤 bind에는 효과 없음 |
| 기록 간 descriptor 준비 재사용 | 기존 snapshot·binding revision·recording별 retention과 R4/R5 동작 유지 | 이미 구현된 부분을 다시 세지 않음. 추가 공유 범위 확대는 이 묶음에서 제외 |
| allocator 공유·회수 확대 | 기존 epoch 공유, 단일 CPU writer, 마지막 사용자 뒤 reset 유지 | 이미 구현. 상한을 크게 늘릴 현재 비용 근거 없음 |
| pass·resolve·barrier·완료 대기 축소 | 필요한 producer→consumer 관계, alias, query, drawable, 완료 확인 유지 | R87 보류 유지. 별도 구체적 비용·API 조건이 확보될 때만 재설계 |

C-T와 C-M3는 같은 자료를 준비하고 소비하는 변경이므로 관련 검사를 묶을 수 있다. 패치 안에서는 각각의 의미를 구분해 검토한다. C-L이나 동기화 변경까지 한 번에 섞는 것은 제안하지 않는다.

## C-T 불변 정보와 호출마다 달라지는 정보 분리

현재 [captureMetal4Uniforms]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdPipeline.mm:554)는 template의 각 entry가 UBO 한 개인지 확인하고, 호출에 전달된 layout을 검사한 다음, 모든 source offset의 덧셈 범위를 다시 순회한다. [template 생성자]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.mm:2303)는 이미 entry를 한 번 순회해 소유 복사한다.

생성자의 기존 순회에서 아래 정보만 소유 객체에 저장한다.

- 모든 entry가 `VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER`, `descriptorCount == 1`인지.
- `offset + sizeof(VkDescriptorBufferInfo)`가 표현 가능한지. 실패는 상태로만 보관한다.
- 표현 가능한 각 끝 위치의 최대값 `maxReadEnd`.

현재 template의 type·bind point·entry count 저장은 그대로 사용한다. 새 map, 전역 cache, 추가 잠금, 생성 때의 pipeline/layout raw 포인터는 필요 없다. 공유 가능한 것은 불변 해석 정보이며, 현재 입력 주소나 GPU 버퍼 내용이 아니다.

호출 시에는 다음 순서를 유지한다.

1. 현재의 pData/count/template type/bind point/push set 조건을 검사한다. 부적격 형식은 기존 generic 경로로 보낸다.
2. **이번 호출에 전달된 layout**의 각 binding 타입과 목적 배열 범위를 검사한다. 생성 때와 호환되는 다른 layout이 올 수 있다.
3. 모든 적격성 검사가 끝난 뒤에만 저장한 overflow 상태, 현재 pData base와 maxReadEnd의 합, compact 저장 크기를 검사한다. 부적격 layout이 있는 template에서 overflow 오류를 먼저 내어 기존 fallback을 바꾸지 않는다.
4. 현재 descriptor 값만 기존처럼 복사한다. offset 사이의 빈 공간을 읽거나 maxReadEnd 전체를 연속 복사하지 않는다.

최대 끝 위치는 같은 정수 범위에서 각 offset 덧셈 검사를 요약할 수 있다. 현재 generic `_size`는 stride를 포함한 다른 의미이므로 maxReadEnd의 대용으로 쓰지 않는다. 특히 singleton의 두 번째 원소가 없으므로 stride가 payload 끝 위치를 정하지 않는다. [Vulkan entry 주소 규칙](https://docs.vulkan.org/refpages/latest/refpages/source/VkDescriptorUpdateTemplateEntry.html)

Vulkan은 push에 전달되는 layout의 호환성을 요구하며, template 생성 구조체의 descriptorSetLayout을 생성 호출 뒤 계속 참조하도록 허용하는 계약도 아니다. 객체가 소유하는 entry 값만 요약해야 한다. [push 계약](https://docs.vulkan.org/refpages/latest/refpages/source/vkCmdPushDescriptorSetWithTemplate.html), [생성 계약](https://docs.vulkan.org/refpages/latest/refpages/source/VkDescriptorUpdateTemplateCreateInfo.html)

반복되는 N-entry 형식 검사와 별도 N-entry overflow 순회를 줄이지만, 현재 layout 확인과 N-entry payload 복사는 남는다. 생성 시 계산과 객체당 작은 상태·size 필드 비용이 추가되므로 한 번만 쓰는 template에 순이익을 보장하지 않는다. 실제 object 크기와 추가 padding은 구현 때 확인한다. lazy 초기화로 새 쓰기 경쟁을 만들지 않는다.

## C-M3 Metal3에도 필요한 descriptor만 소유

현재 [setContent]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdPipeline.mm:624)는 `mvkUseMetal4()`일 때에만 compact capture를 시도한다. Metal3는 template의 generic 크기까지 앞부분을 복사한다.

Zink는 [push template]($WORKSPACE/build/run66-mesa-src-20260903/src/gallium/drivers/zink/zink_descriptors.c:1672)에 context 내부 UBO 위치를 offset으로 넣고, [실제 push 호출]($WORKSPACE/build/run66-mesa-src-20260903/src/gallium/drivers/zink/zink_descriptors.c:1455)에는 context 시작 주소를 준다. 따라서 이 입력에서는 descriptor 사이 공간과 앞부분을 소유 복사할 필요가 없다. push 기능·descriptor mode·uniform 변경 여부가 호출 조건이며 매 draw 무조건 호출된다고 세지 않는다.

공통화의 소스 근거는 다음과 같다.

- [두 pushDescriptorSet overload]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm:2571)는 동일한 CPU push 저장소를 준비한다.
- [write 방식과 template 방식]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.mm:1832)은 최종적으로 같은 `writeDescriptorSetCPUBufferDispatch`를 사용한다.
- 적격한 UBO 한 개에 대해 source 값, dstBinding, dstArrayElement, 처리 순서가 같으면 같은 CPU descriptor 결과를 만들 수 있다. 중복 목적지도 순서를 바꾸지 않는다.

**단순히 Metal4 조건을 삭제하는 것으로 끝내지 않는다.** generic 입력이 촘촘하고 작으면 compact 쪽의 write metadata가 오히려 더 클 수 있다. Metal3에서는 안전한 크기 계산 후 아래 조건을 추가한다.

`genericCaptureBytes > N × (sizeof(VkDescriptorBufferInfo) + sizeof(VkWriteDescriptorSet))`

이는 CPU 소유 payload의 크기 증가를 피하는 조건이다. CPU 실행 시간의 순이익까지 보증하는 기준은 아니다. 조건을 만족하지 않는 작은 입력은 기존 Metal3 generic 경로를 유지한다. Metal4의 현재 적격성·선택 동작은 바꾸지 않는다.

구현 경계는 다음과 같다.

- backend와 무관한 capture 부분은 공통 이름·선언으로 정리한다. M3의 일반 기능을 Metal4 빌드 스위치에만 매다는 임시 구조를 피하고 foundation ON/OFF를 함께 확인한다.
- descriptor 값은 Vulkan 기록 호출 시 복사하고, 그 descriptor가 가리키는 mapped buffer 내용은 기존 GPU 사용 시점의 값을 유지한다. uniform buffer 전체를 기록 시점에 복사하는 변경이 아니다.
- 명령의 기존 `_pData/_dataCapacity` 저장소, layout retain/release, 실패한 node 회수, generic↔compact 재사용을 유지한다. 다른 command·recording과 payload를 공유하지 않는다.
- array/spill, 이미지·fbfetch 혼합, 다른 descriptor type은 generic 경로를 유지한다. 일반 template 크기 계산의 기존 stride 문제 전체를 이 작업으로 해결했다고 주장하지 않는다.
- Metal4의 record policy는 계속 Deferred다. Metal3 prefill/일반 재생 시점도 바꾸지 않는다. 새 GPU 명령이나 barrier는 필요하지 않다.

이 항목은 현재 Metal4에만 적용된 CPU 최적화의 공통화를 검토하는 것이며, 새 Metal3 GPU 결과나 FPS 이득은 아직 없다. 보호된 sparse 입력, unaligned 입력, 실제 push CPU 결과를 비교해야 한다. 복사 byte 감소만으로 성능 향상률을 제시하지 않는다.

## C-L의 우선순위가 낮은 이유

현재 [getMetal4RecordPolicy]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdPipeline.mm:361)는 descriptor bind마다 layout의 buffer 네 종류와 Vulkan binding flags 0x0f를 순회한다. 생성 시 최종 flags가 합쳐진 뒤 결과를 layout 안에 저장하면 반복 순회를 한 bit 확인으로 바꿀 수 있다. 빈 layout, count 0 binding, dynamic-offset 하위 클래스와 null 검사 의미를 유지해야 한다. 기존 다른 cache의 적격성은 variable-count 허용 범위가 달라 재사용할 수 없다.

그러나 [명령 추가]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm:337)는 첫 Deferred 뒤에 early policy를 더 이상 호출하지 않는다. Zink는 uniform push를 다른 set bind보다 먼저 내보내며 현재 push-template 명령은 Deferred다. 그 순서에서는 후속 bind의 분류 계산을 줄여도 실행 비용이 줄지 않는다. 다른 prefix에서 적용될 가능성은 있으나 현재 빈도는 확인되지 않았다.

따라서 예전 C2-L→C2-T 순위를 그대로 따르지 않는다. **항상 안전한 플래그처럼 보인다는 이유보다 실제 도달 범위가 넓은 C-T와 공통 입력 복사에 우선순위를 둔다.** C-L을 위해 push를 State로 승격하거나 직접 기록 whitelist를 확대하지 않는다.

## 기존 C 영역의 현재 계약

### Descriptor cache와 기록 간 재사용

현재 [group cache]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4PreparedResource.h:378)는 완전 동일 stamp의 추가 validity 순회를 이미 생략한다. R4도 [간접 목록이 비었을 때]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm:145) 그룹 준비만 생략한다. roots/direct/dynamic/implicit 처리는 별도 유지한다.

기록을 넘는 CPU snapshot은 이미 descriptor/pipeline 소유로 존재한다. 현재 recording의 등록·보유 확인은 [recording token]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm:600)과 분리돼 있다. 관계없는 전역 epoch 변경도 무조건 payload 재생으로 떨어지지 않고, 사용 binding revision과 살아 있는 proof를 다시 확인해 stamp를 갱신할 수 있다.

따라서 “새 기록에서도 cache를 유지하면 된다”는 안은 이미 한 부분과 필요한 새 ownership을 혼동한다. 전역 epoch 제거, weak proof를 주소 비교로 대체, drawable 세대 확인 생략은 이번 안이 아니다. 추가 이득을 주장하려면 현재 miss 원인·fresh retention 비용이 필요하다.

### Allocator와 완료 경계

현재 [allocator epoch]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.mm:651)는 여러 recording의 명령 메모리를 이미 공유한다. CPU writer는 한 번에 하나이며, end 뒤 다른 기록이 사용할 수 있지만 마지막 live use가 사라지기 전에는 reset하지 않는다. 현재 sealing 기준은 32 recordings 또는 reset 기준 2 MiB 증가다. 업로드·argument table·residency 회수는 allocator와 별도로 유지한다.

Apple은 같은 allocator를 순차 command buffer에 사용할 수 있지만, 그 allocator의 명령을 쓰는 모든 GPU 작업이 끝나야 reset할 수 있다고 설명한다. Metal4 command buffer 자체가 자원의 strong reference를 보유하지 않는 점도 별도 ownership을 유지해야 하는 이유다. [Metal4 core API](https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api), [allocator reset 계약](https://developer.apple.com/documentation/metal/mtl4commandallocator/reset())

현재 정책은 이 핵심 제약을 반영한다. 상한 증가·reset 지연은 메모리 점유와 교환될 수 있으므로 생성·reset 압력이 확인되지 않은 상태에서 우선하지 않는다. 완료용 작업의 소유권이나 CPU 제출 정리를 생략하지 않는다.

### Pass와 동기화

현재 [setMetal4Barrier]($WORKSPACE/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm:821)는 compute 내부 의존성과 조건이 맞는 vertex producer에서는 encoder를 계속 사용한다. fragment/image 경로는 여전히 저장 경계를 만든다. 이것을 모두 과잉 동기화로 분류할 근거는 없다.

Apple silicon의 fragment/tile producer를 기다리는 일반 intrapass barrier에는 제한이 있다. 다른 fragment/tile 결과를 읽는 경우에는 새 pass와 동기화가 필요하며, 같은 pixel/tile의 특별한 경우와 구분해야 한다. [Apple 패스 내부 동기화](https://developer.apple.com/documentation/metal/synchronizing-stages-within-a-pass)

R87의 MSAA 계획 조건도 유지한다. 중간 fragment는 encoder 생성 전 resolve attachment 계획을 알아야 하고, 마지막 draw가 없는 종료에도 최종 resolve를 보장해야 한다. 기존 resolve texture에 Store만 지정하는 수정이나 모든 pass 끝에 resolve 전용 pass를 추가하는 안은 추천하지 않는다. 상위 Zink가 이미 끝낸 pass는 MVK 조건 하나를 풀어도 합쳐지지 않는다. 현재 비교의 AA Off는 창의 MSAA가 꺼졌다는 근거이며 모든 offscreen attachment의 sample 수가 1이라는 증거는 아니다. [R87 판단](r87-renderpass-design-20261008.md)

이전 정점 준비 cache 실험도 반복 후보에서 제외한다. correctness 검증은 있었지만 FPS 이득이 확인되지 않았고, 현재 setter 자체가 같은 native write를 이미 생략한다. 기존 실험을 이름만 바꿔 다시 적용하지 않는다. [정점 준비 실험](r92-vertex-preparation-20261011.md)

## 구현 범위와 최소 검증

권장 다음 단위는 **C-T + C-M3 descriptor 준비·복사 묶음**이다. 명령/descriptor 관련 MVK 파일 4개 내외와 기존 검사만 예상한다. 엔진·Mesa·LuaUI·shader·sync identity·numeric·AI를 수정할 이유는 없다. 새 저장소 수명 계층이나 동기화 재설계가 필요해지면 이 범위를 벗어난 것이다.

| 검증 | 필요한 관측 |
|---|---|
| 기존 descriptor CPU 검사 보강 | 실제 template constructor 또는 그 안의 실제 분류 코드를 실행. 현재 stub에 요약값만 하드코딩하면 새 구현 검증이 되지 않음 |
| C-T 경계 | empty/mixed/array/spill, 최대 offset이 마지막이 아닌 경우, static/base overflow, 호환되는 다른 layout, fallback과 오류 우선순위, template 생성·파괴·재생성 |
| C-M3 byte·출력 동치 | sparse·unaligned·stride 0/8/정상/큰 값, 중복 목적지·부분 갱신 보존, 호출 뒤 입력 변경, mapped 내용은 GPU 사용 시점 값, small-input generic 유지 |
| 기존 저장소/오류 검사 | OOM 뒤 정상 재사용, large→small→medium, pooled/unpooled node 회수와 layout 소유권, compact↔generic 전환 |
| 빌드 | 활성 MVK 증분 빌드와 foundation ON/OFF 관련 문법 확인. 엔진 재빌드는 불필요 |
| 실제 GPU | 기존 offscreen Vulkan의 해당 template/push 사례만 M3·M4에서 결과 비교. 현재 metal4-vulkan-integration은 main에서 M4를 강제하고 native queue를 assert하므로 그대로 실행한 결과를 M3 검증으로 부르면 안 됨 |

GPU 검사에는 기존 fixture에 명시적인 backend 기대값과 공통 template 사례 선택을 추가하는 정도의 한정 변경이 필요하다. M4 모드의 native4 assert를 약화하거나 legacy fallback을 성공으로 처리하지 않는다. M3는 실제 legacy queue와 GPU 결과·완료를 확인하고, M4 전용 완료 counter 검사를 M3에 전용하지 않는다. 별도 측정 플랫폼이나 전체 suite 재실행을 만들지 않는다.

이번 좁힌 구현은 **SOL 6.1 + High**, 변경분 독립 검수는 **Astra + High**를 권장한다. immutable metadata와 command-local 소유 범위를 넘어서 기록 간 공유·제출/완료 계약을 바꾸게 되면 **Astra + Max 설계**로 다시 구분한다. 이 권장은 작업 범위에 대한 판단이며 모델 간 성능 측정 결과가 아니다.

실제 FPS 비교가 필요한 단계에서는 기존 깨끗한 시험 조건을 재사용해 묶음 전체를 비교한다. P1~P3 또는 A/B 검사, 오염된 과거 VBO 점검 위젯, 전체 8회 배치를 자동으로 반복하지 않는다.

## 공식 대조와 근거의 한계

현재 공식 MoltenVK main `5189f8de86ec365860f63bf1da736815cfaea5cd`의 DescriptorSet.h/.mm와 CmdPipeline.mm 원문을 확인했다. 이 세 파일에는 로컬의 `captureMetal4Uniforms`와 `getMetal4RecordPolicy`가 없으며, 읽은 template 생성자는 일반 크기 계산을 유지한다. 따라서 이 후보의 그대로 적용할 공식 구현을 해당 파일에서 찾지는 못했다. 모든 PR·다른 브랜치의 부재를 증명한 것은 아니다. [고정 공식 소스](https://github.com/KhronosGroup/MoltenVK/tree/5189f8de86ec365860f63bf1da736815cfaea5cd/MoltenVK/MoltenVK)

C-T/C-L은 [이전 C2 설계](../artifacts/validation/r92-post-s1-overhead-review-20261013/commands-review.md)를 재사용했다. C-M3는 현재 backend guard와 두 CPU descriptor writer의 연결을 새로 대조한 설계 제안이다. 이전 trace 요약에는 push-template 경로가 관측됐다는 기록이 있지만 raw trace가 정리된 뒤이므로 새 시간 분석이나 현재 hit count로 바꾸어 쓰지 않았다. [보존된 요약](r92-cpu-resource-20261012.md)

Apple core API와 allocator·패스 문서는 공식 Markdown 본문까지 읽었다. 웹 도구의 Markdown content-type 오류는 일반 읽기 요청으로 본문을 확인해 보완했다. 공식 원칙과 현재 API 제약의 대조이며 BAR FPS를 보증하는 자료가 아니다.

검토한 입력 해시·공식 소스 URL과 범위는 [설계 기록](../artifacts/validation/v104-followup-c-design-20261020/design-receipt.json)에 있다. 공유 AGENTS/HQ/coordinator와 자동화는 수정하지 않았다.

