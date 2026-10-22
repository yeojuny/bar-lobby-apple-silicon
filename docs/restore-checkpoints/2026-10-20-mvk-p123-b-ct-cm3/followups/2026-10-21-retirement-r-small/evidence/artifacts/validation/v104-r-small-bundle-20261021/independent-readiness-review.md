# R+reserve 첫 묶음 독립 readiness 검수

**판정: 차단 문제 0. 동결된 R과 R+reserve 후보의 승인된 성능 비교를 진행할 수 있습니다.** unit1 한 파일·reserve 6지점만 포함하며 unit2는 보류입니다. 이 판정은 FPS 개선·기준 승격·전체 게임/MP/다른 Mac 검증을 뜻하지 않습니다.

## 빌드 정정과 실제 앱 연결

옛 3.8초 build.json은 R 헤더의 과거 mtime 복원으로 RLookup ABI 객체가 남았을 가능성이 있어 qualification에서 제외했습니다. header-mtime-rebuild의 실제 로그는 34개 OBJCXX 재컴파일과 링크를 보이며 receipt 목록과 일치합니다. 헤더 내용은 정확한 R `d6222a17…afa653`이고 시각만 갱신됐습니다.

정정 build와 보존 qualified raw는 SHA256 `a10d962d14e0cffbc8c284eb6d1e9d9148e36cd1d71a21e648e0479f3b6c0a77`로 일치합니다. GPU recipe는 이 빌드에 링크하고 최종 hash도 확인합니다. package recipe가 옛 candidate-raw 대신 **qualified-raw**를 복사한 것을 확인했으며, 실제 앱 lib는 `abf4fb1bad831b6295d90dd5a9ffa6af8b25308e99c8724153716e480a0275a2`입니다. 독립 Mach-O 읽기에서도 raw와 packaged `__TEXT,__text`가 일치합니다.

앱은 artifacts/runtime/v104-r-small-bundle-candidate-20261021/BAR.app입니다. 표시 버전은 여전히 **1.0.3**, 작업상 이름은 **v1.0.4 candidate / R+unit1**입니다. 1,194 entry의 R/candidate inventory를 대조하여 MoltenVK lib와 서명 관련 두 entry의 정확한 3차이를 재계산했습니다. 211 closure와 strict deep 서명은 owner의 완료된 recipe/receipt를 검수했고 재실행하지 않았습니다. 소스39핀과 확장 fixture2핀·patch·package/completion/inventory hash binding도 일치합니다.

## CPU와 실제 경로 검증

R preimage와 적용 후보의 전체 prepareCurrentPayload를 독립 재추출하고 각각 receipt의 payload SHA 및 생성 C++와 일치함을 확인했습니다. native id 타입 소거와 동일한 비할당 관찰만 추가됐습니다. prepared header의 접근제어 외 차이 없음, 실제 stamp/cache/replay 및 registry methods 일치도 확인했습니다.

원문 결과는 **220 cases / 3,851 checks, ASan+UBSan 통과**, 관련 texture **65 checks**입니다. 개수220도 조건문으로 독립 검산했습니다. 성공16 fixture invocation의 할당14→6은 기록과 맞습니다. late-failure는 할당 횟수가 같아도 표본 bytes168→2,688, capacity1→16으로 커집니다. 최대16이라는 기존 범위 안의 명시적 tradeoff이며 순이익만 있다고 해석하지 않습니다. 이 수치는 GPU 메모리·BAR 전체 할당량·시간·FPS가 아닙니다.

CPU fixture는 실제 vector/cache/move/weak-proof 본문을 사용하지만 layout/native object/retain sink는 모의입니다. proof digest도 count·valid 중심으로 모든 owner identity의 독립 완전동등성 증명은 아닙니다. immutable/inline/일부 variable 조합·snapshot replay Failed를220개가 모두 별도 열거한 것도 아닙니다. source guard 보존과 아래 관련 native 증거를 함께 봅니다. receipt의 추출 입력 목록에 빠진 DescriptorSet.h는 독립 read pin과 실제 생성 본문 일치로 결합했습니다. 재실행을 요구하지 않습니다.

정정 raw의 실제 Vulkan 검증은 **M3/M4 각3 cases 통과**입니다. 반복·새 recording과 descriptor 갱신, 별도 identical-definition layout, fragment texture/sampler readback을 확인하며 Context는 실제 backend를 검사하고 native M4 완료 증가도 검사합니다. 로그는 M3 native=0/M4 native=1과 일치합니다. 별도 전체 native suite를 통과했다고 확대하지 않습니다.

foundation OFF는 변경 TU의 syntax-only 성공이며 OFF GPU 성공이라는 뜻이 아닙니다. 관련 네 TU의 Ninja FLAGS에서 diagnostics compile0, native recipe의 runtime 계측 옵션0을 확인했습니다. Submission source 핀이 같아 allocator32/growth2MiB/available8/idle64MiB 정책은 유지됩니다.

## 보존과 한계

네 기존 앱 보존은 owner 전후 inventory 검사와 receipt로 결합했고, launcher 전후 HEAD/index/status 기록도 동일합니다. 제품 source의 AI/sync/공식 엔진 identity·화면/profile 변경은 없습니다. 초기 CPU compile의 Vulkan 헤더 누락, FLAGS 위치를 잘못 전제한 recipe 중단, 미검증 옛 빌드 기록은 모두 보존되어 있고 최종 성공 증거와 구분했습니다.

추가 제품/fixture/build 편집·컴파일·테스트·GPU·앱/게임 실행·계측·정리·업로드는 이 독립 검수에서 모두 0회입니다. 전체 앱 hash 반복 없이 관련 source/receipt와 개별 qualified lib만 읽었습니다. 다음 비교의 실행·결과 해석·후보 채택은 coordinator가 담당합니다.
