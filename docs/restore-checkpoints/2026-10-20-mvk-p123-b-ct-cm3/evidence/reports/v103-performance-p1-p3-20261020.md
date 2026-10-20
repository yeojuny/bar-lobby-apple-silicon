# v1.0.3 P1–P3 공통 렌더링 CPU 조회 축소 완료

2026-10-20, America/Los_Angeles. Codex SOL 6.1 / High가 조사·구현·CPU 검사·증분 빌드·적용 코드 검토를 수행했다. P1/P2/P3를 두 활성 엔진에 모두 적용했다. 동결 v1.0.3 앱은 변경하지 않았다. **소스상 중복 조회 감소는 확인했으며 FPS 향상은 측정하지 않았다.**

## 기준과 편집 범위

편집 직전 배포 v1.0.3 source-export inventory와 후보 6파일씩 총 12파일의 SHA256이 다시 일치했다. Lobby는 `build/run91-recoil-src-694e9df7`, Chobby는 `artifacts/runtime/run94-chobby-official-20260704-20260924/source`를 그대로 사용했다. 각 엔진의 `LuaOpenGLUtils.cpp`, `LuaVBOImpl.cpp/.h`, `NamedTextures.cpp/.h`만 변경했다. 기존 `tools/tests/test-run95-luavbo-layout.cpp`는 검사 함수 반환형 선언 한 줄만 맞췄다. 별도 엔진 소스·의존성·빌드 트리는 만들지 않았다.

정확한 패치는 [applied-source.patch](../artifacts/validation/v103-performance-p1-p3-20261020/applied-source.patch), 검사 선언 변경은 [fixture.patch](../artifacts/validation/v103-performance-p1-p3-20261020/fixture.patch)에 있다. 기존 dirty/untracked launcher 상태는 보존했다. 소스 snapshot 디렉터리를 Git clean checkout이라고 주장하지 않는다.

## 기존 외부 기여 확인

P1/P2/P3 각각에 대해 **확인한 외부 소스에서 동일 수정은 발견하지 못했다.** 아래 실제 소스와 관련 PR을 비교한 뒤 작은 변경을 직접 구현했다. 전체 GitHub의 모든 브랜치에 같은 수정이 없다는 주장은 아니다.

