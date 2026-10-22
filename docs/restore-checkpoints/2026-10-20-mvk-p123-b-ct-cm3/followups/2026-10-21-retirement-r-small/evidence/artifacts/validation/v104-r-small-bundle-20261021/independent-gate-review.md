# R 첫 묶음1·2: 독립 도달·경제성 gate 검토

**1번은 좁은 bounded reserve 제안을 검토할 수 있고,2번은 현재 확인한 BAR producer 경로에서 구현 gate 미통과로 보류한다.** 첫 묶음이라고 반드시 두 제품 변경을 모두 넣을 필요는 없다. 모든 입력의 추가 비용0이나 구현 전 FPS 개선 증명을 요구하지 않는다. 유효 다원소 수집의 재성장을 줄이면서 늦은 실패의 작은 임시 capacity 증가를 명시하는 안은 비교 후보가 될 수 있다. 구체 proposal은 아직 없으므로 적용 소스 승인으로 읽으면 안 된다.

R-source-pins39개는 검토 당시 모두 현재 파일과 일치했다. PreparedResource.h는 정확한 R preimage d6222a17…afa653으로 복원됐고 나머지38핀도 유지됐다. 선택 R 앱은 보존됐다. restore-R.json의 명시대로 raw build는 아직 이전 것이므로 소스 복원 자체를 R 라이브러리 재빌드 완료로 세지 않았다. 제품·fixture·build·앱·pointer·profile·공유상태를 쓰거나 테스트/GPU/앱/게임/계측/정리를 실행하지 않았다. 이 두 검수 파일만 저장했다.

## 2번: push-first 경로에서 후속 policy 분류가 도달하지 않는다

[Zink draw](${WORKSPACE}/build/run66-mesa-src-20260903/src/gallium/drivers/zink/zink_draw.cpp:765)는 batch/descriptor 변경 조건에서 descriptor update를 호출한다. [zink_descriptors_update](${WORKSPACE}/build/run66-mesa-src-20260903/src/gallium/drivers/zink/zink_descriptors.c:1345)는 새 batch의 push 상태를 program 사용 정보로 정하고, [1453](${WORKSPACE}/build/run66-mesa-src-20260903/src/gallium/drivers/zink/zink_descriptors.c:1453)에서 필요한 push-template를 먼저 낸 뒤 [1476](${WORKSPACE}/build/run66-mesa-src-20260903/src/gallium/drivers/zink/zink_descriptors.c:1476)의 masked set update/bind로 간다.

[MVKCmdPushDescriptorSetWithTemplate](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdPipeline.h:323)는 policy override가 없고 [base policy](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommand.h:107)는 Deferred다. [addCommand](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm:347)는 early recording일 때만 policy를 호출하고, 첫 Deferred에서 [365](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm:365)의 early flag를 내린다. 따라서 그 뒤 static bind의 [flags/type 분류](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdPipeline.mm:361)는 실행되지 않는다. 이 루프를 layout 생성 때 저장해도 해당 경로의 반복 일이 줄지 않는다.

이것은 모든 BAR prefix에서 호출0이라는 전역 증명이 아니다. push_usage가 없거나 push가 바뀌지 않은 경우, separable/다른 descriptor mode/확장 지원 차이, push 이전 bind는 별도다. 그러나 기존 입력은 그런 예외에서 충분히 반복되는 분류를 보여주지 않으므로 지금2번을 구현할 경제성 근거는 없다. 추가 collector를 요구하지 않는다. 더 안전한 대안은 이 부분을 그대로 두고 기존 자료에 실제 pre-Deferred 반복이 발견될 때만 다시 여는 것이다. 4번 State 승격이나 whitelist/descriptor mode 변경으로2번 도달을 만들어내지 않는다.

## 1번: 임시 vector는 실제 저장소로 이동한다

[buffer proof remember](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKDescriptorSet.h:554), [binding snapshot remember](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4PreparedResource.h:157), [texture proof remember](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4PreparedResource.h:467)는 vector를 persistent entry로 move한다. 따라서 local std::vector를 inline scratch로 바꾼 뒤 목적지 std::vector를 새로 만들면, 단일원소에서 기존 하나의 할당을 없앤 것이 아니다. 목적지 할당이 여전히 필요하고 proof 복사만 늘 수 있다. 기존 move/capacity/negative·exact-hit 작업은 새 성과가 아니다.

[snapshotResources→groupResources](${WORKSPACE}/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm:384)의 복사는 별도 group 보유 목록을 만든 뒤 원 vector를 snapshot entry에 move하기 위한 것이다. 이 복사를 무조건 move로 바꾸면 뒤 snapshot에 moved-from 원소가 남는다. 두 목적지의 storage 공유는 별도 수명·동시성 설계로 범위가 커진다.

현재 검토할 수 있는 가장 좁은 형태는 기존 count/resourceCount 상한을 사용하는 **첫 유효 proof/resource 이후의 exact bounded reserve**다. total>1이고 현재 capacity가 부족할 때만, 기존 eligibility·payload preflight를 보존한 상태에서 다원소 수집의 중간 재할당을 줄이는 안이다. bufferProofs/textureProofs/snapshotResources의 기존16원소 상한부터 좁히는 편이 group 전체를 미리64개 예약하는 것보다 명확하다. partial replay 실패 뒤 clear가 유지하는 capacity도 재사용해야 한다.

첫 유효 proof 뒤에도 나중 proof가 만료되거나 등록이 실패할 수 있다. 이때 기존보다 큰 임시 capacity를 잡는 작은 상한 내 비용이 생길 수 있다. 이를 명시하고 보존되는 결과/수명·순서와 실제 줄어드는 재할당을 검토하면 된다. 그 trade-off만으로 기각하지 않는다. 다만 hit/negative/count0·1에서 새 할당을 만들거나, 완전 성공을 미리 알기 위해 두 번째 전수검사·global scratch·새 persistent cache를 추가하는 안은 이 묶음에 넣지 않는다. group을 처음부터 reserve64하거나 매 binding마다 reserve(size+next)를 강제해 기존 geometric growth를 깨는 것도 별도 반례다.

과거 실제 BAR에서 binder/snapshot/proof 경로는 확인됐으나734500 slow success와1456088 object slots는 vector 길이·할당비용 분포가 아니다. 이 사실을 FPS 사전증명 의무로 만들지 않는다. owner가 실제 bounded proposal과 관련 기존 fixture의 operation/lifetime 결과를 제시하면 소스 단위로 판정할 수 있다.

## 다음 인계

기존 descriptor/prepared-texture/ownership fixture에서 실제 수집 본문을 대상으로 count0·1·2·상한, fast hit/negative, partial replay→fallback, 첫/늦은 invalid proof, 등록 실패, move 후 persistent entry 생존·clear를 확인하면 이 좁은 변경의 핵심을 검증할 수 있다. fixture 안의 할당/capacity 관찰은 가능한 최소 방법이며 제품 collector는 필요 없다. 지금 이 검사들을 실행하거나 새 통과로 기록하지 않았다.

1번 proposal을 기다리며2번은 보류한다. 11a/2837은 이번 gate 범위 밖이고 구현 착수나 승인으로 읽지 않는다. 입력 SHA256·읽은39핀·구체 판정은 independent-gate-review.json에 저장했다.
