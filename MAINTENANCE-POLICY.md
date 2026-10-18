# BAR 유지보수·검증·GitHub 업로드 정책

적용일: 2026-10-17. 대상은 **BAR 배포판 관리**와
`$WORKSPACE`이다.

사용자가 요청한 순서는 **정리 → 구분된 한 단위 적용 → 관련 검사 → 검수 →
GitHub 소스 업로드**다. 통과한 단위만 다음 기준으로 삼는다. 실제 공개 앱과
Homebrew 갱신은 마지막 통합·패키지 확인 뒤에 수행한다.

RAE·SWIV·다른 프로젝트와 개인 자료는 연락·조회·적용·정리 대상에서 제외한다.

## 담당과 단일 소유권

| 역할 | 담당 |
| --- | --- |
| 현재 소스 적용·컴포넌트 빌드 | BAR MVK HQ — 스택 통합·빌드 |
| 변경 범위·검증 근거 검수 | Audit - MK2 |
| GitHub 소스·Release·Homebrew | BAR MVK — GitHub·배포 관리 |
| 역사 기준·복구 보존 확인, 이번 한정 정리 실행 | BAR R88 종합 검수·최신 스택 조사 |

활성 소스·빌드 경로는 하나씩 재사용한다. `run66` 같은 과거 경로명은 현재
내용의 버전이 아니다. 현재 기준은 **Run95+VBO 이후 누적 패치와 candidate.5
유지보수 수정이 포함된 소스**다. 둘 이상의 담당이 같은 제품 파일이나 실제
Git index를 동시에 수정하지 않는다.

## 0. 먼저 정리하고 복구 기준을 확인한다

- 기존 고정 목록의 패키징 중간 앱, 동일 내용의 중복 다운로드, 지정된 옛
  생성 산출물·캐시부터 현재 상태를 대조한다. 후보 부모 폴더 전체를 지우지 않는다.
- 현재 앱·소스·활성 빌드·필수 복구본·원본 실패 증거·사용자 콘텐츠는 보존한다.
  candidate.5의 보류 중 전송 조각도 이 정리의 대상이 아니다.
- 삭제 전 정확한 목록, 보존 정본/재생성 근거, 현재 사용·진입 링크, 파일
  상태를 확인하고 기록한다. 조건이 불명확한 항목은 보류하고 확정 항목부터 처리한다.
- 경로와 파일 종류를 검증하고 링크를 따라가지 않는다. 전후 볼륨 여유 공간과
  삭제 파일의 논리/할당량을 구분해 기록한다. APFS 표시량을 실제 회수량으로 부르지 않는다.
- 새 전체 소스·빌드·앱 복제본이나 대형 압축본을 만들어 공간을 더 소비하지 않는다.

다음 단위의 복구에는 실제 기준 바이트가 필요하다. 변경 전 파일·patch만
이름으로 남기거나 Git SHA/해시 목록만 남기는 것으로 복구가 완성되지 않는다.
현재 정본, dirty/untracked 입력, 필요한 직전 라이브러리와 빌드 조건이 확보돼야 한다.
정리를 위해 다른 프로젝트의 작업이나 원격 업로드를 새로 시작하지 않는다.

## 1. 위험이 낮은 순서와 필요한 확인만

위험은 라이브러리 이름이 아니라 **실제 바뀌는 경로·소유권·동작**으로 나눈다.
OpenAL의 작은 초기화 수정과 SDL의 독립 문자열 수정은 낮은 위험이다. 전체
OpenAL 147커밋이나 SDL 91커밋을 한꺼번에 바꾸는 것은 같은 등급이 아니다.
현재 쓰지 않는 플랫폼·기능의 변경은 개수만 채우려고 적용하지 않는다.

