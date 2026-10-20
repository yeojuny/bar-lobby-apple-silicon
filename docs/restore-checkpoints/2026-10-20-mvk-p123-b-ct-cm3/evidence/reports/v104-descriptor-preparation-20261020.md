# v1.0.4 descriptor 준비·복사 — 2026-10-20

C-T와 C-M3를 함께 구현하고 관련 검증 및 Astra + High 변경분 검수를 마쳤다. 현재 출발점은 P1/P2/P3+B 누적 후보이며 A는 실제 사용 경로 부재로 제외 상태다. 정점 바인딩 캐시는 이번 변경에 추가하지 않고 현재 조합에서의 재실험 가능성을 따로 분석했다. FPS 이득은 아직 미측정이다.

## 구현

| 항목 | 변경과 보존 |
|---|---|
| C-T | template 생성자의 기존 entry 순회에서 singleton UBO 형식·정적 offset overflow·최대 정확한 읽기 끝 위치를 계산한다. 호출 때는 현재 layout의 타입·목적 배열 범위와 현재 pData 주소를 계속 검사하고 descriptor 값은 현재 입력에서 복사한다. |
| C-M3 | 기존 Metal4의 command-local compact singleton UBO capture를 Metal3에도 적용한다. compact 크기가 안전하게 계산되고 generic 크기보다 엄격히 작을 때만 선택한다. 작거나 같은 입력은 generic을 유지하며 Metal4의 기존 선택은 그대로다. |

제품 파일은 MVKDescriptorSet.h/.mm와 MVKCmdPipeline.h/.mm 네 개다. 새 map·전역 cache·잠금·recording 간 공유·GPU barrier·제출 수명을 추가하거나 바꾸지 않는다. 불변 정보만 template 객체에 남기며 생성 당시 layout이나 pData 포인터를 보관하지 않는다. 실제 전달된 layout, 입력 주소 범위, binding/배열 범위, fallback/오류 순서, 명령 소유 payload와 pool/layout 보유 관계를 유지한다. array/spill·이미지 혼합·다른 descriptor 형식은 기존 generic 경로다. generic 크기의 기존 stride 동작 전체를 고친 것은 아니다.

## C-M3가 필요한 근거와 비용

현재 Zink는 template entry의 offset을 context 내부 UBO 위치로 지정하고 실제 push에는 context 시작 주소를 넘긴다. 현재 Mesa 설정으로 소스의 실제 구조를 컴파일해 얻은 값은 다음과 같다. Mesa 소스나 기존 빌드 출력은 수정하지 않고 상수만 별도 artifact에 생성했다.

| 값 | 바이트 |
|---|---:|
| zink_context 전체 | 112768 |
| vertex UBO 위치 | 58256 |
| fragment UBO 위치 | 61328 |
| compute UBO 위치 | 62096 |
| descriptor info / write metadata | 24 / 64 |

vertex singleton의 예에서 기존 보관 범위는 58280바이트, compact 보관은 88바이트다. 이는 해당 입력의 복사량 근거다. Zink의 descriptor mode·push 지원·uniform 변경·fbfetch 혼합 여부에 따라 호출/적격성이 달라지므로 모든 draw가 이 절감을 얻는다고 계산하지 않는다. 실제 BAR의 현재 호출 빈도·절감 CPU 시간·FPS 이득은 측정하지 않았다.

template 객체는 foundation ON/OFF 모두 104→120바이트다. command 객체는 현재 앱의 foundation ON에서 72바이트로 같고 OFF에서는 64→72바이트다. Metal3의 작은 입력도 추가 적격성 확인을 거치므로 byte 감소가 순 CPU/FPS 이득을 보증하지는 않는다. [실제 구조 상수](../artifacts/validation/v104-followup-c-t-20261020/zink-layout.json), [실제 객체 크기](../artifacts/validation/v104-followup-c-t-20261020/final-object-sizes.json).

## 검증과 검수

- 활성 MVK 증분 빌드와 두 production translation unit의 foundation ON/OFF 문법 검사 4개가 통과했다. 엔진·Mesa 재빌드는 하지 않았다.
- 기존 descriptor CPU fixture를 확장해 실제 template class·constructor·accessor와 capture 메서드를 실행했다. ASan·UBSan ON 629 / OFF 134 assertions 통과. 대체 layout/state/vector/pool과 선언된 generic size라는 fixture 한계는 유지한다. wrapper가 synthetic template 변경마다 실제 constructor를 재실행하므로 constructor 실제 빈도나 성능 측정으로 쓰지 않는다.
- 최대 끝 위치가 마지막 entry가 아닌 경우, stride 0/8/정상/4096, empty/mixed/array·목적 범위 fallback, 정적/현재주소 overflow와 오류 우선순위, template 재생성, 소유 snapshot·중복 순서·부분 배열, 크기 변화·OOM·pool 재사용·strict smaller 선택을 확인했다.
- 기존 native prepared suite 6/6 통과. 공통 template 사례는 명시적인 옵션으로 Metal3/Metal4를 각각 선택해 실제 legacy/native queue를 확인했다. 각 6회 cycle과 graphics 소비에서 sparse/unaligned·stride·duplicate·mixed fallback·취소 node 재사용·기록 후 입력 변경·mapped 최신 내용·query/helper 뒤 결과를 확인했다. Metal API Validation을 켰다.
- 기존 fixture의 기본 기대값은 계속 native Metal4이며, native 완료 counter와 argument-buffer 검사를 유지한다. 별도 M3 선택은 legacy 큐를 확인하고 Vulkan fence/queue idle 완료 뒤 결과를 읽는다. Metal4 실행을 Metal3 검증이라고 부르지 않는다. GPU 실행은 foundation ON 라이브러리, argument-buffer 환경 0이다.
- Astra + High 검수자는 실제 구현자와 별개이며 선행 설계 작성자다. 최종 7파일 diff·고정핀·CPU/native 증거·raw 라이브러리를 대조했고 actionable finding 0건이었다. 새 검사를 중복 실행하지 않았다. [최종 검수](../artifacts/validation/v104-followup-c-t-20261020/independent-review-common.md).

