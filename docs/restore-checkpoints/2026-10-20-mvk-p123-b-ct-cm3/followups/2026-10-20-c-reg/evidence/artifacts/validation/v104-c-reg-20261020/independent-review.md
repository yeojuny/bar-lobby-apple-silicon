# C-REG 독립 적용 검수 — 2026-10-20

**판정: 동결된 C-REG 변경에서 actionable finding 및 차단 결함을 발견하지 않았다.** 이 판정은 제한된 구현·적용·기존 검증 근거의 검수이며 성능 개선, 게임 안정성, 최종 패키지 또는 배포 승인을 뜻하지 않는다. 현재 C-T+C-M3 포함 descriptor 후보 대비 전원 연결·절전모드 Metal3/Metal4 실측 비교 결과는 이 검수에 포함하지 않았다.

검수자는 제품 파일·공유 상태·AGENTS를 변경하지 않았고 테스트·빌드·게임을 새로 실행하지 않았다. 다른 채팅으로 메시지를 보내지 않았다. 작성 파일은 이 디렉터리의 `independent-review.json`과 이 문서 두 개뿐이다.

## 동결 대상과 적용 확인

- `review-pins.json`의 제품 4개와 검증 fixture 2개, 총 6개 파일 SHA-256이 현재 파일과 모두 일치했다. 전체 해시는 동반 JSON의 `reviewedPins`에 기록했다.
- `before/`의 6개 preimage는 `before.json.files`와 모두 일치했다. 이 preimage와 현재 파일로 재구성한 unified diff가 `c-reg.patch` 전체와 바이트 단위로 일치했다.
- `before.json`에서 선택된 6개 변경을 제외한 보존 핀 **70개** 모두 존재하고 일치했다. 실제 launcher HEAD/index와 이전 앱 관련 기록 핀을 포함한다. 이 확인은 보호 앱 전체 새 인벤토리 검사를 수행했다는 뜻은 아니다.
- 비교 기준은 `artifacts/runtime/v104-descriptor-candidate-20261020/BAR.app`다. 직전 raw MVK 해시는 `443cae49eeca6814a7374cf510178416660e07238715e1ceb451f648e92eb60a`, 이번 native 검증이 사용한 raw MVK 해시는 `e60a7d6694d2c4a7fd02239d981342e0b3f86cab1e6e1d94d897fe9ce4ba101c`이며 현재 라이브러리와 후자의 일치를 확인했다.

## 구현 판단

| 경계 | 확인 결과 |
| --- | --- |
| generic 등록 | `addResource`는 Unknown으로 공통 구현에 들어간다. 첫 등록에서 한 번 판별한 결과를 lease까지 전달하며 generic 공개 `lease`는 Unknown fallback을 유지한다. 따라서 generic 등록의 중복 판별도 줄어들지만, 타입 의미나 residency 성공을 가정하지 않는다. |
| typed 호출자 | buffer/texture 등록 함수의 기존 typed 인자, render attachment/resolve texture, visibilityResultBuffer만 새 API로 연결했다. snapshot의 불투명 identity는 기존 live guard와 membership proof를 통과한 뒤 typed sink로 들어간다. 새 무검증 opaque-id cast 경로를 추가하지 않았다. |
| 잠금·실패 순서 | error 초기화, recording mutex, Recording/nil 검사, resident hit, 첫 등록 device 검사의 순서가 유지된다. typed wrapper마다 별도 상태 기계를 복제하지 않았다. |
| 소유권·residency | `retainUnique`, resident identity, device residency lease 획득, dynamic fallback, stable-buffer 조건과 등록 통계는 유지된다. type은 ownership 또는 lease가 있다는 증거로 쓰이지 않는다. |
| heap와 view | resource → heap → parent/parent heap 조회와 64단계 제한은 유지된다. registry 조회의 각 잠금과 shared lease 수명도 동일하다. 미등록 typed texture는 parent 탐색을 생략하지 않는다. |
| drawable | ordinary 판정, acquisition binding/generation, 강한 drawable 보유, unknown/external reverse registry 탐색, generation 포화와 변경 처리 본문은 그대로다. |
| 제출·취소·재사용 | GPU 참조와 operation 참조의 해제·retirement·allocator 경계는 변경하지 않았다. 기존 bulk upload의 `addResident` 직접 호출은 기본 Unknown 경로를 유지한다. |
| 변경 범위 | `bindMetal4Resources`, `replayMetal4Resource`, `prepareMetal4ResourceRegistration` 함수 본문이 직전 preimage와 정확히 일치한다. Metal3 구현, 엔진·Mesa·셰이더·동기화 식별자 변경을 이 패치에서 추가하지 않았다. |

`addBufferResource`/`addTextureResource`는 내부 typed 계약이다. Objective-C protocol 타입이 런타임에 강제 검증된다는 뜻은 아니지만, 이번 변경 호출부의 타입 출처는 위와 같이 확인했다. 향후 외부의 불투명한 객체를 강제 cast하여 이 경로로 보내는 변경은 별도 검수가 필요하다.

