# MVK experimental restoration checkpoint — 2026-10-20

This preserves two local experiments, **not a stable v1.0.4 release**. Both apps still display **1.0.3**. Stable Release/Homebrew are unchanged. The checkpoint belongs to the BAR Mesa/Zink → Vulkan Loader → MoltenVK port.

| State | Included | Status |
|---|---|---|
| `parent-ab` | P1/P2/P3 + B | Earlier comparison app, retained |
| `descriptor` | P1/P2/P3 + B + C-T + C-M3 | Later comparison app, retained; Metal4 slowdown concern |

A was excluded on actual-use evidence. The vertex binding cache was analyzed only and is absent from both states. No whole dependency update is included. Mesa/Zink, SDL, OpenAL, Vulkan Loader, original healthbar/tracker and numeric/sync policies retain the v1.0.3 basis.

## Performance result and limits

The owner completed eight successful games, zero retries: two runs per app/backend in ABBA order, AC + Low Power Mode, Ultra/AA Off/Spring, 1432×902, matched official scene/seed/900 workload frames. Metal3 means were **44.9535 → 48.3632 FPS (+7.5851%)**, with substantial spread in the new samples. Metal4 means were **38.6810 → 34.8919 FPS (−9.7959%)**; both new samples were slower than both old samples, and p95/p99 worsened. This is an explicit concern, not an overall improvement or promotion. Two samples do not establish stable source causality. Requested 1× includes an actual-speed ramp; global driver/filesystem caches were uncontrolled. C-T/C-M3 contributions and vertex-cache interaction remain unmeasured.

See the [full report](evidence/reports/v104-descriptor-performance-comparison-20261020.md), [summary with eight samples](evidence/artifacts/validation/v104-descriptor-performance-comparison-20261020/summary.json), and associated per-run receipts, benchmark results and native logs. The publisher did not repeat the games. Deleted private shader/browser caches and content clones are **not** restoration prerequisites and are not claimed to remain available.

## Frozen basis and contents

The source basis is tag `v1.0.3`, commit `e213e890559210e135dccab5342de55b9e1a7c08`, tree `8b972194deb00a9cd8063a1558208cd8193d6573`. Use the complete **BAR-1.0.3-sources.tar.gz** companion, not GitHub's automatic launcher source archive. Its SHA256 is `61ae84d7e6da5b4fe758f6d5cd97239902c1c88dd3c56914b313b2634bda4ac1`.

- [manifest.json](manifest.json) binds the three inner source archives, 15 source preimages/postimages, modes, original source/build roots and application order.
- `preimages/`, `postimages/` and `patches/` provide complete changed files and component-relative diffs. Apply P1/P2/P3 to both engine bases; B then final common C-T/C-M3 to MVK. The final common patch supersedes the retained initial C-T-only record.
- `build-config/` preserves normalized full CMake caches, configure inputs and generated engine version headers. Original compiler/numeric/sync settings are retained. MVK uses Release, arm64, foundation ON, private API ON, custom diagnostics OFF and source-derived `MVK_GIT_REV=f52facf7`. Lobby uses Clang; Chobby uses GCC16 with Clang Objective-C++ as recorded. Do not replace these with guessed defaults.
- `evidence/` preserves original changes, before states, CPU/native/build receipts, fixture sources, review pins and packaging scripts. C-T/C-M3 final review found no actionable findings; earlier stage records retain their original scope. [evidence-index.json](evidence-index.json) binds original and exported hashes; personal workspace paths were normalized to `$WORKSPACE`/`$HOME`. This changes exported text hashes, not product source bytes.
- [basis-audit.json](basis-audit.json) compares every regular archive member present in the current sources, excluding explicit `v1-build-inputs` export metadata. Only the 5 declared files per component differ. It does not enumerate extra untracked current files.
- [app-deltas.json](app-deltas.json) and `app-deltas/` restore both exact signed apps from the released 1.0.3 app. Only five paths change per state: two native engines, MVK dylib, signed launcher executable and CodeResources. The latter executable differs from signing metadata while launcher code is preserved. Against the AB parent, the descriptor app changes three paths, not two. Eight shared/deduplicated patches total approximately 10.6 MB; no duplicate full app/source/build archive was created.

## Restore source without executing a build

