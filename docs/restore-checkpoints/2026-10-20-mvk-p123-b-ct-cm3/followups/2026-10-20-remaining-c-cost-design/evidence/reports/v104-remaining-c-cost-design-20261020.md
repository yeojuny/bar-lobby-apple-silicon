# v1.0.4 후보 이후 C 비용 확인과 한정 설계 — 2026-10-20

현재 누적 후보로 실제 BAR Metal4·Metal3 경로를 각각 한 번 관찰했다. **새로 상세 설계할 근거가 있는 항목은 Metal4의 기록별 자원 등록에 이미 알려진 타입을 전달하는 변경 한 가지다.** 기록 간 자원 소유권 공유 확대, allocator 상한 확대, render pass 병합, barrier·완료 대기 축소는 이번 근거로 채택하지 않는다.

이것은 구현 후보를 좁힌 설계 결과다. 제품 소스·라이브러리·앱은 변경하지 않았고 새 개선율도 측정하지 않았다. 사용자의 “리스크가 없고 순이익만 있다면 뭐든”이라는 기준에 맞춰, 동작과 자원 수명을 유지하는 중복 계산 제거부터 검토했다. **위험이 낮은 설계와 순이익이 실측으로 확인된 변경을 구분한다.** 아래 후보도 아직 무위험 또는 순이익 확정으로 분류하지 않는다.

## 이미 완료해 신규 후보에서 제외한 부분

| 완료 범위 | 현재 구현과 제외 이유 |
|---|---|
| P1/P2/P3·B·C-T·C-M3 | 현재 실행 앱에 누적 반영. template 불변 정보와 Metal3 compact UBO capture를 다시 신규 과제로 세지 않는다. A는 실제 선택 콘텐츠의 대상 호출이 없어 적용 제외 |
| 기록을 넘는 descriptor CPU snapshot | descriptor·pipeline 소유의 불변 typed 목록, 사용 binding revision, weak membership proof, covered/residual 계획이 이미 존재. R71에서 통합·검증 |
| 같은 기록의 등록 중복 제거 | `registerMetal4Buffer/Texture`의 recording memo와 submission의 resident identity가 이미 성공한 등록을 생략. 새 기록에서는 새 소유권 확보가 필요 |
| 완전히 같은 group stamp·빈 간접 목록 | R5 exact hit와 R4 empty-indirect 경로가 이미 반복 확인을 줄임 |
| allocator epoch 공유 | 여러 ended recording이 allocator를 공유하며 CPU writer는 하나. 마지막 live user 뒤 reset. 현재 32 recordings/2 MiB growth, available 8, idle 64 MiB 정책 |
| 저장소·residency 재사용 | pack의 빈 CPU container 용량, upload slab, argument table, 명시적 lifetime token을 가진 stable buffer cache, device residency lease가 이미 존재. 단순히 “pool을 추가하자”는 제안 제외 |
| 안전한 제출 묶기·패스 지속 | timestamp의 적격 ordered commit 묶기, compute 내부 및 적격 vertex producer의 encoder 지속이 이미 구현됨. 다른 GPU 의존성까지 생략한다는 의미는 아님 |

정점 바인딩 memo는 현재 후보에 들어 있지 않다. 과거 성능 이득을 입증하지 못했고 이번 공유·allocator·pass·동기화 조사에서도 재도입 근거를 얻지 못했다.

완료 근거: [현재 descriptor 후보](v104-descriptor-preparation-20261020.md), [R71](metal4-r71-build-and-comparison-20261006.md), [R68 allocator](metal4-r68-shared-allocator-20261006.md), [R5](r92-group-hit-validity-game-20261013.md), [R4](r92-empty-indirect-group-20261013.md), [timestamp 제출 묶기](r92-timestamp-submit-reduction-20261010.md). 과거 보고서의 앱·raw trace 일부는 이후 정리됐으므로 그 경로가 지금도 실행 가능하다고 가정하지 않았다.

## 실제 관찰 대상과 한계

