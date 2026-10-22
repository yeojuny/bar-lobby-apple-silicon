# 11a 독립 사전 검수

판정: **일회성 TypedRenderBuffer에 한정한 별도 Invalidate 설계는 진행 가능하나, 외부 패치의 EBO Bind/Unbind는 그대로 이식하면 안 됩니다.** 아직 구현·빌드·실행을 검수한 단계는 아닙니다. 첫 묶음 owner의 완료 후 별도 작업으로 연결합니다.

외부 [46e9a9ce](https://github.com/tomjn/RecoilEngine/commit/46e9a9ce8d80cd0b8228a84e3fdb33ed6f317fa0)의 API 원문 8,574 bytes를 읽어 기존 외부 조사와 SHA256 `286a9b7328da42091517abe90fce520a1c49910977861d5ed588c0d93da93f6f` 일치를 확인했습니다. 이 커밋은 두 파일의 22줄 추가·2줄 삭제입니다. 외부 성능은 현재 BAR의 효과로 환산하지 않았습니다. root의 두 lane 호출자 12핀도 모두 일치합니다.

## 호출자와 데이터 수명

- 비-readonly Typed Swap은 두 stream을 교체한 뒤 CPU 정점·인덱스와 start/upload 위치를 0으로 지웁니다. 여기에서만 명시적 폐기를 추가하면 다음 프레임 재업로드 계약과 맞습니다. 일반 StreamBuffer Swap은 그대로 둡니다.
- readonly는 Swap 첫머리에서 반환하므로 캐시·GPU bytes를 보존해야 합니다. CopyCurrent는 독립 CPU 배열과 나중에 독립 stream/VAO를 만들며, readonly 복사본의 수명은 원본의 frame clear와 별개입니다. 기존 인덱스 bias의 부호·계산을 바꾸지 않습니다.
- GetPendingElemsRange와 DrawElementsRange는 다음 Swap 전까지만 유효합니다. ProjectileDrawer의 실제 재사용도 drawFrame 일치를 확인합니다. 프레임 마지막 폐기는 이 경로와 양립하며, Unmap·개별 draw·일반 Clear마다 폐기하는 방식은 안 됩니다.
- GlobalRendering의 전역 SwapRenderBuffers 뒤에 기존 PutBufferLocks가 옵니다. 이 순서·fence·GPU 완료 조건은 변경 대상이 아닙니다.
- ModelsDataUploader는 별도 IStreamBuffer와 indexed SSBO 바인딩을 사용합니다. sparse 부분 업로드와 idle frame은 기존 bytes에 의존합니다. BufferSubData fallback도 같습니다. 일반 Swap에서 orphan하면 이 경로가 깨집니다.
- 실제 font renderer는 BufferSubData를 명시 사용하고 Typed 기본값도 같습니다. 정적 도달은 확인했으나 현재 BAR의 빈도·staging·pass 비용은 미측정입니다.

## 구현 전에 해결할 지점

**VAO 상태:** 외부 Invalidate는 원래 target으로 Bind/Unbind합니다. target이 ELEMENT_ARRAY_BUFFER라면 현재 VAO A의 인덱스 연결을 변경합니다. 예컨대 A→X 상태에서 별도 Typed EBO Y를 폐기하면 A→Y→0이 됩니다. Mesa `bufferobj.c:706–707`이 현재 VAO의 IndexBufferObj를 직접 반환하고 StreamBuffer.cpp:188–198은 상태를 복원하지 않습니다. 대다수 Typed draw가 VAO0으로 복귀한다는 사실만으로 전역 Swap의 모든 caller에 안전을 보장할 수 없습니다. 기존 제품 결함으로 신고한 것이 아니라 **제안 패치에 필요한 수정**입니다.

권고는 지원되는 named BufferData 우선입니다. 두 lane의 glad.h/c에 core4.5/ARB DSA 변수와 NamedBufferData pointer/loader가 이미 있습니다. **(core4.5 이상 또는 ARB DSA)와 실제 non-null pointer를 모두 확인**해야 합니다. 로컬 core4.5 loader의 버전 guard가 주석 처리되어 pointer만으로 지원을 판정하면 안 됩니다. EXT 이름의 별도 함수와도 혼용하지 않습니다. 기존 원문은 GL4.6 Compatibility Mesa를 입증하지만 named pointer 자체를 기록하지 않아, 향후 관련 context 검증에서 확인해야 합니다.

DSA 미지원 fallback은 COPY_WRITE_BUFFER의 기존 binding을 저장하고 같은 객체를 orphan한 뒤 그 binding을 정확히 복원할 수 있습니다. nonzero foreign binding도 보존합니다. DSA 경로에는 상태 조회를 추가하지 않습니다. fallback 조회의 비용·GL-thread 동기화 가능성은 측정하지 않았으므로 공짜라고 주장하지 않습니다. 범위에 맞는 경우 DSA 미지원에서 최적화만 생략하는 선택지도 가능합니다. 다른 플랫폼에 GL4.5를 무조건 요구하지 않습니다.

**HEADLESS:** 두 gladstub.cpp에는 새 ARB DSA 변수·NamedBufferData 정의/초기화가 없습니다. HEADLESS에서 새 심볼 참조를 제외하거나 좁은 stub 보완이 필요합니다. interactive 심볼 존재만으로 모든 구성의 link를 보장하면 안 됩니다.

**업로드 표식:** fresh/no-upload 및 중복 Invalidate는 무동작이어야 합니다. 기존 업로드 후에만 dirty를 세우고 새 backing을 만드는 Init/Resize 때 이를 초기화하여 업로드 없는 성장 직후 불필요한 orphan을 피합니다. ID·byteSize·usage hint·CPU/client pointer 및 기존 Map/Unmap 규약을 보존합니다. 다른 stream 구현은 no-op Invalidate를 상속합니다.

## 가장 좁은 검증 범위

1. 기존 test-step7-model-shared-upload fixture가 실제 StreamBuffer.h/cpp를 사용하도록 유지하며, fresh/idle·복수 partial upload→한 번 orphan·재업로드·Resize·client pointer/자체 CPU buffer·stream/static usage를 확인합니다. 초기 생성과 orphan 횟수는 구분합니다.
2. 현재 fake BindBuffer는 target을 무시하는 단일 전역 bound라 VAO 손상을 검출하지 못합니다. 관련 범위만 target별 binding·현재 VAO·VAO별 EBO로 확장하고, nonzero foreign VAO와 COPY_WRITE binding을 둔 상태에서 실제 Invalidate 전후를 비교합니다. 가능하면 외부 unsafe body를 음성 대조로 사용합니다.
3. core/ARB 각각 지원+nonnull, 지원 flag 없음+nonnull, 지원 flag 있음+null, 모두 미지원 분기를 확인합니다. 실제 DSA 경로에는 binding 변경·상태 조회가 없어야 합니다. HEADLESS 참조 경계도 확인합니다.
4. actual 또는 정확히 추출한 Typed Swap/Clear/CopyCurrent/DrawElementsRange로 readonly·독립 복사본·같은 프레임 범위 재생·다음 프레임 0부터 재업로드를 확인합니다. stream만 검증한 결과를 Typed 호출자 검증으로 대신하지 않습니다. 기존 model sparse/idle/fallback 경로는 orphan 0회와 bytes 보존을 확인하면 됩니다.
5. orphan CPU 모형은 같은 buffer ID의 backing 세대를 구분해야 합니다. 이미 제출된 read는 옛 backing을 보유하고 새 backing은 poison 상태로 시작하게 합니다. 기존 ID만 비교하는 지연 read 모형은 실제 GL의 storage 교체를 증명하지 않습니다. CPU 모형만으로 GPU 수명 안전을 주장하지 않습니다.
6. owner의 좁은 구현/빌드 후 허가된 실제 Mesa context에서 loaded named pointer와 분기·foreign VAO 상태·indexed/nonindexed draw·같은 프레임 재사용을 확인합니다. 전체 게임/무관한 suite 반복이나 신규 제품 collector를 요구하지 않습니다.

## 경제성과 한계

폐기 가능한 frame-local 저장소임을 드라이버에 알리는 구체적 변경입니다. staging 복사·pass 경계 감소는 현재 포트에서 검증할 가설입니다. orphan은 in-flight draw가 끝날 때까지 옛 backing을 보유하거나 새 저장소를 할당할 수 있어 peak memory 감소·순이익을 보장하지 않습니다. 먼저 좁은 기능/상태/수명 검증 후 승인된 비교 후보로 판단하는 것이 합리적이며 사전 FPS 입증이나 모든 입력의 추가 비용 0을 요구하지 않습니다. 바인딩/readonly/model 수명 변경, 미지원 entrypoint, 기능 오류·과도한 memory churn이면 중단·철회합니다.

원본 부호·AI/sync·공식 identity·기준 R 및 복구 앱 보존이 경계입니다. 이 검수는 제품/fixture/build 변경 0, 컴파일·테스트·GPU·앱/게임·계측·정리·업로드 0회입니다. 이 두 검수 파일만 저장했습니다. 전체 read pins와 input hash 및 분기별 세부 계획은 짝 JSON에 있습니다.
