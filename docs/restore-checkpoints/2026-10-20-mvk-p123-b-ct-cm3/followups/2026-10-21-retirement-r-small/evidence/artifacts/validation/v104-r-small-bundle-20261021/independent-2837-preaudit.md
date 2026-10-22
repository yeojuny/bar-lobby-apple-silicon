# MVK2837 독립 사전 검수

판정: **고정 PR을 그대로 이식하는 것은 권고하지 않습니다. dynamic offset의 길이/packing 변경을 보수적으로 처리하고, residency용 affected-set 무효화는 먼저 유지하는 좁은 이식은 검토할 수 있습니다.** 현재 R+reserve 소스는 수정하지 않았습니다.

[PR2837](https://github.com/KhronosGroup/MoltenVK/pull/2837)의 두 파일 patch/blob이 기존 head `5978a64ae125333457ebc35ab1f80321a7eb3924` manifest와 일치합니다. 현재 State.mm은 적용된 reserve 핀 `b1013a4a907210de7f527f550758824d1dfcf5d79b05266a984aa2a1e97e62e3`입니다. 상세 입력/remote patch SHA는 짝 JSON에 있습니다.

## 먼저 수정할 구체 반례

PR helper는 dynamicOffsets를 늘린 **뒤** 기존 값과 비교합니다. 새 영역은 0으로 초기화되므로 새 offset이 0이면 바뀌지 않았다고 판정할 수 있습니다. 하지만 이미 Metal에 설정한 immediate bytes의 길이는 늘어나지 않았습니다.

예: M3 compute P1에서 set0 A의 dynamic descriptor 하나와 set1 S의 하나를 [0,0]으로 bind/dispatch합니다. P2 layout은 set0 B에 dynamic descriptor 두 개가 있고 set1은 동일 정의의 S layout을 유지합니다. B와 동일 S를 [0,0,0]으로 다시 bind하면 새 vector 원소도 0이므로 PR의 changedData가 false일 수 있습니다. B 때문에 changedSets가 켜져도 descriptorSetData만 지우며 implicit buffer는 지우지 않습니다. compute의 DynamicOffset slot은 Pipeline.mm:2937에서 고정되어 있으므로, 다음 dispatch가 같은 slot의 예전 2-word setBytes를 유지한 채 세 번째 offset을 필요로 할 수 있습니다. descriptor 내용 갱신이 없는 layout/rebind 사례입니다. 실제 실행하거나 BAR에서 발생했다고 주장하지 않았습니다.

근거는 State.mm:1119의 helper, SmallVector resize의 기본 0, State.mm:1440의 implicit-exists 조기 반환, Pipeline.mm:2937의 고정 slot입니다. **grow/new meaningful range는 resize 전부터 dirty로 표시**해야 합니다. packing/layout 관계가 증명되지 않은 전환도 보수적으로 무효화합니다. 기존 offset 소비 순서·stage별 건너뛰기·마지막 개수 assertion은 보존합니다.

## 동일 포인터와 자원 등록

State.mm:1411–1418은 새 set으로 판정될 때만 binding별 descriptorSetResourceUse를 비웁니다. 이후 :1333–1338은 이 비트가 있으면 CPU payload를 읽지 않고 UseResource를 건너뜁니다. 따라서 동일 주소의 set이라는 이유만으로 내용·native resource·allocation incarnation까지 같다고 할 수 없습니다. 허용된 mutable 갱신이 실제 later native encode 전에 반영되는 경로라면 X→Y 변경 후 Y 등록을 놓칠 수 있다는 상태 계약 반례가 있습니다. 실제 GPU 재현으로 단정하지 않으며, device residency set이 없는 legacy argument-buffer 경로에 노출되는 문제입니다.

일반 non-UAB set을 bind한 다음 임의 갱신하는 예는 [Vulkan 규칙](https://docs.vulkan.org/refpages/latest/refpages/source/vkUpdateDescriptorSets.html)에 따라 recording/executable command buffer 자체를 무효화하므로 버그 근거로 사용하지 않았습니다. UAB/unused 허용 범위·host 동기화·실제 encoding 시점이 맞는지 별도로 확인해야 합니다. **가장 좁은 첫안은 residency용 affected clear를 유지하는 것**입니다.

기존 version metadata는 공짜인 공통 해답이 아닙니다. DescriptorSet.mm의 write/copy revision 갱신과 field 자체는 foundation ON에서만 존재하고, nonzero incarnation은 runtime M4의 eligible argument-buffer set에만 생성됩니다. M3, foundation OFF, UAB/unused 등 비적격·0/overflow에는 기존 경로가 필요합니다. 이후 이를 활용한다면 이전 bind 때의 incarnation/revision을 값으로 보관해야 합니다. 같은 live object의 현재 revision을 두 번 읽는 방식은 갱신 검출이 아닙니다.

## layout·helper·encoder 계약

PR의 descriptor pointer 배열 0 초기화는 pre-bind 비교 도입 시 유지해야 합니다. 특정 owner가 우연히 value-initialize하는 데 의존하지 않습니다.

동일 S를 다른 pipeline layout과 bind할 때, 앞쪽 set 때문에 dynamic packing이 달라질 수 있습니다. 현재 common._layout은 pipeline bind가 이미 갱신했을 수 있어 직전 descriptor bind가 사용한 layout과 동일한 기록이 아닙니다. memo를 쓴다면 실제 이전 packing 관계를 담아야 하며, 동일 정의의 별도 layout을 보수적 miss로 처리해도 됩니다. 현재 R의 no-dynamic/argument-buffer graphics fast path도 보존합니다.

새 render/compute encoder는 기존 reset을 통해 exists와 shared use history를 비웁니다. 같은 Vulkan pointer라도 첫 사용은 등록·바인딩해야 합니다. helper가 덮은 argument-buffer slot도 bindMetalResources의 root bind/cache 검사로 복원합니다. pointer 비교를 전체 prepare의 조기 반환으로 확장하면 안 됩니다. 로컬 M4의 helper/table-slot revision 복구도 별도 계약입니다.

## 구성별 적용 범위

| 구성 | 판단 |
| --- | --- |
| foundation OFF / M3 | version field 없음. dynamic 길이 반례와 legacy useResource 경계를 그대로 검토해야 함. |
| foundation ON / runtime M3 | M4용 stamp가 유효하게 초기화되지 않음. device residency 여부에 따라 legacy UseResource 노출이 다름. |
| foundation ON / native M4 | 기존 세 invalidateMetal4ImplicitBuffer는 별도 slotRevision을 무효화함. PR의 changedData만 이식해도 이 비용은 계속 남으므로 M4까지 최적화했다고 주장하면 안 됨. |
| foundation OFF / native M4 | native M4 제공 구성이 아님. runtime 검증 통과 lane으로 세면 안 됨. |

## 권고하는 최소 범위

1. 배열 초기화와 실제 값·유효 길이/packing이 변하지 않은 legacy implicit dirty 처리만 좁게 이식합니다. fresh/grown/불명확 layout이면 원래 무효화합니다.
2. residency용 affected clear, argument root 복구와 로컬 M4 별도 implicit invalidation은 첫안에서 유지합니다. 별도 성과·검증 없이 범위를 넓히지 않습니다.
3. 기존 관련 CPU/native fixture에 all-zero 성장·prefix-layout 변경·다중 set/stage·새 encoder·helper 복구를 좁게 확인합니다. 같은 포인터의 자원 갱신을 검증할 때는 legal Vulkan schedule과 상태 모의 검증을 구분합니다. foundation OFF와 ON M3/M4도 구분합니다. 새로운 전체 suite·collector를 요구하지 않습니다.

동일 set 반복 빈도·절감 시간·FPS 이익은 미확인입니다. 유용한 선례이지만 현재 상태의 단순 cherry-pick을 안전하다고 승인하는 결론은 아닙니다.

첫 reserve 후보의 옛 build.json은 copy2가 R header의 옛 mtime을 복원하여 RLookup ABI 객체가 잔존할 수 있었으므로 qualification 보류입니다. root-build-qualification-correction.json의 정정 incremental build/new raw SHA와 연결된 후속 native/GPU/package만 최종 readiness 증거로 인정합니다. 이 검수는 제품·fixture·build 쓰기/컴파일·테스트·GPU·앱·게임·계측 모두 0회이며, 이 두 독립 사전 검수 파일만 저장했습니다.