| 항목 | 이번 관찰 |
|---|---|
| 앱 | `artifacts/runtime/v104-descriptor-candidate-20261020/BAR.app` |
| 포함 변경 | P1/P2/P3+B+C-T+C-M3 |
| 표시 버전 | 1.0.3 유지, 로컬 v1.0.4 후보 명칭 |
| 패키지 MVK SHA256 | `7ac71989ca27a99a2f9adf219ac0dcb12f16804cd35733bf7fd2c078635c5c4a` |
| 활성 빌드 MVK SHA256 | `443cae49eeca6814a7374cf510178416660e07238715e1ceb451f648e92eb60a` |
| 순서 | 같은 현재 후보 Metal4 → Metal3, 각 1회 |
| 조건 | AC·Low Power ON·thermal 0, Ultra·AA Off·Spring·VSync Off, 1432×902, hidden window, sound off |
| 장면·기록 | 기존 Seths Ravine Remake 1.3.1, 고정 frame240에서 공식 900-frame benchmark 시작. 기존 controller·scene 재사용 |
| 비용 관찰 | 소유한 native game PID에 macOS `sample`, 요청 10초/간격 1 ms. runtime 세부 계측 OFF |
| backend 확인 | Metal4 native queue 활성·완료 확인. Metal3는 USE_METAL4=0과 실제 legacy `execute → encode(id<MTLCommandBuffer>)` 호출 stack 확인 |
| 화면 상태 | guard 관찰 111개 모두 console unlocked. 잠금 허용 정책을 사용했지만 이번 관찰은 잠긴 상태가 아니었음 |

현재 빌드의 `MVK_ENABLE_CUSTOM_DIAGNOSTICS=0` 때문에 환경 변수만 켜서 기존 세부 카운터를 얻을 수 없다. 앱 재빌드 없이 OS sampler를 사용했다. 실제 매핑된 라이브러리 경로와 SHA를 확인했으며 같은 UUID prefix만으로 앱을 식별하지 않았다.

샘플러의 10초 수집과 이후 symbol 처리 시간이 구분된다. 프로세스 전체 소요는 M4 43.150초/M3 12.047초였다. M4 sampler의 종료 receipt는 benchmark 종료 이후이므로 그 receipt의 frame1481을 “10초 샘플 끝 frame”으로 쓰지 않는다. 정확한 마지막 sample의 simulation frame은 기록하지 않았다. 원본 sampler stderr에는 10초 수집 완료와 이후 symbol 처리 단계가 남아 있다.

**이 실행의 FPS는 비교 표본에서 제외한다.** 샘플링과 symbol 처리가 시스템 부하를 바꾸며, 두 backend의 처리 시간도 달랐다. 원래 benchmark 결과는 원본 receipt에 보존한다. 새 표본을 앞선 세 차례 성능 비교에 합치거나 이를 근거로 후보가 빨라졌다/느려졌다고 판단하지 않는다.

## 관측된 남은 작업

아래 숫자는 `sample` call tree에서 해당 경로가 stack에 있던 관측 수다. 같은 범주 안에서는 중첩 호출을 한 번만 세었다. **호출 횟수·밀리초·CPU 사용률·GPU 시간·FPS 기여율이 아니다.** 범주끼리는 겹치므로 더하지 않는다. 한 번씩의 짧은 관찰이며 inlining, deduplicated symbol, scheduler·대기 상태가 섞인다.

| 경로 | Metal4 | Metal3 | 해석 |
|---|---:|---:|---|
| Zink 제출 worker 전체 관측 | 1,801 | 1,829 | 해당 thread의 분모 |
| `vkQueueSubmit` 아래 | 331 | 168 | 현재 실제 BAR 제출 경로 확인 |
| MVK command replay | 293 | 162 | 기록된 명령 재생 비용이 실제 존재 |
| M4 draw 준비 | 88 | 해당 없음 | descriptor·binding 준비 등 포함 |
| M4 `addResource` | 46 | 해당 없음 | 새 기록의 등록 및 ownership 경로 |
| 그 아래 Objective-C protocol 판별 | **28** | 해당 없음 | 실제 반복되는 타입 판별을 확인한 직접 근거 |
| 그 아래 device residency `lease` | 15 | 해당 없음 | 위 28과 일부 겹침. 조회·lock·parent traversal 전체를 생략할 근거는 아님 |
| native render encoder 생성 | 58 | 43 | pass 준비 비용 존재. 불필요한 pass 수나 병합 가능성은 미측정 |
| 명시적으로 식별된 allocator 생성/reset 함수 | 0 | 해당 없음 | 관측되지 않았다는 뜻. 비용 0 또는 최적이라는 결론 아님 |
| Zink 제출 worker의 condition wait | 1,455 | 1,653 | queue 작업을 기다리는 경로. 제거 가능한 Vulkan/GPU 완료 대기로 해석하지 않음 |

