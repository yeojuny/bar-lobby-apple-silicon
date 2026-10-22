# 4. compact UBO push의 조건부 조기 CPU State 기록 확대

상태: `source-capsule-prepared-early-native-path-gates-activation`

Prepared compact singleton-UBO capture only as State, with independent encoder layout ownership. Command-owned normalized metadata is copied to encoder CPU descriptors; no mapped UBO contents are snapshotted. Native buffer address resolution moves earlier; valid bound resource identity and existing host visibility remain required. Mixed/generic capture stays Deferred.

## 코드화/실행 조건

- Demonstrate less total or critical-path work, not merely moving work to recording
- Review a lifetime/state table for recorded, unsubmitted, adopted, cancelled and reset commands
- Independent reviewer closes layout reuse and mutable mapped-input counterexamples

## 검증

- Existing recording group/ownership fixtures for destroy-after-record, cancel/reset, mixed fallback, query/pass order
- Functional GPU cases after source/build; no broad early-record enable

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