## 기존 검증 기록의 범위

| 기록 | 확인된 결과 | 의미와 한계 |
| --- | --- | --- |
| `cpu-registration-3/receipt.json` | 컴파일·실행 exit0, **410 assertions**, ASan/UBSan | 생산 submission 구현과 추출된 등록 함수, generic/typed nil·device·중복 등록·parent lease·취소·recording 구분, drawable generation/mutation 등을 검사. NSObject doubles이며 실제 Metal device/GPU는 사용하지 않음. |
| `common-validation/registration-native/receipt.json` | **6/6**, ASan/UBSan·Metal Validation | 실제 자원으로 generic/typed buffer GPU retirement와 heap/texture view, owner lifetime을 비교. 전체 lifetime suite를 모두 실행한 것은 아님. |
| `common-validation/syntax.json` | **6/6 exit0** | 생산 translation unit 3개 × foundation OFF/ON. 실행 의미 검증과 구분. |
| `common-validation/build.json` | 증분 빌드 exit0, custom diagnostics OFF | 해당 MVK 빌드 완료 근거. 최종 앱 패키지 검수가 아님. |
| `common-validation/native-receipt.json` | 기존 prepared suite **6/6**; common M3/M4 각각 **6 cycles + graphics** | 실제 생산 라이브러리의 제한된 Vulkan 경로. common Metal3의 `native_queue:false`는 M4 native queue 여부이며 GPU를 쓰지 않았다는 뜻으로 해석하지 않는다. BAR 게임/FPS 검증이 아님. |

CPU receipt의 입력 13개와 생성 fixture 해시가 현재 파일에 모두 일치한다. 별도 native prepared fixture의 해시도 receipt와 일치했다. CPU execution 로그와 native registration stderr를 읽었고 전자는 성공 JSON, 후자는 Metal Validation 활성화 로그였다. sanitizer 옵션은 `detect_leaks=0`이므로 누수 부재 검증으로 확대하지 않는다. concurrency mutation hook을 다중 thread race-freedom 증거로 확대하지 않는다.

## R50·R47 fixture 조정 검수

**옛 R50 binder 바이트 비교 삭제는 타당하다.** 삭제한 비교는 과거 R50 소스와 현재 바인더가 같아야 한다고 요구했으나 이후 R71/R4/R5 등 이미 누적된 변경을 반영하지 못한다. 이번 fixture는 간접 바인더를 실행하지 않는다. 이 검수에서는 대신 동결된 직전 후보의 `bindMetal4Resources`가 이번 변경에서 그대로인지 확인했고 일치했다. 따라서 오래된 baseline의 불일치를 C-REG 결함으로 취급하지 않는다.

**R47에서는 기존 NSObject doubles와 그 기반 선언·실제 submission include/require helper만 재사용한다.** 첫 `namespace {` 앞에서 잘라 오래된 private-state retirement test 본문과 main을 끌어오지 않는다. 최초 compile 실패는 삭제된 `primaryPool`, `tailPool`, allocator/retirement 멤버를 그 옛 테스트가 참조한 결과로 기록에 남아 있다. 이 수정은 이번 등록 구현을 mock 대체한 것이 아니며, 옛 R47 retirement 테스트가 현재 구현을 통과했다고 주장해서도 안 된다.

**stage-preparation reset은 CPU fixture에서 미검증이다.** 실제 `MVKMetal4StagePreparation[kMVKShaderStageCount]`를 reset 가능한 `std::array<unsigned, 1>`로 바꾼 shell이다. 추출된 reset 루프를 컴파일·실행할 수는 있지만 실제 stage 수, stage 객체 내부 상태·소유 자원 해제·바인더 invalidation 정확성을 입증하지 않는다. 생산 reset 본문은 이번 패치에서 바뀌지 않았고, 별도 native common 사례는 실제 생산 경로의 제한된 보완 근거일 뿐 reset 전반의 완전한 검증은 아니다.

`cpu-registration`과 `cpu-registration-2`의 실패 기록은 남아 있다. 각각 옛 R47 private-state 테스트 포함과 stage-preparation 타입/단계 상수 누락에 의한 fixture 컴파일 실패다. 최종 성공만으로 이 실패를 없었던 일로 표시하지 않는다.

## Actionable findings와 다음 판단 경계

**Actionable findings: 0.** 변경 목적에 필요한 타입 전달과 기존 소유권 보존을 막는 결함은 발견하지 않았다. 새 테스트나 제품 수정을 요구하는 항목을 만들지 않았다.

정적 판별 제거가 FPS 순이익을 보장하지 않는다. wrapper/분기 비용, 실제 first-registration 빈도 및 실행 변동을 포함한 현재 후보 대비 비교는 별도다. 이번 검수만으로 “무위험”, “전체 CPU 410개가 native/GPU 검증”, “stage reset 검증 완료”, “BAR gameplay/MP/다른 Mac/최종 배포 검증 완료”라고 결론 내리지 않는다.