M4 `addResource` 아래의 `__psynch_mutexwait`는 관측되지 않았다. 이를 근거로 lock 경합이 지배적이라거나 lock을 없애야 한다고 주장하지 않는다. 기존 lock 획득 자체의 CPU 비용이 0이라는 뜻도 아니다.

[분석 결과와 정규식 정의](../artifacts/validation/v104-remaining-c-cost-design-20261020/sample-analysis.json), [M4 원본](../artifacts/validation/v104-remaining-c-cost-design-20261020/1-candidate-metal4/sessions/lobby-no-native-hook-1792548401835/cpu-sample.txt), [M3 원본](../artifacts/validation/v104-remaining-c-cost-design-20261020/2-candidate-metal3/sessions/lobby-no-native-hook-1792548532959/cpu-sample.txt).

## 상세 설계: C-REG — 기록별 등록에 기존 타입 정보 전달

### 원인과 줄일 작업

현재 [typed binding sink와 snapshot replay](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm:65)는 Buffer/Texture를 이미 구분한다. snapshot도 `Resource::kind`를 보유하고, replay 시 현재 live proof를 확인한 뒤 해당 typed sink로 들어간다.

하지만 [registerMetal4Buffer/Texture](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm:615)에서 공통 `addResource(id<MTLResource>)`로 들어가며 타입 정보가 사라진다. [addResource](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.mm:2162)는 이 기록에 아직 resident가 아닌 자원의 `conformsToProtocol(MTLTexture)`를 실행한다. [device residency lease](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.mm:467)도 resource/heap 조회가 모두 실패하면 같은 타입을 다시 묻는다.

이미 등록한 자원의 빠른 반환은 그대로 있다. 따라서 새 memo로 매 draw 전체를 줄인다는 설계가 아니다. **새 기록의 필수 retention·residency 등록은 수행하면서, 호출자가 이미 아는 타입의 재해석만 없앤다.** snapshot의 기존 typed 정보가 기록 경계 뒤의 등록까지 전달되는 셈이다.

### API와 자료 흐름

다음은 제안 인터페이스이며 현재 구현된 코드는 아니다.

```cpp
enum class MVKMetal4ResourceKind : uint8_t {
    Unknown, NonTexture, Texture
};

// 기존 generic 진입점 유지
bool addResource(id<MTLResource> resource, NSError** error);

// MVK 내부의 타입이 증명된 호출자만 사용
bool addBufferResource(id<MTLBuffer> buffer, NSError** error);
bool addTextureResource(id<MTLTexture> texture, NSError** error);

// 위 세 진입점이 공유하는 private 구현
bool addResourceWithKind(id<MTLResource> resource,
                        MVKMetal4ResourceKind kind, NSError** error);
```

`NonTexture`는 generic 경로의 기존 “MTLTexture가 아님” 의미를 그대로 표현한다. 모든 MTLResource가 Buffer/Texture 두 종류뿐이라고 가정하지 않는다. 새 전역 map, 객체별 associated metadata, payload 공유, cache 크기 증가는 필요 없다. kind는 호출 인자로 전달하고 기존 `ObjectIdentity::texture`에 최종 결과를 남긴다.

공통 구현 순서는 다음과 같다.

1. 기존처럼 error 초기화 → submission mutex → Recording phase/nil 검사.
2. 현재 recording의 resident identity가 있으면 기존 빠른 반환과 drawable generation 검사를 그대로 수행. 이 hit에서 새 타입 검사를 추가하지 않는다.
3. 아직 resident가 아니면 기존 device 일치 검사를 수행. `Unknown`일 때만 현재 protocol 검사로 Texture/NonTexture를 결정한다. typed 진입점은 해당 값을 이미 전달한다.
4. 기존 `addResident`에 결정된 kind를 함께 전달한다. `stableBufferCandidate = !isTexture` 조건과 현재 retain/residency 등록 순서를 유지한다.
5. `lease`는 resource/heap의 현재 registry 조회를 그대로 수행한다. 두 조회가 실패했을 때만 kind로 texture parent traversal 여부를 결정한다. Unknown인 별도 호출자는 기존 protocol fallback을 사용한다.
6. Texture는 기존 `textureOwnership`, ordinary 판정, exact drawable acquisition, unknown/external reverse registry 발견과 operation retention을 모두 그대로 수행한다.

