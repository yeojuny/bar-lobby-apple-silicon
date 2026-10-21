# v1.0.4 후보 — 남은 Buffer 등록 호출부

2026-10-20. 사용자 “그래 해보자”에 따라 이전 Astra + Max 설계의 작은 호출부 수정을 구현했다. allocator·descriptor 공유·패스·동기화 정책은 변경하지 않았다. FPS 개선은 아직 측정하지 않았다.

## 변경과 후보

제품 변경은 활성 MoltenVK 소스의 `MVKCmdDraw.mm`, `MVKCmdTransfer.mm`, `MVKQueryPool.mm` 세 파일이다. indexed draw의 index buffer, buffer copy의 source/destination, transfer compute helper의 명시적 Buffer pair, query 결과의 source/destination을 기존 `addBufferResource`에 연결했다.

transfer의 공통 오류 본문은 유지했다. 기본 template 인자는 Unknown으로 기존 image/mixed 호출을 그대로 처리하고, buffer copy 두 입력만 NonTexture를 명시한다. nil 검사, 오류 초기화·short-circuit 순서, 범위/overflow, Recording phase/device 검사, 현재 기록의 retain/residency와 lock, query/transfer 의존성은 유지한다. 새 cache나 공유 상태는 없다.

이미 같은 기록에 resident인 버퍼는 기존에도 타입 판별 전에 반환한다. 이번 변경의 이익은 주로 새 버퍼의 첫 등록에서 발생한다. 매 draw마다 비용이 사라지거나 FPS가 상승했다고 주장하지 않는다.

- 기준: `artifacts/runtime/v104-drawable-size-candidate-20261020/BAR.app`.
- 새 후보: `artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app`.
- 표시 버전은 1.0.3이며 로컬 v1.0.4 누적 후보다. 앞선 P1/P2/P3+B+C-T+C-M3+C-REG와 양쪽 엔진의 drawable-size helper를 포함한다.
- raw MVK: `ed983a2648efe352336ca0896e4682d7d9a61e02b56347a5d2680b8f8795ac9f`.
- packaged MVK: `c5ea9b843ba2284c410a0b83b7e2412d4cbc0446f15232b5b317eca56b79f804`.

## 관련 검증

| 검사 | 결과 |
|---|---|
| 기존 등록 CPU fixture, ASan/UBSan | 410 assertions 통과. 실제 공통 등록 구현을 사용하며 GPU/전체 binder 검사는 아님 |
| 제품 세 번역 단위, foundation OFF/ON | 6/6 통과 |
| 현재 활성 Release 증분 빌드 | 변경한 세 object와 link만 실행, 3.58초. diagnostics OFF 유지 |
| 실제 Metal4 Vulkan 출력 | 최초 7개 + 후속 2개 실행 통과. 고유 사례 8개이며 byte-copy는 한 번 중복 실행 |
| 실제 Metal3 공통 Vulkan 출력 | indexed render, aligned copy, distinct/same-buffer regions, copy/compute/fill continuation, occlusion query copy, parallel byte-copy 총 7개 통과 |
| Metal3 timestamp host/GPU 비교 | 후보에서 실패. 정확한 수정 전 raw 라이브러리에서도 동일 위치·오류 재현. 미해결로 보존 |
| 앱 패키지 | 1,194개 항목, MVK와 서명 관련 두 항목만 변경. 엔진/런처 실행 코드 유지, closure 211 edges, strict deep signature 통과 |

GPU 검사는 기존 production-linked fixture의 해당 함수만 선택했다. 직접 라이브러리를 연결한 offscreen Vulkan 검사이며 BAR.app 게임 실행·수동 시각 검증을 대신하지 않는다. indexed readback, copy 데이터와 guard, 바이트 helper/두 큐/pool reset, query packed/narrow/stride/availability/reset 및 occlusion 값을 확인했다. native queue 선택과 completion을 확인했으며 Metal3에는 native 완료 카운터 조건을 요구하지 않았다.

### Metal3 timestamp 실패의 처리

기존 `timestamps` 함수의 마지막 native 완료 횟수 assertion만 명시적 M3 context에서 제외한 임시 fixture로 같은 입력을 실행했다. 후보와 수정 전 baseline 모두 `GPU/host timestamp result, availability, or padding mismatch at 64`에서 실패했다. 원인은 이번 범위에서 확정하지 않았다. 이를 통과로 세거나 제품 query 동작을 추측 변경하지 않았다.

첫 baseline 로딩 시도는 install-name `libMoltenVK.1.dylib` alias가 backup에 없어 후보가 로드됐다. 그 시도는 `validBaselineComparison=false`로 기록했다. backup에 해당 alias를 추가한 뒤 `DYLD_PRINT_LIBRARIES`로 **실제 baseline 경로와 원래 SHA256**을 확인한 재실행에서 동일 실패를 재현했다. 최초 잘못된 시도와 정확한 재현 자료를 모두 남겼다.

시간값 비교가 없는 기존 occlusion query 검사와 byte-copy를 양쪽 backend에서 추가 실행하여 모두 통과했다. 이는 timestamp 실패를 해소한 것이 아니다. 임시 fixture 변경은 원본으로 복원했고, 최종 제품 diff는 세 파일뿐이다. 재현용 임시 fixture와 실행 파일/로그는 이번 evidence에 보존했다.

## 보존과 한계

이전 후보 전체 inventory, 변경 외 31개 입력, launcher HEAD/index/status를 대조했다. 이전 raw dylib는 `backups/runtime/v104-typed-buffer-callers-20261020/`에 보존했다. 현재 source/build lane 하나만 사용했다. 기존 미해결 sampled BAR native-exit 관찰은 여전히 별도 미해결이며 이번 offscreen 통과로 해소됐다고 보지 않는다.

실제 BAR 게임·FPS 비교, 앱 설치, 공식 Release/Homebrew 갱신은 실행하지 않았다. 사용자 동시 작업이 섞인 과거 FPS와 합산하지 않는다. 독립 검수와 GitHub 복원 checkpoint 결과는 별도 receipt로 연결한다.

근거: `artifacts/validation/v104-typed-buffer-callers-20261020/`의 원본 patch, before, source pins, CPU/빌드/GPU receipts, package receipt와 app inventory.

독립 Astra + High 검수 완료: actionable findings 0. 세 제품 파일, 보호 31개 입력, 원본 fixture 복원, 실제 baseline 로딩, 두 앱 inventory와 raw/packaged Mach-O 대응을 확인했다. 범위 밖 timestamp/종료 문제와 FPS 미측정 한계는 유지된다. `independent-review.json` 및 `.md` 참고.

검수 후 이번 작업에서 생성한 성공 CPU·followup 검사의 실행 파일/디버그 심볼 4 roots, 8 files, 7,534,088 logical bytes만 정리했다. 물리 회수량을 주장하지 않는다. 해당 소스·컴파일 인자·결과·로그와 실패 timestamp 실행 파일/심볼은 보존했다. 기존 검수의 실행 파일 hash 확인은 삭제 전 시점의 기록이다. 정확한 목록은 `derived-cleanup-selection.json`과 `derived-cleanup-completion.json`에 있다.
