**R 첫 묶음 1·2 — 독립 소스 검수용 제안**

1번은 최대16원소의 per-binding 배열 세 종류에 한정한 작은 선예약 후보를 준비했다. 2번은 확인한 push-first 경로에서 줄일 반복 조회가 없어 보류한다. 이 문서는 적용 전 제안이다. 제품·fixture는 아직 수정하지 않았고 빌드·테스트·게임을 실행하지 않았다.

**기준**

root가 복원한 정확한 R 소스 39핀과 일치한다. group locator/D/E를 다시 넣지 않는다. 선택 R 앱과 비교용 네 앱·원 launcher는 이번 작업에서 쓰지 않았다. raw build는 여전히 이전 RLookup이므로 R 소스와 일치한다고 주장하지 않는다. allocator32/growth2MiB/available8/idle64MiB와 diagnostics OFF를 유지한다.

**1번 제안**

[unit1.patch](${WORKSPACE}/artifacts/validation/v104-r-small-bundle-20261021/unit1.patch)는 binder 제품 파일 하나의 여섯 삽입 지점만 바꾼다.

| 배열 | 예약할 예상 원소 수 | 기존 적격성 상한 |
|---|---|---|
| bufferProofs | count | 16 |
| textureProofs | resourceCount; 해당 경로는 buffer0 | 16 |
| snapshotResources | resourceCount | 16 |

기존 live/retain/proof 검사를 통과한 첫 원소를 넣기 직전에만 expectedCount>1, empty, capacity 부족을 확인하고 reserve한다. group hit·개별 cache hit는 이 지점을 지나지 않는다. 첫 원소가 유효하지 않으면 예약하지 않는다. 부분 replay 실패 뒤 clear가 남긴 capacity도 재사용한다. snapshot-to-group의 필요한 복사는 유지하고, 배열 저장소는 기존 persistent entry로 std::move한다. global/threadlocal scratch, 다른 container, 추가 소유권 공유는 없다.

여기서 0/1은 **해당 배열의 예상 원소 수**다. 단일 combined image+sampler descriptor는 resourceCount2일 수 있다. 이런 경우 원래 두 번 성장할 수 있는 배열이 후보에 포함된다. descriptorCount1을 모든 배열 길이1과 혼동하지 않는다.

성공하는 다원소 수집에서는 중간 성장 할당·원소 이동을 줄인다. 단일원소에는 추가 할당이 없지만 작은 조건 분기는 추가된다. 첫 유효 원소 뒤에 나머지가 실패하면 기존보다 큰 임시 capacity를 잡을 수 있으며, 배열별 최대16원소다. 이 제한을 공개한 통제 실험 후보이지 모든 입력의 무비용·FPS 순이익을 증명한 것은 아니다. 실제 BAR의 길이·실패 분포는 없고 새로운 collector는 만들지 않는다.

입력 SHA256은 `9b28b9a30f6e0d8a975b732dcaf8a49c8e14b32f9ba3157e4f9dce03b14276b9`, 제안 결과는 `b1013a4a907210de7f527f550758824d1dfcf5d79b05266a984aa2a1e97e62e3`, patch는 `d2cc1b83b29b8b83ed5ffd42eea85fd2f95e9bfb92881b20ea4b625fbb99641e`다. 원본은 그대로다.

**2번 판정**

현재 Zink는 프로그램의 push_usage와 변경 상태가 있는 경우 push-template를 masked descriptor set 갱신보다 먼저 낸다. MVK의 compact capture도 같은 push-template 명령 class이며 조기 기록 policy override가 없어 Deferred다. 첫 Deferred가 early flag를 내리므로 그 뒤 static descriptor bind의 layout flags/type 순회는 호출되지 않는다. 이 경로에서는 생성 시 사전 분류로 줄일 반복 일이 없다.

이는 BAR 전체 호출0의 증명이 아니다. push 미사용·변경 없음·push 이전 bind·separable/다른 descriptor mode 등의 예외는 가능하지만, 현재 자료로 의미 있는 반복 도달을 입증하지 못했다. 4번 State 승격이나 새 collector로 2번을 살리지 않는다. [unit2.patch](${WORKSPACE}/artifacts/validation/v104-r-small-bundle-20261021/unit2.patch)는 의도적인 0바이트이며 별도 보류 판정을 뜻한다.

**검수 이후의 최소 검증 계획**

- 기존 descriptor/prepared-texture CPU fixture에서 실제 helper와 변경된 수집 본문을 추출해 사용한다. 따로 베낀 수집 로직만 검사하지 않는다.
- fixture에서만 할당을 관찰하여 예상 길이0·1·2·3·16, hit/negative, 첫·늦은 무효 proof, 등록 실패, partial replay→clear→fallback을 전후 대조한다.
- 기존 remember의 vector move 후 identity·weak ownership·entry 생존/clear를 확인한다. 최종 cache로 옮길 때 추가 저장소 할당이 없는지도 확인한다.
- 소스 검수 후 실제 적용·관련 CPU 검사 → 단일 active lane 증분 빌드·foundation OFF syntax → 변경 경로에 필요한 기존 Vulkan M3·M4 선택 사례만 진행한다. GPU 시작은 root와 조정한다.
- 관련 검증이 통과한 경우에만 R-small-bundle 앱을 별도로 동결한다. 게임/FPS와 채택은 root의 다음 단계다.

개별 철회는 unit1.patch의 역적용이며, 필요한 fixture 보완은 별도 patch로 남긴다. 이번 제품 변경에 group64 선예약·allocator·pass·동기화·11a·#2837은 없다. 상세 계약과 근거는 [design.json](${WORKSPACE}/artifacts/validation/v104-r-small-bundle-20261021/design.json), 현재 39핀과 제안 postimage는 [source-proposal.json](${WORKSPACE}/artifacts/validation/v104-r-small-bundle-20261021/source-proposal.json)에 있다.
