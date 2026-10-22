from pathlib import Path
import json,hashlib,datetime,subprocess,plistlib
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();before=read(O/'before.json');packages=read(O/'packages.json')
assert all(sha(R/p)==h for p,h in read(O/'R/source-pins.json').items())
assert sha(R/'build/metal4-mvk-20261002/CMakeCache.txt')==before['CMakeCacheSHA256']
assert sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib')==read(O/'R/completion.json')['rawSHA256']
assert read(R/'artifacts/runtime/v104-local-candidate.json')==before['currentCandidate']
protected=read(R/'artifacts/validation/v104-r-combined-reverse-20261021/performance/protected-inputs.json')
for p in protected['userState'].values():assert sha(p['path'])==p['sha256']
src=read(R/'artifacts/validation/v104-r-combined-reverse-20261021/performance/protected-source-launcher.json');launcher=R/'sources/bar-lobby'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==src['HEAD']
assert sha(launcher/'.git/index')==src['indexSHA256']
assert subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)==src['status']
review=read(O/'independent-source-review.json');assert review['actionableFindings']==[]
for role in ['R','Combined']:
 p=packages[role];c=read(O/role/'completion.json');assert c['status']=='passed';assert p['rawSHA256']==c['rawSHA256'];assert p['entries']==1194 and p['closureEdges']==211 and p['deepStrictSignature'];assert p['diagnosticsCompile']==0 and p['countLimit']==32
 assert plistlib.loads((Path(p['app'])/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='1.0.3'
 assert sha(Path(p['app'])/'Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib')==p['packagedSHA256']
 assert p['sourcePins']==read(O/role/'source-pins.json')
 if role=='R':assert p['sourcePins']==read(O/'R-expected-source-pins.json')
 for label in ['cpu-build','cpu-run','mvk-build','native-build','native-run','vulkan-build','vulkan-m4','vulkan-m3','foundation-off']:assert read(O/role/(label+'.json'))['exitCode']==0
 assert 'PASS 46290 checks' in (O/role/'cpu-run.log').read_text()
 # Both source variants apply the identical new class, retaining their original
 # R versus D/E1/E2/E3 difference in the other product bytes.
 header=(O/(role+'-next.h')).read_text();s=header.index('class MVKMetal4PreparedGroupCache {');e=header.index('\n};',s)+len('\n};');assert header[s:e]+'\n'==(O/'group-cache-after.inc').read_text()
report=R/'reports/v104-group-lookup-20261021.md'
text='''# R와 R+전체에 동일 준비표 위치 조회 최적화 — 2026-10-21

R 및 R+전체(R+D+E1+E2+E3)에 같은 제품 변경을 각각 적용하고 별도 앱으로 만들었다. 기존 R/R+전체는 그대로 보존했다. 새 알파벳 후보명 대신 기준+변경명을 쓴다.

실제 Metal4 binder는 같은 기록에서 준비 group을 반복 조회한다. 기존 BAR 진단 자료의 group checks 1,886,293 / full reuse 1,654,897은 이 경로가 반복된다는 근거이며 현재 후보의 시간 비중이나 새 FPS 효과를 뜻하지 않는다. 새 변경은 MVKMetal4PreparedGroupCache에서 stage별 최근 script의 map node 위치만 기억한다. 같은 script가 같은 stage에서 반복되면 unordered_map find를 건너뛰고 기존 stamp/epoch/revision/weak proof/partial/stableStamp 검증 본문을 그대로 실행한다. 긍정 위치 6개만 보관하고 범위 밖 stage는 map을 쓴다. map 128개 한도, admission/update/refresh/clear 경계는 보존한다. rehash에도 안정적인 Entry*를 사용하고 clear 때 위치를 먼저 비운다. 객체 복사·이동은 금지했다. 실제 소유 SubmissionState는 기존 mutex로 이미 복사·이동되지 않는다.

제품 파일은 GPUObjects/MVKMetal4PreparedResource.h 하나다. 두 baseline의 GroupCache 기존 본문이 같고 새 본문도 byte-exact임을 확인했다. 하나의 active source/build lane에서 R+전체 쪽을 먼저 검증·동결한 뒤, R의 정확한 11개 원본으로 되돌려 같은 패치를 적용·빌드했다. 현재 source/build는 R+준비표 위치 조회 최적화다. 양쪽 차이인 D/E1/E2/E3와 Q/R allocator 정책은 각 source pin과 11개 variant state에 연결돼 있다.

| 새 앱 | 표시 버전 | CPU 대조 | 관련 native GPU | Vulkan Metal3·4 | 앱·서명 |
|---|---|---|---|---|---|
| R+준비표 조회 최적화 | 1.0.3 / local v1.0.4 후보 | 46,290 checks 통과 | sequential recording/출력/끝난 기록 clear 통과 | 각 3사례 통과 | 1,194 entries / closure211 / strict 통과 |
| R+전체+준비표 조회 최적화 | 1.0.3 / local v1.0.4 후보 | 46,290 checks 통과 | 동일 통과 | 각 3사례 통과 | 동일 통과 |

CPU는 실제 새 header와 동결된 이전 class에 같은 입력을 주어 complete/partial 반환과 revision/stableStamp callback 횟수를 대조한다. ASan/UBSan에서 deterministic 50,000 trace와 rehash·stage overwrite·128개 한도·범위 밖 stage·clear/re-admission·weak owner 만료·revision/unstable refresh·partial residual·drawable epoch·잘못된 stamp를 확인했다. 별도 counting hasher 관찰용 class는 동결/새 제품 class에서 이름과 hasher 타입만 치환했다. 같은 여섯 stage의 1,200회 hot lookup에서 hash 호출 1,200→0회를 확인했으며 제품에 계측을 넣지는 않았다. 이는 작업량 검사이며 시간/FPS 측정이 아니다.

native fixture는 기존 sequentialPrimaryTableSnapshots의 실제 GPU 출력, sequential encoder lease, recording-end CPU metadata 해제/다음 기록 miss를 확인한다. 그 안의 synthetic CPU proof는 실제 자원 provenance 증거로 사용하지 않는다. Vulkan 선택 사례는 descriptor revision/new recording, compatible layout fallback, fragment texture/sampler 출력이다. 양쪽 Metal3·4 각 3개를 통과했다. 각 variant의 증분 MVK 빌드와 foundation OFF syntax도 통과했다. 새 전체 conformance/게임/MP/다른 Mac 검증은 수행하지 않았다.

6개 script/pointer 위치로 targeted64-bit ABI에서 cache metadata는 40→136bytes, 즉 기록당96bytes 늘었다. 추가 분기/clear/공간 비용도 있으므로 순이익·FPS 개선은 아직 미확정이다. 진단 compile/runtime OFF와 allocator32/growth2MiB/available8/idle64MiB는 유지한다. 새 FPS 비교·BAR 앱/게임 실행은 0회다. 원래 선택 R pointer는 유지하며 두 새 앱은 비교 준비 후보로 보존한다.

기존 앱마다 변경은 MVK runtime, launcher 실행파일의 재서명, CodeResources의 세 파일뿐이다. launcher 코드/엔진/게임/그래픽 설정 bytes와 사용자 실제 프로필·실제 launcher HEAD/index/status를 보존했다. 배포판이나 GitHub Release/Homebrew 업데이트는 수행하지 않았다.

'''
for role,p in packages.items():
 label='R+준비표 조회 최적화' if role=='R' else 'R+전체+준비표 조회 최적화'
 text+=f'- [{label}]({p["app"]}) — MVK SHA256 `{p["packagedSHA256"]}`\n'
text+='\n독립 소스 검수에서 행동이 필요한 결함은0이었다. 최종 산출물 검수는 별도 기록으로 연결한다.\n'
report.write_text(text)
summary=dict(status='both-candidates-implemented-validated-packaged-awaiting-final-evidence-review',createdUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),productFiles=['GPUObjects/MVKMetal4PreparedResource.h'],sameClassPatchBothBaselines=True,workingSourceBuild='R-plus-group-locator',selectedCandidateUnchanged='R',FPSMeasured=False,gameSessions=0,diagnosticsCompile=0,allocatorRecordings=32,CPUChecksPerVariant=46290,nativeCasesPerVariant=1,vulkanCasesPerBackendPerVariant=3,extraMetadataBytesPerRecording=96,packages=packages,report=str(report),reportSHA256=sha(report),sourceIndependentReviewFindings=[])
(O/'completion.json').write_text(json.dumps(summary,indent=2)+'\n')
# Separate pending-comparison metadata; do not promote the selected baseline.
(R/'artifacts/runtime/v104-group-locator-candidates.json').write_text(json.dumps(dict(status='ready-for-comparison-not-promoted',basedOn=['R','R+D+E1+E2+E3'],apps={k:p['app'] for k,p in packages.items()},completion=str(O/'completion.json'),FPSMeasured=False),indent=2)+'\n')
print('Both frozen apps validated and packaged; source/launcher/user state preserved. Report SHA256 '+sha(report))