`MVKMetal4DeviceResidency::lease(resource)`라는 기존 generic 인터페이스도 유지한다. 내부 kind 전달용 helper만 추가하고 접근은 submission state 등 필요한 내부 호출자로 제한한다. 다른 `addResident` 직접 호출은 첫 변경에서 Unknown fallback을 유지할 수 있다. 측정된 typed 등록 경로와 무관한 bulk primitive upload의 입력 검사까지 삭제하지 않는다.

### 처음 적용할 호출자

| 호출자 | 타입 근거 | 변경 |
|---|---|---|
| `registerMetal4Buffer` | 실제 `id<MTLBuffer>` 인자, buffer live proof 또는 이미 보유한 native buffer | Buffer 진입점으로 연결 |
| `registerMetal4Texture` | 실제 `id<MTLTexture>` 인자, texture live proof/기존 drawable 경로 | Texture 진입점으로 연결 |
| `beginMetal4RenderPass` attachment·resolve | Metal descriptor의 texture 속성 | Texture 진입점으로 연결 |
| 같은 함수의 visibilityResultBuffer | Metal descriptor의 buffer 속성 | Buffer 진입점으로 연결 |

이 네 연결과 공통 구현을 하나의 한정 변경으로 검토한다. 나머지 generic call site는 유지한다. 런타임 class 포인터나 native 주소를 전역 저장하여 다음 기록의 타입·소유권을 추측하지 않는다.

snapshot replay는 기존 membership proof와 live guard를 통과한 후 typed 호출을 사용한다. 불투명한 외부 `id`를 단순 cast해 typed 진입점에 넘기는 새 호출자는 허용하지 않는다. 검증 빌드에서는 typed 내부 계약을 assertion으로 확인할 수 있지만 제품 hot path에 다시 protocol 검사를 넣어 변경 목적을 상쇄하지 않는다.

### 수명·동시성·실패 계약

| 경계 | 유지할 조건 |
|---|---|
| 기록 A → 기록 B | B는 새 identity와 새 retention/lease를 획득. A의 성공을 B의 resident 증거로 사용하지 않음 |
| device registry 변경 | 현재 registry를 lock 아래 조회. type을 안다고 registry entry나 lease가 아직 살아 있다고 가정하지 않음 |
| heap·texture view | resource → heap → 실제 parent/parent heap 탐색 순서와 현재 깊이 제한 유지 |
| ordinary·drawable·import | Texture라는 사실은 ordinary/owned라는 증거가 아님. 현재 acquisition generation과 strong drawable snapshot 유지 |
| GPU 완료 전 | command buffer가 자원을 대신 retain한다고 가정하지 않음. submission resource/lease는 기존 retirement 시점까지 유지 |
| cancellation·오류 | 기존 open/ended cancellation, device loss, cleanup/handler 순서와 반환값 유지. typed 진입점마다 별도 상태 기계 복제 금지 |
| 주소 재사용 | recording의 strong retain 및 snapshot weak proof 유지. 이전 주소의 타입을 새 객체에 재사용하는 캐시 없음 |
| lock | 현재 submission → residency/registry 순서와 lock 범위 유지. lock-free화나 CPU writer 수 확대 없음 |
| generic·비-M4 | generic entry는 기존 동작 보존. Metal3는 이 M4 등록 구현을 사용하지 않으므로 동등한 성능 개선 대상으로 세지 않음 |

Metal4 command buffer가 GPU 자원에 strong reference를 자동 생성하지 않는다는 계약이 fresh recording의 소유권을 계속 확보해야 하는 이유다. 타입 전달은 이 의무를 없애지 않는다. [Apple Metal4 core API](https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api)

### 예상 변경 파일과 검증

제품 변경 예상은 `MVKMetal4Submission.h/.mm`, `MVKCommandEncoderState.mm`, `MVKCommandBuffer.mm` 네 파일이다. 같은 공통 구현을 사용해 generic·typed 경로의 validation 및 texture ownership 처리가 갈라지지 않게 한다. 엔진·Mesa·shader·numeric/sync identity 변경은 필요하지 않다.

기존 native fixture를 확장해 아래 결과를 비교한다. 새 benchmark framework나 전체 테스트 재실행을 전제로 하지 않는다.

