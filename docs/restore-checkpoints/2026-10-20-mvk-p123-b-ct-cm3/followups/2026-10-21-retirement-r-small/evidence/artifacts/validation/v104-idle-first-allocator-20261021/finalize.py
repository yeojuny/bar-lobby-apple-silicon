from pathlib import Path
import json, hashlib, datetime

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
read = lambda p: json.loads(Path(p).read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
review = read(O/'independent-final-performance-review.json')
assert not review.get('findings', [])
summary, completion, before = read(O/'comparison-summary.json'), read(O/'completion.json'), read(O/'before.json')
assert summary['groups']['R']['changeFromQPercent'] > 0
assert len(summary['executionOrder']) == 4
for row in summary['executionOrder']: assert sha(row['receipt']) == row['receiptSHA256']
for rel, h in read(O/'review-pins.json').items(): assert sha(R/rel) == h
report = Path(completion['report']); assert sha(report) == completion['reportSHA256']
p = R/'artifacts/runtime/v104-local-candidate.json'
previous = read(p); assert previous == before['currentCandidate'] and previous['currentCandidate'] == 'Q'
decision = dict(createdAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
    humanInstruction='Q 기준으로 다음 개선점 찾아서 구현하고 독립 검수',
    previousCandidate='Q', selectedCandidate='R', app=before['RApp'],
    basis='Human cumulative-work preference; CPU1027/native6/package/source reviews passed; observed matched Metal4 mean +0.845833%.',
    limitations='n2 per app and R run-to-run variation; no established causal/peak-memory/other-Mac benefit.',
    independentReview=dict(path=str(O/'independent-final-performance-review.json'),sha256=sha(O/'independent-final-performance-review.json')),
    comparison=dict(path=str(O/'comparison-summary.json'),sha256=sha(O/'comparison-summary.json')),
    previousCandidatePreserved=True, earlierCPreserved=True, formalPublication=False)
(O/'R-next-iteration-selection.json').write_text(json.dumps(decision,indent=2)+'\n')
selected = dict(previous)
selected.update(status='R-selected-for-next-cumulative-work', currentCandidate='R', app=before['RApp'],
    previousCandidate=dict(candidate='Q',app=before['QApp'],purpose='comparison and rollback; preserved'),
    retainedEarlierBaseline=previous.get('previousCandidate'),
    selectionDecision=dict(path=str(O/'R-next-iteration-selection.json'),sha256=sha(O/'R-next-iteration-selection.json')),
    formalPublication=False)
p.write_text(json.dumps(selected,indent=2)+'\n')
completion.update(status='R-implemented-validated-independently-reviewed-and-compared',
    selectedWorkingCandidate='R', candidatePromoted=True, promotionScope='local cumulative work only',
    formalPublication=False, previousQPreserved=True)
(O/'completion.json').write_text(json.dumps(completion,indent=2)+'\n')
names = ['independent-source-review.json','independent-readiness-review.json','independent-final-performance-review.json',
         'comparison-summary.json','completion.json','R-next-iteration-selection.json','performance/outcome.json',
         'R-package.json','R-build.json','allocator-32/completion.json','allocator-32/cpu-Q-oracle.json',
         'test-executable-cleanup-completion.json','os-context.json','metal3-history-answer.json']
bindings = {name:dict(path=str(O/name),sha256=sha(O/name)) for name in names}
bindings['report'] = dict(path=str(report),sha256=sha(report))
bindings['selectedCandidate'] = dict(path=str(p),sha256=sha(p))
(O/'coordinator-completion.json').write_text(json.dumps(dict(status='complete',
    completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), selectedWorkingCandidate='R',
    selectedApp=before['RApp'], previousQAndCPreserved=True, sourceBuild='R frozen', formalPublication=False,
    groups=summary['groups'], sessions=4, cleanup=summary['cleanup'], osSwVers=summary['osSwVers'],
    screenRestored=True, awakeReleased=True, bindings=bindings),indent=2)+'\n')
print('R selected for subsequent local cumulative work; Q/C retained; final reviews/results bound.')