Obtain this branch with Git, then use this directory as `checkpoint`. The branch is `restore/mvk-20261020-p123-b-ct-cm3`; pin its verified commit for durable restoration.

```sh
git clone --filter=blob:none --single-branch --branch restore/mvk-20261020-p123-b-ct-cm3 https://github.com/yeojuny/bar-lobby-apple-silicon.git bar-mvk-restore
checkpoint="$PWD/bar-mvk-restore/docs/restore-checkpoints/2026-10-20-mvk-p123-b-ct-cm3"
curl -fL -o BAR-1.0.3-sources.tar.gz https://github.com/yeojuny/bar-lobby-apple-silicon/releases/download/v1.0.3/BAR-1.0.3-sources.tar.gz
python3 "$checkpoint/restore-sources.py" --wrapper BAR-1.0.3-sources.tar.gz
python3 "$checkpoint/restore-sources.py" --wrapper BAR-1.0.3-sources.tar.gz --state descriptor --out restored-descriptor-sources
python3 "$checkpoint/restore-sources.py" --wrapper BAR-1.0.3-sources.tar.gz --state parent-ab --out restored-parent-ab-sources
```

The last two commands require fresh destinations. They extract the three frozen inner archives and overlay checked postimages; the AB state leaves the four descriptor files at the v1.0.3 preimages while applying B. They never touch the original workspace. Other unchanged component archives, notices, dependency sources/recipes and packaging/license material remain in the complete v1.0.3 wrapper. Original GPL v2-or-later engine and Apache-2.0 MoltenVK notices are preserved; copied source headers retain attribution.

For a source build, follow the wrapper's existing component build instructions and dependencies, using these pinned source outputs. Translate `$WORKSPACE`/`$HOME` in copied configuration to the fresh restoration workspace. Reconfigure into fresh build directories using the retained typed configure inputs; do not drop the original numeric flags or reuse an old machine's absolute CMakeCache paths blindly. The recorded active targets were `engine-legacy` for both engines and `MoltenVK` for MVK. Generated `VersionGenerated.h` retains the official Lobby `2026.09.01-24-g01efdf4 master`, Chobby `2026.07.04` and `BAR-1.0.3` values. Existing wrapper dependency/compiler coverage still applies; a source rebuild on another toolchain is not guaranteed byte-identical. No build is executed by these restore scripts.

Raw MVK SHA256 is `443cae49eeca6814a7374cf510178416660e07238715e1ceb451f648e92eb60a`; packaged SHA256 is `7ac71989ca27a99a2f9adf219ac0dcb12f16804cd35733bf7fd2c078635c5c4a`. The packaging receipt/script records install-name relocation and ad-hoc signing, with identical executable text. Engine raw/packaged identities and original v1.0.3 relocation recipes are retained in the evidence/wrapper. Prefer the exact app restoration below when matching signed historical bytes matters.

## Restore either exact experimental app

Download the existing v1.0.3 ZIP, SHA256 `1c12ab2d5a660d2f46d6c0343f6a57642b5556b348ebada8f2c139328f35a0f2`. Extract it into a fresh `base` directory with macOS `ditto -x -k BAR-1.0.3-arm64.zip base`. Neither helper launches or installs the app.

```sh
python3 "$checkpoint/restore-app.py" --base-app "$PWD/base/BAR.app" --state parent-ab
python3 "$checkpoint/restore-app.py" --base-app "$PWD/base/BAR.app" --state parent-ab --out "$PWD/restored-parent-ab/BAR.app"
python3 "$checkpoint/restore-app.py" --base-app "$PWD/base/BAR.app" --state descriptor --out "$PWD/restored-descriptor/BAR.app"
```

Python3 and `zstd` are required. The helper verifies all 1194 basis entries, creates a fresh app copy, applies only verified file deltas, checks all final file/link contents and file modes, and performs strict nested signature verification on macOS. No resign, launch, installation, graphics preference change or automated acceptance is performed. Quarantine/Finder metadata and arbitrary extended attributes are outside the exact file-content claim. Source and binary restoration are separate paths; neither depends on retired test caches.

## Follow-up evidence

This branch is a restoration record. Later measurements may be appended as new commits under `followups/` with explicit app/source/measurement bindings. Retain this commit's hashes and original mixed result; do not rewrite it as an accepted stable release or overwrite existing stable source tags.