| 검사 | 실제로 확인할 결과 |
|---|---|
| 기존 foundation의 nil/phase·retain-first 사례 | generic/typed 모두 nil·late registration 거부, retain-only 뒤 resident 등록, 중복 등록 뒤 retained/resident 수 동일 |
| 기존 lifetime의 device residency 사례 | 등록한 buffer와 미등록 fallback buffer의 lease 수·GPU 복사 결과 동일. 마지막 allocation owner가 사라져도 in-flight lease 생존 |
| 기존 heap/view 사례 | heap buffer와 texture view가 실제 base allocation lease를 확보. caller 소유권 해제 뒤 GPU 결과·최종 해제 동일 |
| 기존 drawable ownership 사례 | ordinary, 직접 drawable, view, unknown/external fallback, generation 교체가 기존과 같은 drawable을 보유 |
| 기록 재사용·취소 | 다음 recording에서 이전 identity가 비어 있고 새 소유권을 확보. ended cancellation·완료 뒤 해제 정확히 한 번 |
| 실제 변경 호출 경로 | 기존 prepared Vulkan 사례에서 descriptor snapshot replay/직접 texture·buffer/attachment 경로의 결과 비교. helper/query 뒤에도 소유권 정상 |
| 빌드 | 해당 translation unit 및 foundation ON/OFF, 활성 MVK 증분 빌드. 기존 라이브러리·후보와 분리 보관 |

필요한 foundation·lifetime 사례는 이미 존재한다. 특히 [deviceResidencyBlockedRetirement/HeapAndView](/Users/yeojun/Desktop/BAR-AppleSilicon-App/tools/tests/metal4-r49-lifetime-native.mm:1639)는 owner 재등록·in-flight lease·heap/view 반환을 실제 native 자원으로 검사하므로 이를 generic/typed 연결에 맞춰 보완하는 편이 적절하다. 단순히 enum 분기를 흉내 내는 테스트로 통과를 주장하지 않는다. 이 문서 작성 중에는 위 제품 검사를 새로 실행하지 않았다.

### 순이익 판정과 중단 조건

정적으로 줄이는 것은 타입을 아는 최초 등록의 protocol 판별, 그리고 residency miss 뒤의 재판별이다. registry lookup·retain·GPU residency·pass 생성 전체가 사라지는 것이 아니다. 28 stack 관측을 그대로 절약 시간이나 FPS 퍼센트로 환산하지 않는다.

구현 후 현재 후보와 변경 후보의 같은 입력·같은 backend·진단 OFF 비교를 기존 절차로 수행해야 한다. 순서를 뒤집은 반복에서 방향이 유지되는지, 평균뿐 아니라 p95/p99와 메모리·오류 결과도 함께 본다. sampling은 경로 제거 확인용으로 별도 실행하고 FPS 비교와 섞지 않는다. Metal3는 변경 범위의 음성 대조군이지만 그 변동으로 M4 수치를 임의 보정하지 않는다.

컴파일러가 wrapper를 충분히 합치지 않아 호출/분기 비용이 늘거나, typed 경로의 실제 빈도가 작으면 순이익이 없을 수 있다. 효과가 변동 안에 남으면 “중복 계산 제거 구현은 확인, 게임 순이익 미확정”으로 남긴다. 소유권 예외, 추가 cache/lock, registry 계약 변경이 필요해지면 이 설계 범위에서 중단하고 다시 검토한다. 사용자의 순이익 조건을 충족했다고 자동 승격하지 않는다.

## 채택하지 않은 C 변경과 재개에 필요한 근거

| 영역 | 이번 판단 | 다음에 필요한 구체적 증거 |
|---|---|---|
| 기록 간 payload·lease 공유 확대 | 현재 snapshot·stable storage 공유를 넘는 비용 근거 부족. freshness/ownership 생략은 불가 | 현재 BAR에서 miss 사유별 빈도·준비 CPU 비용, 현재 기록의 필수 retention과 중복 해석 비용 분리 |
| allocator epoch/idle 상한 확대 | 생성/reset pressure를 이번 stack에서 특정하지 못함. 32/2 MiB를 임의 상향하지 않음 | 실제 create/reuse/reset/정책별 seal 수, live peak·allocatedSize·idle 회수량과 CPU 비용. 기존 pool stats의 단위/수집 시점 명시 |
| render pass 병합·중간 resolve 제거 | encoder 생성 비용은 보이나 어떤 경계가 중복인지, 상위 Zink 종료인지 알 수 없음 | 현재 장면의 pass 종료 이유, attachment/subresource·sample 수, load/store/resolve·query·alias·producer/consumer별 분류와 해당 GPU 시간 |
| barrier·완료 대기 축소 | worker condition wait는 제거 가능한 GPU wait 증거가 아님. query/fence wait도 이번 표본에서 특정하지 못함 | 정확한 wait 대상·의존 관계·발생 stack과 실제 blocked/critical-path 시간. host query 가용성·세대·실패 처리 검증 |