| 등급·순서 | 해당 변경 | 이 단계에서 필요한 확인 |
| --- | --- | --- |
| 0 · 실행 시험 없음 | 문서·주석·CI만 변경, 제품 산출물에 영향 없는 기록/메타데이터. 현재 Mac에 무관한 플랫폼 변경은 생략 | diff·출처·업로드 내용 확인만. 제품 빌드·게임·GPU·소리·MP 시험 없음. CMake·compiler·ABI·native 버전 표시는 이 등급이 아님. |
| 1 · 낮음 | SDL S1 UTF-8 한 줄, S2 환경 mutex 실패 처리. OpenAL A1 기본 effect-slot 한 hunk처럼 작게 분리 가능한 초기화 수정 | 해당 컴포넌트 빌드와 기존 관련 문자열/환경/초기화 검사만. 전체 게임·해상도·FPS·MP 시험 반복 없음. A1은 기본 reverb 경로 필요성이 있을 때만 선택하며 전체 upstream commit을 끌어오지 않음. |
| 2 · 제한된 동작 변화 | Loader L5 실패 pNext 복원, L4 설정 경로 두 커밋 | 실패/성공 연결 복원, parser 경계와 새로 읽히는 외부 설정·드라이버 선택 확인. 보통 게임 반복 시험은 필요 없음. |
| 3 · 영향이 넓음 | Cross C1 shader 생성, Loader L1/L2/L3 공유 잠금, SDL Cocoa 창·화면·키보드 경로 | shader 결과/캐시 또는 잠금·수명·동시성의 관련 검사. 창을 바꾸면 기존 실제 target-screen·safe-area·DPI·fullscreen 정책을 확인. 필요할 때만 해당 화면/게임 경로를 한 번 확인. |
| 4 · 별도 작업 또는 보류 | SDL 오디오 출력 전환, OpenAL/SDL 전체 갱신, 새 HRTF/키맵 소유권, Mesa/MVK 광범위 변경·새 기능 | 구체적인 이득과 현재 알려진 문제를 먼저 해결. 활성 경로에 맞는 통합 확인이 필요하며 작은 정확성 큐와 섞지 않음. |

문서에 적용 순서를 적거나 diff를 읽는 일을 새 runtime 검증으로 부르지 않는다.
작은 수정에 별도 벤치마크·새 harness·게임 전체 시험을 만들지 않는다. 이미 있는
관련 검사가 변경 경로를 다루면 재사용하고, 필요하지 않은 검사는 `not-required`
및 이유를 남긴다. 필요한 검사를 생략했을 때는 `not-run`이며 통과가 아니다.
빌드·캐시·실제 앱 버전을 바꾸는 메타데이터는 단순 문서와 구별한다.

### OpenAL과 SDL의 경계

- 현재 OpenAL은 CoreAudio ON, SDL2/SDL3 backend OFF다. OpenAL A1
  `e77723ff`의 기본 effect-slot `updateProps`만 분리하면 낮은 위험 후보지만,
  기본 reverb가 없는 context에는 직접 이득이 없다. 같은 commit의 constructor/
  consteval 연쇄까지 작은 수정으로 묶지 않는다.
- 기록된 새 upstream OpenAL HRTF 캐시는 filename 키 저장 누락 때문에 재사용을
  놓칠 수 있어 전체 갱신을 보류한다. **현재 사용 중 OpenAL의 결함이라는 뜻은 아니다.**
  새 SDL keymap 소유권 전환도 기존 객체 해제 판단에 새 객체의 flag를 쓰는 우려가
  있어 보류한다. 이 두 항목을 제외했다고 전체 라이브러리 동등성이 입증되지는 않는다.
- 해상도 정책 보존은 SDL 창 변경의 필수 조건이다. 문자열·환경 수정에는 화면
  시험이 필요 없다. SDL 전체 변경에는 입력 객체 수명·이벤트·오디오 등도 있으므로
  해상도 정책 하나만으로 무위험으로 판정하지 않는다. SDL_Renderer/SDL_GPU는 현재
  BAR 렌더링 경로가 아니므로 그 변경만으로 BAR 화면 개선을 기대하지 않는다.

### SDL 오디오의 이득과 우선순위

현재 두 native lane의 `OpenSdlDevice`는 `RECOIL_MACOS_SDL3_EGL`에서 false를
반환한다. 기존 `UseSDLAudio` 구현도 OpenAL을 제거하지 않는다.

