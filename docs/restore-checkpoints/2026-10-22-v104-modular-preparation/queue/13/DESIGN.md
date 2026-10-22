# 13. E3 범위를 넘는 barrier·GPU 완료 대기 중복 축소

상태: `dependency-edge-proof-gated-no-code`

Choose one observed redundant edge outside the completed experimental E3/Combined candidate; E3 is not active in frozen R unless explicitly composed. Preserve actual issued RAW/WAR/WAW visibility, destination stages, query availability, host reads, semantic signals, error cleanup and address/allocator reuse. A worker idle wait alone never proves a removable GPU wait.

## 코드화/실행 조건

- Name the exact edge, producer/consumer and critical-path wait interval
- Prove alternative ordered visibility for every affected consumer and terminal failure path
- Independent ownership/synchronization design review passes before any wait/barrier change

## 검증

- Existing queue-barrier-reuse/completion/timeline/native tests
- Cross-queue/host/query/address-reuse and poison/cancel cases; no global wait suppression

Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.

Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.