기존 세부 통계는 현재 후보에서 compile-out되어 있다. 후속 측정이 필요해지면 기존 선택적 통계를 쓰는 별도 진단 빌드를 원본 후보와 분리하고, 수집 비용을 먼저 확인해야 한다. 새 대규모 계측 시스템을 만들거나 관찰되지 않은 비용을 추정 수치로 채우지 않는다. 이번에는 추가 빌드·실행을 예약하지 않았다.

allocator는 그 allocator의 메모리를 쓰는 모든 command buffer가 완료된 뒤에만 reset할 수 있다. 이 경계를 앞당기는 안은 제외한다. [Apple reset 계약](https://developer.apple.com/documentation/metal/mtl4commandallocator/reset())

Apple silicon에서 fragment/tile 출력의 일반적인 다른 fragment/tile 소비를 intrapass barrier 하나로 해결할 수는 없다. 필요한 경우 새 pass와 동기화가 요구된다. 같은 pixel/tile의 제한된 경우와 구분해야 하며, 실제 resource 의존성 분류 없이 [현재 setMetal4Barrier](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm:821)의 image/fragment 분기를 풀지 않는다. [Apple 패스 내부 동기화](https://developer.apple.com/documentation/metal/synchronizing-stages-within-a-pass)

현재 AA Off·EGL sample 0은 창 조건이며 모든 offscreen attachment가 single-sample이라는 증명이 아니다. 기존 [R87의 resolve 설계 제약](r87-renderpass-design-20261008.md)도 유지한다. timestamp grouping의 과거 완료를 “남은 모든 제출 경계가 불필요”라는 결론으로 확대하지 않는다.

## 별도 발견: 화면 geometry 조회

주요 C 경로 바깥에서 `MacSDL3EGL::QueryDisplayGeometry`가 main thread 관측의 M4 938/1,801, M3 529/1,829에 나타났다. 그 하위 WindowServer display-state 조회가 각각 850/470에 관측됐다. `LoadDefaultFramebufferViewport`/scissor → SDL/Cocoa display 조회 → IPC 경로가 실제 stack과 현재 소스에 함께 존재한다.

[기본 framebuffer viewport](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run91-recoil-src-694e9df7/rts/Rendering/GlobalRendering.cpp:2312)는 배율을 얻으려고 [전체 display geometry](/Users/yeojun/Desktop/BAR-AppleSilicon-App/build/run91-recoil-src-694e9df7/rts/System/Platform/Mac/MacSDL3EGLBridge.mm:412)를 조회한다. 이는 추가 조사 가치가 있는 구체적 발견이다. 다만 이번은 숨김 창·짧은 샘플 조건이며 정상 표시 게임 전체의 병목 비중이나 절약 가능 시간을 확정하지 않는다.

이 경로는 Retina·화면 이동·크기 변경·fullscreen·safe-area 및 과거 iMac 수정과 연결된다. 이번 C 설계에 섞어 수정하거나 무조건 영구 캐시하지 않았다. 별도 범위에서 정확한 변경 이벤트와 필요한 geometry 필드만 확인하는 것이 우선이다.

## 보존과 종료

두 관찰은 benchmark 완료·정상 게임 종료·Lobby 복귀·소유 프로세스 정리·보호 입력 확인을 통과했다. private shader/browser cache 12개 root, 667 leaves, 논리적 19,243,820 bytes를 제거하고 raw sample·로그·JSON·Markdown은 보존했다. 이는 디스크 물리 회수량 주장이 아니다. 화면 idle 설정 900→0→900 복원, awake assertion 해제, Low Power 유지가 확인됐다.

현재/이전 후보의 전체 앱 인벤토리는 실행 중 기존 검증으로 보존됐고, 원래 launcher HEAD/index 및 기록된 source/build 핀을 완료 receipt에서 다시 대조한다. 기존 성능 비교 결과는 변경하지 않는다. 이번에 작성한 것은 관찰 자료, offline 분석, 설계 문서뿐이다. 제품 구현·새 빌드·설치·공식 Release/Homebrew 변경은 없다.

[실행 결과](../artifacts/validation/v104-remaining-c-cost-design-20261020/outcome.json) · [최종 설계·보존 receipt](../artifacts/validation/v104-remaining-c-cost-design-20261020/design-receipt.json) · [공식 문서 원문과 hash](../artifacts/validation/v104-remaining-c-cost-design-20261020/official/sources.json).
