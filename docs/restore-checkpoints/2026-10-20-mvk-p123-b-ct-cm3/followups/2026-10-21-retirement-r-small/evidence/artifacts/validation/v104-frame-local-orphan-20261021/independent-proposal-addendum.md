# 11a 제안 추가 독립 검수

**수정 제안과 설계·검증 계획에 남은 actionable finding은 없습니다.** 아직 미적용이며 실행·readiness 판정은 아닙니다. 기존 independent-proposal-review.md/json은 변경하지 않았습니다.

최종 검수 patch는 `6708badf0af62cc4fb6b336cd7bccba81d5e3f93c229b8459bf4b10684d2f0d6`입니다. 두 lane StreamBuffer 제안 SHA는 `2ea17f26c9b6edd0d21d179dfb4d12be034aa0509c1b8ef1b5d56e8e23dde76f`입니다. 원본4파일이 preimage와 같고, 메모리상 exact-context 적용으로4개 proposed SHA를 재확인했습니다.

이전 COPY_WRITE 지원 지적은 해결됐습니다. DSA 미지원 때 core3.1 또는 ARB_copy_buffer가 있는 경우만 fallback하고, 둘 다 없으면 새 GL 호출 없이 최적화를 생략합니다. HEADLESS에서는 새 GL 기능 검사와 orphan 호출 전부를 제외하고 marker만 지웁니다. 기존 DSA capability+nonnull, VAO/EBO·외부 binding 보존, readonly/부분 업로드/같은 프레임 재사용/model 제외 범위도 유지됩니다.

추가 design.json은 두 native lane의 dependent TU 재빌드와 current-mtime 적용을 명시하여 virtual ABI와 이전 mtime 문제를 다룹니다. 부모 앱은 비교 후 root가 정하고, 선택 부모의 MVK를 그대로 보존해 active Small raw를 잘못 가져오지 않도록 명시했습니다. 공식 identity·numeric/sync·NoGS/healthbar·launcher와 CMake 설정 보존도 포함합니다.

validation-plan.json은 실제 stream/Typed 본문을 기존 fixture에서 검증하고, target/VAO별 fakeGL·unsafe 음성 대조·DSA/pointer/fallback/미지원/HEADLESS 분기·old backing generation·readonly/copy/move·모델 데이터 보존을 좁게 확인하도록 되어 있습니다. Chobby에 없는 range API를 추가·검증한 것처럼 주장하지 않습니다. 후속 realGL은 API/component 검증이고 전체 Recoil game 검증과 구분합니다. 무관한 전체 suite나 제품 collector는 요구하지 않습니다.

현재 비교가 끝난 뒤 부모 선택·owner 인계와 실제 구현/관련 검증/앱 포장이 남습니다. 절감량·FPS·메모리 순이익은 아직 미확인입니다. 이 추가 검수에서 제품/fixture/build 변경, 빌드·테스트·GPU·앱/게임·inventory·정리·업로드는 모두0회입니다.
