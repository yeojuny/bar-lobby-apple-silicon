#!/usr/bin/env python3
"""Write the existing thirteen-item queue, preserving evidence gates and identity."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
SOURCE=ROOT/'artifacts/validation/v104-remaining-optimization-inventory-20261021/inventory.json'
PRECEDENTS=ROOT/'artifacts/validation/v104-optimization-precedents-20261021/external-assessment.json'
ASSESSMENT=ROOT/'artifacts/validation/v104-optimization-risk-return-20261021/independent-assessment.json'

# These are staged work contracts, not speculative performance promises.
DESIGNS={
 1: {
  'status':'implemented-Small-awaiting-qualified-performance',
  'strategy':'Reuse the exact bounded-positive-reserve patch and existing correctness qualification. Do not implement another vector/SBO/cache scheme.',
  'acceptance':['Finish the already prepared forward8/reverse8 comparison without original contaminated8 pooling','Keep R selected unless a later adoption decision names Small'],
  'tests':['Existing Small descriptor/texture CPU, native and package receipts; do not repeat without cause'],
  'code':['artifacts/validation/v104-r-small-bundle-20261021/unit1.patch'],
  'interactions':[8,9]},
 2: {
  'status':'source-capsule-prepared-reachability-gates-activation',
  'strategy':'If repeated pre-Deferred queries are established, store the exact current flags/type predicate as immutable layout-owned metadata at construction. No address-keyed global cache and no early-push expansion to manufacture reach.',
  'acceptance':['Existing BAR prefix shows repeated layout policy classification before the first Deferred; otherwise close as no useful change','All binding flags, type exclusions, zero descriptors and empty layouts match the original predicate'],
  'tests':['Existing recording-group policy cases with original predicate as oracle','Foundation ON/OFF and M3 unaffected behavior'],
  'codeModules':['02-layout-policy'],
  'interactions':[4]},
 3: {
  'status':'source-capsule-prepared-prefix-evidence-gates-activation',
  'strategy':'Prepared an exclusively owned replay head/tail chain. The existing _next belongs to replay only after completed encoding and before detached pool return. It is never concurrently owned by replay and the async pool. Restore splices prefix/suffix in O(1); no new field in every command.',
  'acceptance':['Meaningful long-prefix collection/fallback cost established','Explicit state table owns every command from capture to adoption, cancel, reset or fallback; exactly one pool return'],
  'tests':['Existing recording-ownership cases: empty/single/long prefix, suffix restoration, cancellation, secondary and simultaneous use','Delayed pool return and original command order oracle; no cycles or duplicate release'],
  'codeModules':['03-owned-replay-chain'],
  'interactions':[4]},
 4: {
  'status':'source-capsule-prepared-early-native-path-gates-activation',
  'strategy':'Prepared compact singleton-UBO capture only as State, with independent encoder layout ownership. Command-owned normalized metadata is copied to encoder CPU descriptors; no mapped UBO contents are snapshotted. Native buffer address resolution moves earlier; valid bound resource identity and existing host visibility remain required. Mixed/generic capture stays Deferred.',
  'acceptance':['Demonstrate less total or critical-path work, not merely moving work to recording','Review a lifetime/state table for recorded, unsubmitted, adopted, cancelled and reset commands','Independent reviewer closes layout reuse and mutable mapped-input counterexamples'],
  'tests':['Existing recording group/ownership fixtures for destroy-after-record, cancel/reset, mixed fallback, query/pass order','Functional GPU cases after source/build; no broad early-record enable'],
  'codeModules':['04-compact-cpu-state'],
  'interactions':[2,3]},
 5: {
  'status':'negative-pass-proof-gated-no-code',
  'strategy':'Attach a conservative no-conversion summary to an already recorded pass interval only if the existing capture path can produce it cheaply. Any unknown/dynamic topology, fan, restart, provoking requirement, shader write or inherited uncertainty selects the original full planner.',
  'acceptance':['Existing evidence shows meaningful negative lookahead scanning','All commands in the exact interval are covered; first pipeline/draw alone is never proof','Summary construction cost does not simply duplicate the skipped scan'],
  'tests':['Existing primitive-plan/native cases with baseline planner as oracle','Dynamic topology, secondary/inherited state and unknown command force fallback; producer/handoff barriers unchanged'],
  'interactions':[11]},
 6: {
  'status':'source-capsule-prepared-terminal-predicates-reviewed',
  'strategy':'Suppress only success feedback pre-retirement notification. Actual child predicate is Completed||error; queue predicate is pending0||firstError. Success feedback bits alone satisfy neither. feedback.error preserves the early notification even with zero handlers; final/error/poison notifications remain.',
  'acceptance':['CPU sleeping-waiter schedules pass; validate actual native callback progress after activation','Every terminal/error path and inline/duplicate/range/tail callback reaches a preserved notification','Existing shutdown failures remain visible; this is not a shutdown fix without reproduction'],
  'tests':['Existing backend timeline/completion/recording-ownership CPU tests with deterministic sleeper-before-notify schedules','Error-success race, missing terminal feedback and delayed completion; bounded timeout is test failure'],
  'codeModules':['06-success-notify'],
  'interactions':[7,13]},
 7: {
  'status':'source-capsule-prepared-immutable-proof-reviewed',
  'strategy':'A noncopyable submit-local proof names the exact fresh strongly-held group after its successful complete check. Ended claimed children reject legal event mutation. Publication still reads current event values; direct calls and absent/mismatched proof run full validation.',
  'acceptance':['Repeated multi-signal groups established; zero/one-signal paths not burdened with new allocation','Token cannot outlive or cross changed children/signal lists','Concurrent external event advancement remains rejected at publication'],
  'tests':['Existing group signal/timeline cases: unsorted/duplicate, zero/one/multi, direct publication and retry','Current value advances after validation; wrong-group proof falls back, legal Ended mutation is rejected. Arbitrary private-vector mutation is outside the proven invariant.'],
  'codeModules':['07-signal-order-proof'],
  'interactions':[6,13]},
 8: {
  'status':'08a-and-08b-source-capsules-prepared-runtime-and-benefit-open',
  'strategy':'08a preserves conservative resource invalidation while skipping unchanged legacy implicit payload invalidation. Separately08b derives a bounded recording-local proof for unchanged covered binding slices in a new descriptor combination; changed slices become residual. Repeated observations return to existing full capture, except rejected captures. Global snapshot identity and per-recording fresh native guards/retention/residency remain.',
  'acceptance':['08a source/CPU/build/GPU gates are separate from partial-sharing acceptance','Identify repeated subsets and concrete rescuable miss causes; old selected full/partial replay0 is not evidence of benefit','Actual partial/full transition, concurrent replacement, drawable/alias revocation and native lifetime fixture after cue'],
  'tests':['08a value/growth/layout/encoder/helper cases','Broader snapshot: existing descriptor/prepared-texture lifecycle cases plus concurrent replacement and stale weak-proof rejection'],
  'codeModules':['08a-conservative-rebind','08b-partial-group-replay'],
  'interactions':[1,9]},
 9: {
  'status':'source-capsule-prepared-contention-gates-activation',
  'strategy':'Acquire shared immutable entry under mutex, run unchanged live-retain callback outside, and erase on Miss only if exact entry identity still matches. Admitted allocation failure preserves the old map and current native ownership. Replacement adds allocation/refcount cost; concurrently replayed old entries can temporarily exceed the map64 bound.',
  'acceptance':['Per-binding mutex contention is established, not inferred from a nested callback','Entry ownership and replace/delete races reviewed jointly with the group8 design','Noncontended path cost and bounded retained memory remain acceptable'],
  'tests':['Existing snapshot replay fixture with deterministic replacement between lookup/retain/failure cleanup','Stale failed entry must not erase a new entry; old owner survives callback; no dangling pointer'],
  'codeModules':['09-snapshot-unlocked-retain'],
  'interactions':[1,8]},
 10: {
  'status':'policy-evidence-gated-no-new-tuning',
  'strategy':'Keep recordings32/growth2MiB/available8/idle64MiB as the parent. Use existing counters and one isolated policy value per experiment if churn or memory pressure identifies a cause. Preserve Q/R quiescent reset and idle-first state machines; 64 was already tested.',
  'acceptance':['A named churn/memory-pressure condition and a single justified alternative value are recorded','No change to writer, unsubmitted owner, GPU completion, reset/reoffer/cancel/poison contracts'],
  'tests':['Existing allocator lifecycle/OOM/cancel tests','Paired throughput and peak retained-memory observation; do not infer physical reclaim from budget size'],
  'interactions':[11,13]},
 11: {
  'status':'11a-patch-ready-general-pass-merging-gated',
  'strategy':'First test Typed frame-local discard (11a), which communicates ended data lifetime upstream. Any later driver pass merge must target one proven redundant boundary and preserve attachment/subresource, load/store, sampling, query, alias and producer-consumer requirements. Never equate E2 descriptor construction with pass merging.',
  'acceptance':['11a readonly/model retention/DSA and actual context checks pass','For broader merging, establish a specific repeated boundary with preserved intermediate observations','Review fallback for every unknown attachment/query/alias case before code'],
  'tests':['11a actual StreamBuffer and Typed owner CPU checks plus later real Mesa context','Existing suspend/resolve/visibility/native cases for exact proposed merge'],
  'codeModules':['11a-typed-frame-discard'],
  'interactions':[5,10,12,13]},
 12: {
  'status':'pass-ownership-proof-gated-no-code',
  'strategy':'Only for a proven repeated internal MSAA split, pre-classify fragments and the final consumer before encoder creation. Resolve exactly when required, including final termination without another draw. Unknown/memoryless/alias/visibility cases retain existing resolves. No unconditional extra Store/Load or final encoder.',
  'acceptance':['A concrete group11 split with multisampled offscreen attachments is observed','Intermediate consumers, memoryless/private lifetime and final resolve ownership are explicit','AA Off window setting is not proof all offscreen attachments are single-sample'],
  'tests':['Existing suspend-resolve and visibility recycle CPU/native cases','No-final-draw, depth/stencil, alias/readback, memoryless and one-unbroken-pass regressions'],
  'interactions':[11,13]},
 13: {
  'status':'dependency-edge-proof-gated-no-code',
  'strategy':'Choose one observed redundant edge outside the completed experimental E3/Combined candidate; E3 is not active in frozen R unless explicitly composed. Preserve actual issued RAW/WAR/WAW visibility, destination stages, query availability, host reads, semantic signals, error cleanup and address/allocator reuse. A worker idle wait alone never proves a removable GPU wait.',
  'acceptance':['Name the exact edge, producer/consumer and critical-path wait interval','Prove alternative ordered visibility for every affected consumer and terminal failure path','Independent ownership/synchronization design review passes before any wait/barrier change'],
  'tests':['Existing queue-barrier-reuse/completion/timeline/native tests','Cross-queue/host/query/address-reuse and poison/cancel cases; no global wait suppression'],
  'interactions':[6,7,10,11,12]}
}


def main():
    inventory=json.loads(SOURCE.read_text())
    precedents={x['number']:x for x in json.loads(PRECEDENTS.read_text())['items']}
    assessment={x['number']:x for x in json.loads(ASSESSMENT.read_text())['items']}
    items=[]
    for source in inventory['items']:
        n=source['number']; design=DESIGNS[n]
        item=dict(number=n,title=source['title'],source=source['currentSource'],
                  existingWork=source['sourceObservation'],missingEvidence=source['missingEvidence'],
                  requiredBoundary=source['requiredBoundary'],risk=assessment[n]['risk'],
                  sourceReferences=precedents[n]['sourceIds'],**design)
        item.update(dependencyMeaning='Interactions require re-review; they are not permission to enable all related changes together.',
                    designStage='Exact source capsules where named; broader missing-target/ownership/pass designs remain gated where stated',
                    codeActivationAutomatic=False,FPSBenefitEstablished=False,
                    stopRule='Any unclosed correctness/lifetime counterexample, changed parent, failed check or unclear measurement stops this module. Preserve failure evidence; no automatic replay.',
                    rollback='Prepared source module: exact reverse patch only against its postimage, refresh mtimes and rebuild all affected headers. No-code module: active product remains unchanged; no invented reverse patch.')
        directory=HERE/'queue'/f'{n:02d}';directory.mkdir(parents=True,exist_ok=True)
        (directory/'module.json').write_text(json.dumps(item,ensure_ascii=False,indent=2)+'\n')
        body=f"# {n}. {source['title']}\n\n상태: `{design['status']}`\n\n{design['strategy']}\n\n## 코드화/실행 조건\n\n"+'\n'.join('- '+x for x in design['acceptance'])
        body+='\n\n## 검증\n\n'+'\n'.join('- '+x for x in design['tests'])+'\n\n'+item['stopRule']+'\n\n'+item['rollback']+'\n'
        (directory/'DESIGN.md').write_text(body)
        items.append({'number':n,'title':source['title'],'status':design['status'],'file':str((directory/'module.json').relative_to(HERE))})
    queue={'schemaVersion':1,'status':'prepared-not-activated','scope':'All original13 work groups; nine new source capsules across eight groups, original1 already implemented as Small; four groups and broader11b have detailed design boundaries without source code.',
           'selectedParent':'R; Small remains unpromoted','runtimeDefaults':'diagnosticsOFF allocator32; current protected R/Small apps untouched',
           'humanCueRequiredForActivation':True,
           'beforeFirstActivation':['Finish the separately authorized frozen R/Small forward8/reverse8 or obtain explicit superseding direction','Choose/pin the exact parent source; never fuzzy-apply or package a mismatched raw library','Confirm no other source/build/storage job or benchmark overlaps','Recheck independent review and exact payload/patch hashes'],
           'firstCodeModuleOrder':['11a-typed-frame-discard','08a-conservative-rebind','06-success-notify','07-signal-order-proof','02-layout-policy','03-owned-replay-chain','04-compact-cpu-state','08b-partial-group-replay','09-snapshot-unlocked-retain'],
           'sameFileComposition':{
               '06-then-07':['06-success-notify:R-and-Small','07-signal-order-proof:after06'],
               '07-then-06':['07-signal-order-proof:R-and-Small','06-success-notify:after07'],
               '02-then-04':['02-layout-policy:R-and-Small','04-compact-cpu-state:after02'],
               '04-then-02':['04-compact-cpu-state:R-and-Small','02-layout-policy:after04'],
               '08b-then-09':['08b-partial-group-replay:R-and-Small','09-snapshot-unlocked-retain:after08b'],
               '09-then-08b':['09-snapshot-unlocked-retain:R-and-Small','08b-partial-group-replay:after09'],
               'rule':'Exact staged full-file hashes only; never apply two baseline patches with fuzz.'},
           'equivalentCompositionPairs':[['06-then-07','07-then-06'],['02-then-04','04-then-02'],['08b-then-09','09-then-08b']],
           'perCodeModuleSequence':['verify inputs','apply exact forward patch in single active lane','related CPU/syntax checks','incremental build with correct header timestamps','bounded functional GPU checks','isolated signed app/closure and actual runtime identity','separately authorized like-for-like performance comparison','review outcome; hold/revert/adopt explicitly'],
           'remainingDesignQueue':[5,10,'11b',12,13],
           'remainingDesignMeaning':'5/10/12/13 have no justified exact transform yet;11b is broader pass merging beyond prepared11a. Detailed state tables/counterexamples in remaining-design-boundaries.json.',
           'noCodeGateBehavior':'Record why a group is not yet useful/safe; continue independent groups. A cue is not permission to fabricate evidence or delete waits.',
           'items':items,'inputHashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (SOURCE,PRECEDENTS,ASSESSMENT)},
           'notIncluded':['new product feature toggles','new collector suite','old-app/payload retirement','stable Release/Homebrew/default branch change','foreign projects']}
    (HERE/'QUEUE.json').write_text(json.dumps(queue,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'groups':len(items),'newSourceModules':9,'activation':False}))


if __name__=='__main__':main()