- 현재: **OpenAL 공간음향·믹싱 → OpenAL CoreAudio → macOS 출력 장치**.
- 대안: **OpenAL loopback 믹싱 → SDL stream → SDL 출력 장치**.

SDL3의 기본 장치 변경 추적과 공통 장치 처리 방식은 잠재적 이점이다. 그러나
현재 출력 문제나 성능·지연·용량 개선이 입증된 것은 아니다. OpenAL의 믹싱·EFX/
HRTF를 계속 사용하므로 이 경로만 켜도 OpenAL 의존성이 사라지지 않는다.
현재 코드의 SDL2 callback 방식은 SDL3 stream API로 옮겨야 하며 장치 열기/
재개·종료, callback 수명, format/channel/resampling/buffering을 맞춰야 한다.
따라서 **현재 CoreAudio 출력을 유지하고, 구체적인 장치 문제나 요구가 생길 때
별도 단위로 검토**한다. OpenAL을 완전히 제거하는 오디오 엔진 교체는 더 큰 작업이다.

근거: [현재 엔진 구현](docs/release-readiness/2026-10-17-v1.0.0/SOURCE-STATUS.md),
[SDL3 공식 오디오 이전 문서](https://wiki.libsdl.org/SDL3/README-migration),
[SDL_OpenAudioDeviceStream](https://wiki.libsdl.org/SDL3/SDL_OpenAudioDeviceStream).

## 2. 우선 적용 큐: 8단위·upstream 10커밋

전체 컴포넌트를 최신 HEAD로 갈아끼우지 않는다. 아래 고정 커밋의 필요한
변경을 현재 누적 패치 위에 선택 적용한다. 정확한 40자리 SHA와 기록 양식은
[단위 정의](docs/maintenance-units/2026-10-17/units.json)에 둔다.
`U1~U8`은 위험을 반영한 진행 순번이고, 감사·파일·commit의 식별자는 차례대로
`S1, S2, L5, L4, C1, L1, L2, L3`를 사용한다. 같은 등급 안에서 절대적인
위험 확률을 계산한 순서는 아니다. OpenAL A1은 낮은 위험의 **선택 후보**로
별도 기록하며 현재 8단위에 자동 추가하거나 이미 적용했다고 표시하지 않는다.

| 순서·단위 | upstream 커밋 | 최소 범위와 관련 검증 |
| --- | --- | --- |
| U1 · S1 · SDL 4바이트 UTF-8 | `57f22e6e` | 두 번째 continuation byte 마스크 수정. 해당 코드포인트와 기존 문자열 검사. 한글 IME 전체 수정으로 설명하지 않는다. |
| U2 · S2 · SDL 환경 mutex 실패 | `52ef28ae` | mutex 생성 실패 반환과 뒤 단계 실패 시 정리를 함께 적용. 기존 환경변수/초기화 정상·실패 경로와 한 번 정리 확인. |
| U3 · L5 · Loader 실패 pNext 복원 | `77406fdf` | 실패 판정 전 caller 연결 복원. 성공/하위 생성 실패의 원래 pNext 보존과 caller 수명 확인. |
| U4 · L4 · Loader 설정 경로 | `d77a2a09` + `a3fdec40` | **두 커밋 한 단위**. 두 번째 이후·한 글자·빈/구분자 경계. 외부 설정 적용과 번들 드라이버 선택 확인. |
| U5 · C1 · Cross 음의 0 | `300681bb` | 정밀 곱셈/행렬 도우미와 공식 예상 결과. #2687 보존, 관련 fixture, MVK/Cross 빌드·새 캐시 식별자 확인. |
| U6 · L1 · Loader surface 잠금 | `2d3e7b9b` | 조회·지연 생성 잠금과 반환별 해제. 기존 생성/삭제 보완, 관련 동시성/수명 검사. |
| U7 · L2 · Loader device callback 잠금 | `6b45d762` | `loader.c`와 `trampoline.c` 함께. 일반 진입·직접 callback·생성/삭제·실패·잠금 균형. |
| U8 · L3 · Loader debug messenger | `e38751a7` + `73cf5326` | **두 커밋 한 단위**. 공통 잠금과 중복 잠금 제거. 메시지/삭제 경쟁·재진입 제한·출력 OFF 확인. |

L3·L4의 두 조각 사이를 통과 상태로 게시하지 않는다. 나머지는 원인과 영향이
다르므로 한 commit이나 한 검증 결과로 합치지 않는다. Loader 다섯 단위는 같은
빌드 캐시를 재사용하되 각각 적용하고 확인한다. 준비 편의로 순서를 다시 바꿀 때도
낮은 위험 우선 원칙과 각 단위의 독립적인 통과 기록을 지킨다.

별도 보류 목록은 유지한다. cJSON 전체 갱신, MoltenVK depth-clip/로컬 Metal4
연결, 새 SDL 키맵 소유권, 새 OpenAL HRTF 캐시, Mesa 전체 갱신과 추가 근거가
필요한 성능 후보는 U1~U8에 끼워 넣지 않는다. 이미 동등하게 포함된 Loader
#2050도 중복 적용하지 않는다.

## 3. 한 단위의 처리 순서

1. **입력 고정:** 단위 ID, upstream SHA, 실제 로컬 파일/바이트, 현재 base,
   기존 로컬 패치, 컴파일러·SDK·옵션·의존성을 기록한다. 다른 작업의 변경을
   발견하면 그 차이를 먼저 식별한다. reference clone의 fetch/lazy fetch/reset은 하지 않는다.
2. **작은 복구점:** 기준 원본 내용, 변경 전 파일·모드·링크, patch와 필요한
   직전 raw 라이브러리/빌드 조건을 확보한다. 작은 수정마다 전체 빌드와 앱을 복제하지 않는다.
3. **적용:** 해당 최소 범위만 변경한다. 관계없는 정리·버전 변경·성능 실험을 섞지 않는다.
   충돌은 현재 로컬 안전 조건을 보존해 해결하고 원본과 달라진 이유를 기록한다.
4. **검사:** 위 위험 등급에 필요한 upstream/기존 fixture와 최소 빌드만 실행한다.
   검사 명령·입력·종료 코드·산출물 해시와 실제 확인 범위를 기록한다. 실패한 기존 사례를
   건너뛰거나 기준값을 근거 없이 바꾸지 않는다.
5. **검수:** Audit - MK2가 실제 diff, 로컬 수정 보존, 테스트 범위, 새 비용과
   알려진 공백을 확인한다. 정적 검토·CPU 검사·실제 GPU/게임 결과를 각각 표시한다.
6. **확정·소스 업로드:** 필요한 단위 검사가 통과하고 검수 결과가 정리되면
   해당 단위를 한 논리 commit으로 저장·업로드한다. public export가 다른 구조라면
   정확한 패치·base·recipe·source association을 함께 연결한다.
7. **다음 단위:** 위 통과본을 다음 base로 고정한다. 실패하면 현재 단위에서
   수정·재검사하거나 그 단위를 정확히 되돌린다. 실패 상태에 다음 패치를 계속 쌓지 않는다.

검증이 없는 상태는 `needs-validation`, 실패는 `failed`, 되돌렸으면 `reverted`다.
기존 기록을 읽은 상태는 새 검사 `passed`가 아니다. 기존 Loader D6는 새 잠금/
settings/pNext 검사가 아니며, 기존 Cross alias 두 사례도 음의 0 검사가 아니다.
공식 테스트 실행 파일·도구 연결이 아직 없으면 그 공백을 해결하기 전 해당 검증을
통과 처리하지 않는다. 가능한 경우 기존 테스트를 확장하며 새 제품 도구·벤치마크·
프로브·런타임 계측을 별도로 늘리지 않는다.

새 SDL 소스를 검사할 때 기존 `testautomation` 실행파일을 그대로 실행한 결과를
사용하지 않는다. 변경한 라이브러리에 연결해 필요한 테스트 대상을 다시 빌드한다.
Loader의 공식 테스트도 기존 local 의존성 연결부터 확인하고 자동 외부 dependency
갱신을 켜지 않는다. 테스트 runner의 과거 출력 경로는 새 단위 evidence로 바인딩해
원본 receipt를 덮어쓰지 않는다. 전체 앱 복제는 최종 단계에 모으고, 단위별로는
실제 변경 라이브러리와 필요한 lock/closure/서명 근거만 범위에 맞게 남긴다.

NoGS·CUS·stream lifetime·버퍼 경계·SHIELD·수치/컴파일 정책, 공식 엔진 sync
identity, CPU submit wait OFF, cost collection OFF는 변경 대상이 아니다.
Cross 변경 시 캐시 식별자와 실제 새 라이브러리를 연결한다. 잠금/오류 처리를
FPS 개선으로 설명하지 않는다.

## 4. GitHub에 올리는 기준

**단위별 소스 업로드**와 **최종 앱 공개**는 서로 다른 결과다.

- 단위 commit은 정확한 적용 내용, upstream 출처, 로컬 적응, 검사 근거와 남은
  검증을 설명한다. CPU만 확인했으면 그 범위를 표시하고 게임/GPU 통과를 주장하지 않는다.
- 기본 업로드 대상은 명시적으로 선택한 유지보수 브랜치의 검증된 소스 체크포인트다.
  미완성/실패 작업을 `main`/`master`나 정식 릴리스에 섞지 않는다. 브랜치·대상 ref는
  실제 원격 구조와 출판 manifest에서 확정한다. 이 문서가 임의 이름의 ref 생성을 뜻하지 않는다.
- workspace 루트는 Git 저장소가 아니다. 실제 launcher HEAD/index에는 기존 미커밋
  작업이 있으므로 `git add -A`, 실제 index reset/checkout, 무관한 파일 staging을 하지 않는다.
  기존 동결 입력·독립 index 출판 방식으로 선택 파일과 native 대응 소스를 구성한다.
- component 원본 위치와 공개 wrapper 경로가 다르면 매핑을 manifest에 남긴다.
  해당 patch를 적용할 실제 base 내용과 대응 소스를 공개/보존 가능한 방식으로 연결한다.
- 공개 단위 bundle은 공개적으로 확보 가능한 불변 base에서 재구성돼야 한다.
  로컬 절대경로, 비공개 초안에만 있는 archive, launcher 자동 source ZIP만을
  완전한 native base로 부르지 않는다. 필요한 작은 preimage와 기존 공개 archive/
  앞선 단위 체인을 연결하며, 매 단위 전체 source archive를 중복 생성하지 않는다.
- commit 전 경로·내용·크기와 원본/생성물 구분을 확인한다. 비밀정보, 사용자 로그,
  계정/설정, 앱·빌드 전체 사본, 대용량 진단 원본을 소스 commit에 섞지 않는다.
- 정상 fast-forward push와 명시적 ref를 사용하고 원격 commit/tree/blob을 읽어 확인한다.
  원격 ahead/diverged이면 강제 push·임의 merge/reset으로 덮지 않는다. 동결 tag를 이동하지 않는다.
- GitHub API 조회가 끊겨도 업로드를 반복하지 않는다. 공식 Git HTTPS의 최신 ref OID,
  그 OID로 재해시한 정확한 commit의 parent/tree·변경 경로·mode/blob 관계, 같은
  불변 commit의 공식 raw URL에서 받은 모든 변경 파일의 바이트·길이·SHA256/Git
  blob ID를 대조하는 동등한 방법도 허용한다. 실제 사용한 전송과 검증 방법을
  기록하고, 받지 못한 API 응답을 성공했다고 표시하지 않는다. 실제 HEAD/index와
  기본 브랜치 보존도 확인한다. codeload archive를 쓰면 archive의 일반 파일
  permission 표시와 Git의 실행 비트 기반 file mode를 구별한다.
- 공개 단위에는 component-relative `change.patch`, base/출처/전후 hash의 `manifest.json`,
  실제 `validation.json`, 적용본의 감사 근거, build/export recipe 연결을 둔다.
  생성할 commit 자신의 SHA를 자기 tree 안에 미리 넣지 않는다. 실제 commit SHA와
  원격 확인은 commit 뒤 별도 작은 receipt에 기록한다.
- 사용자가 적용·검증·업로드까지 지시한 실행에서는 합의된 범위 안의 각 단계를
  이어서 수행한다. 단위마다 같은 승인을 반복해서 묻지 않는다. 이 정책 작성 자체는
  지금 패치 적용·원격 쓰기·자동화 재개를 시작하는 명령이 아니다.

## 5. 마지막에 버전과 공개 앱을 만든다

다음 제품 번호는 **1.0.0 / v1.0.0**이다. 현재 포함 목록은 candidate.5 유지보수와
실제 적용·검사·감사·소스 업로드가 완료된 U1~U8(S1/S2/L5/L4/C1/L1/L2/L3)이다.
최종 적용 근거는 [8단위 완료 기록](docs/maintenance-units/2026-10-17/COMPLETION.json)이다.
사용자의 “그래 해봐”로 V1 통합·master 반영·Release·Homebrew 실행이 승인됐다.
이 번호 선택과 실행 승인은 새 앱의 검증 완료를 뜻하지 않으며, 아래 순서로 확인한다.

버전·패키징은 별도 **V1 단위**다. 앱 package/lock/buildVersion/ASAR/plist,
두 native lane의 `VERSION_ADDITIONAL=BAR-1.0.0`, 소스 동반자료·notices·체크섬·
Homebrew 표기를 함께 맞춘다. 버전 의존 최소 엔진 재컴파일/재링크와 새 native
SHA/input-lock/서명 검증이 필요하다. 공식 GetSync/engineDirectory는 유지한다.

최종 단계에서는 다음을 확인한다.

- 통과 단위 목록과 소스·컴포넌트·빌드 산출물의 정확한 대응.
- 영향 범위에 필요한 기존 CPU/type/Lua/VBO 검사와 새 라이브러리 closure,
  새 앱의 안쪽 코드부터 바깥쪽까지 서명·파일/링크/모드 검증.
- 필요한 실제 화면/게임 확인은 요청된 범위의 정상 BAR.app 경로로 수행한다.
  캡처 뒤 자동 종료·신호·재시작을 하지 않는다. 미수행/실패 범위를 숨기지 않는다.
- 같은 정확한 서명 앱 하나로 DMG/ZIP을 생성하고 installer readback을 확인.
- 새 대응 소스와 최신 선택 문서, 라이선스 고지, 최종 SHA256 일치.
- 새 tag/release/source commit과 자산 manifest의 일치. candidate.5의 untagged
  초안·실패한 재조립을 성공한 새 릴리스로 취급하지 않음.
- 공개 자산의 digest/길이와 실제 익명 readback 확인 뒤 Homebrew cask 갱신·재확인.
  소스 업로드 성공을 앱 공개 완료나 로컬 설치 완료로 부르지 않음.

정식 번호는 게임·FPS·전체 MP·다른 Mac·공증 검증을 대신하지 않는다.
현재 범위와 필요한 검증만 정확하게 주장한다. 관련 없는 큰 시험을 매 단위
반복하지 않고, 최종 통합 검사는 바뀐 전체 조합을 대상으로 수행한다.

## 기록과 공간 규칙

단위 기록에는 ID, 포함 upstream SHA, local base/preimage/postimage, touched files,
적용 patch/hash, 관련 검사 명령/결과, 변경 산출물, 검수 판정, 남은 범위, 복구 방법,
소스 commit·원격 확인, 다음 base를 남긴다. 실패와 되돌림 기록도 보존한다.

큰 앱/원본 소스 archive는 공개 경계에서 동결한다. 통과 소스 단위마다 전체 앱·
소스·빌드 archive를 새로 만들지 않는다. 새 캐시·전송·패키징 임시본은 소유자,
생성 이유, 정본과의 대응, 폐기 조건을 기록한다. 원격 검증 전 필요한 로컬 payload는
보존하고, 새 작업 시작 전 예상 최대 추가 공간을 확인한다.

기존 자동화는 PAUSED 상태를 유지한다. 이 정책이 주기적 실행이나 감시를 새로
만드는 것은 아니다. 제품 변경·검증·출판 담당은 위 역할을 유지한다.
