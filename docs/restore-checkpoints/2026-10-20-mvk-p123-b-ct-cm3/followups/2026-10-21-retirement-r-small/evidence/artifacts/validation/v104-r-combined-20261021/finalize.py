from pathlib import Path
import json, hashlib, datetime

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
read = lambda p: json.loads(Path(p).read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
review = read(O/'independent-final-performance-review.json')
assert not review['actionableFindings'] and review['status'] == 'passed-evidence-integrity-and-arithmetic-review'
summary, completion, before = read(O/'comparison-summary.json'), read(O/'completion.json'), read(O/'before.json')
assert len(summary['executionOrder']) == 8
assert [r['role'] for r in summary['executionOrder']] == ['R','Combined','Combined','R','Combined','R','R','Combined']
for row in summary['executionOrder']: assert sha(row['receipt']) == row['receiptSHA256']
for rel, h in read(O/'review-pins.json').items(): assert sha(R/rel) == h
assert read(R/'artifacts/runtime/v104-local-candidate.json') == before['currentCandidate']
assert before['currentCandidate']['currentCandidate'] == 'R'
report = Path(completion['report']); assert sha(report) == completion['reportSHA256']
assert sha(report) == review['reviewedReportSHA256']
completion.update(status='R-combined-implemented-validated-independently-reviewed-and-compared',
    selectedCandidate='R', combinedCandidatePreserved=True, sourceBuild='Combined frozen',
    independentPerformanceReviewPending=False, candidatePromoted=False)
(O/'completion.json').write_text(json.dumps(completion,indent=2)+'\n')
names = ['independent-source-review.json','independent-readiness-review.json','independent-final-performance-review.json',
         'comparison-summary.json','completion.json','performance/outcome.json','combined-package.json','combined-build.json',
         'cpu-complete.json','registration-complete.json','visibility/completion.json','queue-barrier/completion.json',
         'allocator-32/completion.json','gpu-complete.json','ownership-gpu-complete.json',
         'derived-cleanup-selection.json','derived-cleanup-completion.json','application-stages.json','combined-source-pins.json']
bindings = {name:dict(path=str(O/name),sha256=sha(O/name)) for name in names}
bindings['report'] = dict(path=str(report),sha256=sha(report))
candidate = R/'artifacts/runtime/v104-local-candidate.json'
bindings['selectedCandidate'] = dict(path=str(candidate),sha256=sha(candidate))
(O/'coordinator-completion.json').write_text(json.dumps(dict(status='complete',
    completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), selectedWorkingCandidate='R',
    selectedApp=before['RApp'], combinedApp=before['CombinedApp'], sourceBuild='Combined frozen',
    previousRSourceAndRawPreserved=True, QAndCAppsPreserved=True, formalPublication=False,
    groups=summary['groups'], sessions=8, countLimit=32, diagnosticsCompile=0, diagnosticsRuntime=False,
    cleanup=summary['cleanup'], standaloneCleanup=read(O/'derived-cleanup-completion.json'),
    osSwVers=summary['osSwVers'], screenRestored=True, awakeReleased=True, bindings=bindings),indent=2)+'\n')
print('All eight R/Combined results and independent reviews bound; baseline R and complete combined candidate retained.')