초기 C-T 단독 단계의 검증·검수는 별도 파일로 남겨 최종 공통 구현의 증거와 구별한다. 처음 기존 CPU fixture의 고정 indent 추출이 현재 중첩과 맞지 않아 실행 전에 실패했고, 동일 production block의 brace 경계를 읽도록 수정해 해결했다. 새 제품 코드의 실패를 숨기거나 stale 결과를 최종 결과로 사용하지 않았다.

## 정점 바인딩 캐시 재평가

과거 R92는 native setter보다 앞의 ownership/setter CPU 확인을 줄였지만 Metal4 평균 42.426132→41.072590 FPS로 개선이 관측되지 않았다. 두 새 표본의 변동이 커 그 차이의 안정적 인과를 확정할 수는 없다. 기존 native setter는 같은 Metal 쓰기를 이미 생략했고, 추가 memo에는 31개 슬롯 1488바이트와 초기화·비교 비용이 있었다.

현재 소스에도 당시 캐시가 대체하려던 vertex registration/setter 문장이 남아 있다. C-T는 기록 시 검사를, C-M3는 legacy payload 보관을, B는 primitive 변환의 CPU 임시 저장을 바꾼다. 이 변경들은 native vertex memo의 buffer/유효 offset/stride/물리 slot/table identity·revision/recording·pass 경계를 바꾸지 않는다. 따라서 캐시 적중률을 직접 높이는 상호작용은 확인되지 않는다.

상승효과 가능성을 영구 배제하지 않는다. 지금 AA Off는 과거 실험의 4×MSAA보다 GPU 부담이 작을 수 있어 vertex CPU 비용이 상대적으로 중요해질 수 있고, 다른 CPU 절감과 합쳐 병목 비중이 달라질 수 있다. 반대로 memo 관리 비용이 절감보다 클 수도 있다. 현재 BAR의 반복 동일 binding 수·절감 시간·FPS 이득은 새로 측정하지 않았다.

이를 확인하려면 같은 현재 조건에서 무변경/descriptor만/정점 cache만/둘 다를 구분하는 별도 비교가 필요하다. 단순히 현재 앱이 빨라졌다는 결과만으로 두 변경의 상호작용을 주장할 수 없다. 이번 요청에서는 cache를 부활시키거나 새 게임 배치를 실행하지 않았다. 기존 table cache를 더 일찍 참조하는 작은 대안도 현재 recording의 ownership과 helper/pass/lease invalidation을 별도로 증명해야 하며 native 포인터 일치만으로 등록을 생략하지 않는다. [재평가 기록](../artifacts/validation/v104-followup-c-t-20261020/vertex-cache-reassessment.json).

[최종 diff](../artifacts/validation/v104-followup-c-t-20261020/applied-common.patch), [검증 요약](../artifacts/validation/v104-followup-c-t-20261020/validation-summary.json), [공식 설계·출처](v104-followup-c-design-20261020.md). 공유 AGENTS/HQ 기록·자동화·설치·발행·사용자 설정은 변경하지 않았다.

## 완료한 누적 앱

새 앱은 artifacts/runtime/v104-descriptor-candidate-20261020/BAR.app이며 P1/P2/P3+B+C-T+C-M3를 포함한다. 표시 버전은 1.0.3이고 로컬 v1.0.4 후보 명칭만 사용한다. 이전 AB 후보 대비 MVK dylib와 재서명 관련 2항목만 바뀌며, 두 엔진과 launcher 실행코드는 그대로다. 앱 1194항목·의존성211연결·strict nested 서명을 확인했다. frozen v1.0.3, P1/P2/P3 후보, AB 후보의 전체 인벤토리가 그대로이며 기록된 보호 핀 57개도 일치했다. 앱/게임 실행·설치·발행은 하지 않았다. [패키징 근거](../artifacts/validation/v104-followup-c-t-20261020/package-receipt.json), [완료 기록](../artifacts/validation/v104-followup-c-t-20261020/completion.json).
