# 11a 미적용 제안 독립 검수

**핵심 수명·VAO 요구는 반영됐습니다. 현재 Mac 경로의 소스상 차단 문제는 없으며, 공통 fallback의 COPY_WRITE 지원 guard 한 가지를 보완할 것을 권고합니다.** 제품 적용·검증 통과를 뜻하는 판정은 아닙니다.

검수한 patch SHA는 `e6a49a2111455e1e06fedb735c26ccb94260338ea9d0fcf10607f2e6c51a100f`입니다. 두 lane의 원본4파일이 preimage 핀과 같고, diff를 메모리에서 exact context로 적용한 결과도 각 proposed SHA와 일치합니다. 실제 파일에는 적용하지 않았습니다.

- DSA는 core4.5/ARB capability와 non-null named pointer를 함께 확인합니다. HEADLESS에서는 이 새 심볼 참조가 제외됩니다.
- DSA 호출은 바인딩을 변경하지 않습니다. fallback은 COPY_WRITE에만 bind하고 기존 binding을 복원하므로 현재 VAO와 EBO 연결을 건드리지 않습니다. 원래 제안의 EBO Bind/Unbind 위험이 제거됐습니다.
- 업로드 표식은 fresh/Init/Resize에서 false, 실제 nonzero upload 뒤 true, orphan 후 false입니다. 복수 partial upload는 한 번의 프레임 종료 orphan으로 합쳐집니다.
- 일반 StreamBuffer Swap은 그대로이고 다른 구현은 no-op Invalidate를 상속합니다. 모델 uploader의 부분·idle 데이터 보존 경로에 새 호출이 없습니다.
- readonly는 함수 첫머리에서 반환합니다. CopyCurrent, 기존 signed index bias, 같은 프레임 DrawElementsRange/particle reuse는 변경하지 않습니다. Map/Unmap/Clear/draw에서 폐기하지 않고 기존 Typed Swap과 frame Clear 사이에만 폐기합니다.

권고 사항은 **COPY_WRITE 기능 확인**입니다. 엔진의 context 기본/최소는3.0이고 VBO.cpp도 ARB_copy_buffer를 별도 검사합니다. DSA 없는 GL3.0 context가 copy-buffer extension도 없을 수 있는데 제안 fallback은 새 target/query를 무조건 사용합니다. 현재 BAR GL4.6에서 관측된 오류가 아니라 공통 소스의 호환 경계입니다. interactive fallback을 core3.1 또는 ARB_copy_buffer 지원 때만 쓰고, 둘 다 없으면 이 선택적 orphan 최적화만 생략하는 것이 좁습니다. HEADLESS의 기존 stub 경로는 별도 유지할 수 있습니다. 다른 플랫폼의 context 최소 요구를 암묵적으로 높이지 않습니다.

검수 시점에 design.json은 아직 없었습니다. 향후 검증은 기존 실제 stream/uploader fixture의 좁은 확장으로 충분합니다. target별 binding·현재 VAO·VAO별 EBO를 구분해 foreign VAO와 nonzero COPY_WRITE binding을 보존하는지 확인해야 합니다. 예전 단일 bound fake GL로는 이 주장을 검증할 수 없습니다. core/ARB DSA와 pointer-null/unsupported 조합, COPY_WRITE fallback 및 미지원 생략, HEADLESS, fresh/partial/repeat/Resize, readonly/복사본/같은 프레임 range 재사용, 모델 orphan0을 나누어 확인합니다. 실제 body 또는 정확한 추출을 사용하고 제품 collector를 추가할 필요는 없습니다.

DSA의 상태 조회 생략은 설계상 확인됐지만 실제 loaded pointer는 나중의 관련 native context 검증 대상입니다. fallback 조회 비용·저장소 churn·in-flight backing 보존 때문에 순이익이나 메모리 감소를 보장하지 않습니다. 현재 BAR의 pass/staging/FPS 효과도 미측정입니다.

R/Small 비교 중에는 구현·빌드·테스트·GPU·앱/게임·큰 inventory·정리·profile/pointer 변경을 하지 않았습니다. 이 두 독립 제안 검수 파일만 저장했습니다.