| 확인 대상 | 고정 커밋/출처 | 결과 |
|---|---|---|
| 공식 Recoil master | [63a4a4bd](https://github.com/beyond-all-reason/RecoilEngine/tree/63a4a4bd2b209c1c63c9e4ca5fc99adf7c9adeb9) | 해당 LuaOpenGLUtils, LuaVBOImpl, NamedTextures 실제 코드에 세 중복 조회가 남아 있음 |
| benbreen native 포트 | [a49a8ecc](https://github.com/benbreen/RecoilEngine-AppleSilicon/tree/a49a8ecc5265c4dd3f8d0016d90b32e81e22c73b) | 같은 세 중복이 남아 있음. IMPROVEMENTS/LESSONS는 탐색용으로만 읽었으며 성능 증거로 채택하지 않음 |
| tomjn 엔진 fork | [4d76fd88](https://github.com/tomjn/RecoilEngine/tree/4d76fd88bad3bce1cdba50cb6d340f25e2fc7df4) | 실제 관련 저장소를 특정함. 기본 브랜치에 같은 세 중복이 남아 있음 |
| tomjn macOS 통합 PR | [#3271](https://github.com/beyond-all-reason/RecoilEngine/pull/3271), head `7efc6d9b79ecb1932dd1bf63c9c529e5e6ce5b5a` | 해당 세 파일을 head에서 직접 재확인. P1/P2/P3는 미해결 |
| BAR Wine 프로젝트 | [0dcdac1a](https://github.com/BambaDamba/bar-on-apple-silicon/tree/0dcdac1afc483331c391136bee298303f0ae6959) | 실제 `mesa-bar-patches.diff`는 Zink/Venus/WSI 파일의 변경이다. 엔진 이름·속성 조회 수정이 아니므로 이식하지 않음 |

공식 PR 검색은 `NamedTextures`, `LuaVBOImpl`, texture+lookup, author:tomjn으로 제한했다. tomjn의 [#3553](https://github.com/beyond-all-reason/RecoilEngine/pull/3553) (head `e088373b47fdea69750a83b17afacf0a723d7e01`)은 Upload/Download padding, [#3551](https://github.com/beyond-all-reason/RecoilEngine/pull/3551) (head `1cfa65a1366d7a567170dd9b72d40c7b04d02b3e`)은 할당 크기 검사다. 둘 다 확인 시 open/unmerged이며 P2의 조회 전달 수정과는 다르다. 기존 로컬 padding·직접 변환·크기 보정은 다시 신규 성과로 세지 않았다.

엔진 파일의 GPL v2-or-later 헤더와 benbreen의 GPL-2.0 저장소 표시를 확인했다. Wine 저장소의 라이선스는 GitHub API에서 Other로 표시되었으므로 이를 임의로 GPL 코드 전체와 동일시하지 않았다. 외부 패치 자체를 복사·채택하지 않았고 기존 엔진의 라이선스 헤더를 유지했다.

공식 BAR도 [26bf7c18](https://github.com/beyond-all-reason/Beyond-All-Reason/tree/26bf7c1862d83198cf5d63c7379099191fe5c503)의 실제 파일로 연결을 확인했다. PIP는 동적 텍스처 생성, `modules/graphics/instancevbotable.lua`는 단일/목록 InstanceDataFromUnitIDs/FeatureIDs, healthbars는 atlas 이미지 `gl.Texture`를 호출한다. 현재 master 확인이 동결 앱의 게임 버전을 바꾼 것은 아니다. 선택된 31671과 동결 healthbar의 연결 근거는 [기존 후보 보고서](v103-performance-step1-candidates-20261020.md)에 유지된다.

출처 URL·해시·원문 발췌·PR patch는 evidence의 `external-source-review.json`, `external-discovery.json`, `upstream-bar-and-integration-review.json`에 있다.

## 적용 내용

| 항목 | 변경 | 소스상 조회 수 |
|---|---|---|
| P1 동적 Lua 텍스처 | GetIdx(name)를 한 번 호출하고 기존 GetInfo(index)의 범위 검사를 사용. 그 인덱스를 LuaMatTexture에 전달 | 정상 이름 조회 2→1 |
| P2 인스턴스 속성 | InstanceBufferCheck의 find 결과를 const 속성 참조로 반환하여 바로 형식 검사에 사용 | 스칼라 속성 조회 3→2, 비어 있지 않은 표 5→3 |
| P3 일반 이미지 | 기존 GetInfo API를 유지하고 인덱스를 함께 반환하는 overload를 추가. ParseTextureImage가 그 결과를 사용 | 이미 로드된 이름 조회 2→1 |

P1은 인덱스 0을 실패로 간주하지 않는다. 없는 이름·삭제된 이름의 sentinel과 기존 범위 검사도 그대로다. 새 캐시나 프레임 간 포인터 보관은 없다.

P2 참조는 각 형식 검사 함수 안에서만 소비된다. InstanceDataFromImpl의 콜백 앞/뒤 두 검증은 유지했고 콜백을 넘어 참조를 보관하지 않는다. UploadInstanceData의 별도 at, 다중 ID 트랜잭션 저장소, 오류 순서, CPU shadow와 엔진 소유 버퍼 방어는 변경하지 않았다. Instance/Matrix 진입 함수와 Upload/Delete/UploadInstanceData 본문이 편집 전과 정확히 동일한 것을 대조했다. Matrix 경로의 별도 조회 축소는 이번 변경에 포함하지 않았다.

P3 기존 4인자 GetInfo는 새 overload로 전달하므로 기존 호출과 symbol을 유지한다. persist OR 갱신, GL_LIST_INDEX 확인, display-list 지연 생성, secondaryGLContext 전달, GenLoadTex 호출 및 후속 map 접근을 유지한다. 추가한 인덱스 출력만 되돌리면 원래 조회 본문과 정확히 일치한다. 기존 최초 로드 실패의 후속 map/vector 접근도 수정하지 않았다. 따라서 이 변경이 기존 로드 실패 처리를 개선했다는 주장은 하지 않는다. 기존에 잠금 없는 조회의 스레드 계약도 확장하지 않았다.

## 검사·빌드·검토 결과

| 검증 | Lobby | Chobby |
|---|---|---|
| 기존 LuaVBO 실제 메서드 CPU fixture, 실제 Lua/sol2 + ASan/UBSan | 2,024 cases / 41,666 assertions / 실패 0 | 2,024 cases / 41,666 assertions / 실패 0 |
| 기존 내부 Instance/Matrix 검사 | paired calls 391 통과 | paired calls 391 통과 |
| 기존 Upload length callback 검사 | 15 통과 | 15 통과 |
| 기존 활성 native engine-legacy 증분 빌드 | 종료 0, 약 11.95초 | 종료 0, 약 19.67초 |
| CMakeCache/build.ninja | 전후 해시 동일 | 전후 해시 동일 |

두 엔진 모두 `LuaOpenGLUtils.cpp`, `NamedTextures.cpp/.h`가 바이트 동일하다. 해당 공통 코드의 작은 CPU 비교에서 동적 텍스처 6개 사례와 일반 텍스처 80개 조합이 통과했다. 실제 변경 전/후 함수 본문을 추출하여 비교했고 GL/로드 호출 경계는 stub으로 관찰했다. 일반 텍스처 검사는 empty/hit index0/hit index1/miss/load-failure, forceLoad/persist/secondaryGLContext/display-list 조합 및 기존 API 전달을 확인했다. ASan/UBSan 오류는 없었다. 이는 실제 이미지 업로드·GL context·GPU 수명 검증을 대신하지 않는다. 기존 Lua/streflop 정적 라이브러리 내부에 sanitizer를 새로 넣지는 않았다.

빌드에는 기존 파일·의존성에서 발생하는 format/sol2/entt 및 duplicate-library 경고가 있었으며 오류는 없었다. 이번 조회 수정으로 새 경고가 생겼다는 증거는 없다. 바이너리 문자열과 생성 version header의 공식 identity는 Lobby `2026.09.01-24-g01efdf4 master`, Chobby `2026.07.04`, 추가 버전 `BAR-1.0.3`이다. 이번에는 native version CLI도 실행하지 않았으므로 이 identity 확인은 정적 검사다.

적용 코드 자체를 다시 읽고 반환 참조 범위, Lua 재진입 경계, 오류 처리, 기존 호출자와 overload, 숫자·sync·shader·자원 수명 정책에 대한 영향이 없는 것을 검토했다. 별도 독립 reviewer가 검토했다는 주장은 하지 않는다. 자세한 결과는 `applied-code-review.json`, 두 `cpu-*/receipt.json`, 두 `*-build.json`, `texture-cpu.json`, `dynamic-texture-cpu.json`에 있다.

## 보존과 남은 검증

동결 v1.0.3 BAR.app의 1,194개 파일/링크가 전후 정확히 일치했다. v1.0.3의 기존 source-edits 21개도 모두 유지했다. 실제 launcher HEAD `6a3b298c236cd10eff8fd7ce27d15cdb589f650f`, index SHA256 `073483d1f4a62c9cda7006b467f60da926f889d1c8f126dc0016e3a23b761c87` 및 기존 dirty 상태가 동일하다. 체력바/tracker 공급, CUS/NoGS, shader, 시뮬레이션/AI, 숫자 정책, Metal 기본값과 의존성 스택은 변경하지 않았다.

새 바이너리는 두 기존 활성 build의 spring에 있다. 배포 앱·패키징 자산으로 복사하거나 설치하지 않았다. 앱/게임/창 실행·종료, FPS/MP 검사, 공개 릴리스, 업로드, 정리, 다른 프로젝트 접근, 다른 채팅 메시지 및 공유 AGENTS/HQ 기록 수정은 하지 않았다. 자동화는 PAUSED 상태를 유지했다.

남은 미측정 항목은 실제 호출 빈도·CPU 시간·FPS/프레임 시간과 Metal3/Metal4 실제 게임 회귀다. 공통 엔진 경로의 조회 수를 줄였다는 사실이 어느 Metal 모드의 FPS 상승이나 상대 순위 개선을 증명하지 않는다. 새 수명·동시성 계약 변경은 필요하지 않았다.

[최종 completion.json](../artifacts/validation/v103-performance-p1-p3-20261020/completion.json), [보존 결과](../artifacts/validation/v103-performance-p1-p3-20261020/preservation.json).
