# R 첫 묶음: unit1 독립 소스 검수

**수정이 필요한 소스 결함은 발견하지 못했다.** unit1의 좁은 reserve 변경은 관련 검증으로 진행할 수 있다. unit2.patch는0바이트로 보류 상태다. 빌드·테스트·패키지 통과 판정은 아직 아니다.

최초에는 실제 R preimage `9b28b9a30f6e0d8a975b732dcaf8a49c8e14b32f9ba3157e4f9dce03b14276b9`를 읽고6개 hunk를 메모리에서 exact context로 적용하여 제안 hash `b1013a4a907210de7f527f550758824d1dfcf5d79b05266a984aa2a1e97e62e3`를 재구성했다. helper와6개 호출을 제외한 전체 token은 R과 같고 std::move14곳도 유지된다. 보고서 작성 중 owner가 적용했고 application.json 및 현재 실제 파일이 같은 제안 hash임을 확인했다. source-proposal.json의 not-applied 상태는 제안 당시 기록이다. reviewer는 제품/fixture/source/build/앱/pointer/공유상태를 쓰거나 컴파일·테스트·GPU·게임·정리를 실행하지 않았다.

| 적용 line | vector / 경로 | reserve 이전의 수용 조건 |16 상한 |
| ---: | --- | --- | --- |
| 294 | textureProofs / snapshot replay callback | existing replayMetal4Resource returned Hit, allTexturesProven | textureCacheEligible ensures resourceCount<=16 |
| 299 | bufferProofs / snapshot replay callback | Hit, allBuffersProven, resource.kind==Buffer | allBuffersProven ensures count<=16 |
| 329 | snapshotResources / captureSnapshot | snapshotEligible, nonnull value, proof.valid | snapshotEligible ensures resourceCount<=16 |
| 360 | textureProofs / slow texture | allTexturesProven and proof.valid after original registration | textureCacheEligible ensures resourceCount<=16 |
| 376 | bufferProofs / slow buffer | allBuffersProven and proof.valid after original registration | allBuffersProven ensures count<=16 |
| 388 | textureProofs / slow sampler | allTexturesProven and proof.valid after original registration | textureCacheEligible ensures resourceCount<=16 |

helper는 expectedCount>1, values.empty(), capacity<expectedCount일 때만 reserve한다. 첫 삽입 전 한 번만 적용하고 partial snapshot replay 실패 뒤 clear가 남기는 충분한 capacity는 재사용한다. lambda 자체에는16 상한 검사가 없지만 실제6개 caller의 기존 allBuffersProven/allTexturesProven/snapshotEligible이 상한을 보장한다. helper에17을 직접 입력하는 검사만으로 binder의 admission을 검증했다고 해서는 안 된다.

snapshot callback의 Hit는 기존 replayMetal4Resource가 live identity/proof 검증과 현재 recording retain을 성공한 뒤다. slow texture/buffer/sampler에서는 기존 proof.valid 뒤, captureSnapshot에서는 snapshotEligible/value/proof 확인 뒤에만 reserve한다. 기존 plain std::move, snapshot→group 복사, admission·full/partial·실패 결과와 resource/callback 순서는 유지된다. 전역 scratch, 새 cache, native ownership 공유, lock 또는 제품 계측을 추가하지 않는다.

빠른 group/recording-buffer/texture cache Hit는 reserve 이전에 return한다. binding snapshot replay의 Hit는 다른 경로이며 원래 proof vector를 재수집해 persistent cache로 옮겼으므로 이 수집의 growth는 변경 대상이다. texture negative memo는 textureProofs만 막고 독립적으로 적격인 positive snapshot capture까지 막지 않는다. “negative가 있었으니 이 binding의 모든 vector는 비어야 한다”는 기대는 기존 의미와 다르다.

vector cardinality와 descriptor count도 구분해야 한다. expectedCount0/1은 reserve하지 않지만 descriptor count1의 texture+sampler는 실제 두 원소이므로 reserve2가 맞다. 첫 invalid proof/value 또는 Failed retain에서는 새 reserve가 없다. 나중 실패라면 작은 부분 capacity 대신 기존 상한 내 전체 기대 capacity를 임시로 보유할 수 있다. 이 trade-off는 허용하며 그 사실만으로 기각하지 않는다. 최초 allocation 크기/OOM 압력과 시점까지 모든 입력에서 같다고 주장하지는 않는다. snapshot mutex 안의 callback은 원래도 할당했으며 lock topology는 바뀌지 않지만 hold time은 미측정이다.

성공 다원소 수집의 반복 growth를 줄일 수 있는 좁은 설계다. 실제 operation 수치·빌드·BAR FPS/메모리 이익은 아직 미확정이다. 구현 전 FPS 증명이나 모든 입력 추가 비용0을 요구하지 않는다.

## 최소 관련 검증 제안

기존 descriptor/prepared-texture/ownership fixture 안에서 실제 helper와6개 guarded 본문을 추출하거나 binder 수집 본문을 재사용하여 exact R과 제안을 비교한다. 새 shadow loop만으로 제품 전체를 검증했다고 하지 않는다.

- snapshot replay callback의 두 proof branch, slow texture/buffer/sampler의 세 branch, captureSnapshot을 모두 포함한다.
- cardinality0/1/2/3/16·ineligible17, immutable/inline, fast hit, texture negative와 독립 positive snapshot을 구분한다.
- first-invalid/late-invalid, replay Hit/Miss/Failed, partial replay→clear→fallback에서 충분한 capacity의 재사용을 확인한다.
- fixture 한정 allocator/capacity 관찰로 실제 줄어든 allocation/growth와 late-failure의 추가 capacity를 함께 기록한다. setup·map-node 할당과 vector storage는 분리한다.
- 기존 실제 remember의 move 후 local vector가 사라져도 같은 resource/weak proof가 재생되는지 확인한다. 결과·순서·retention은 원 R과 같아야 한다.

owner 적용핀은 관측했으므로 관련 CPU와 변경 TU/foundation guard, 필요한 기존 native descriptor/ownership 선택 검증 증거를 다음 인계에서 확인하면 된다. 새 collector나 전체 FPS suite는 이 소스 검수의 선행조건이 아니다. 11a/2837은 이번 범위 밖이다. 입력핀·각 호출 조건·검증 공백은 independent-source-review.json에 저장했다.
