from pathlib import Path
import json,hashlib,datetime
O=Path(__file__).resolve().parent;R=O.parents[2]
read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
summary=read(O/'comparison-summary.json');completion=read(O/'completion.json');report=Path(completion['report'])
assert sha(report)==completion['reportSHA256']
assert (summary['totalCompletedSessions'],summary['primarySessions'],summary['referenceSessions'])==(16,8,8)
assert len(summary['executionOrder'])==8
assert [r['sourcePhase'] for r in summary['executionOrder']]==['fresh-metal4']*4+['fresh-metal3-retest']*4
assert [r['role'] for r in summary['executionOrder']]==['C','Q','Q','C']*2
for row in summary['executionOrder']:assert sha(row['receipt'])==row['receiptSHA256']
reviews=['independent-source-review.json','independent-readiness-review.json','independent-final-performance-review.json']
for f in reviews:assert (O/f).is_file(),f
bindings={f:dict(path=str(O/f),sha256=sha(O/f)) for f in reviews+['comparison-summary.json','completion.json','additional-metal3-retest-grant.json','performance-idle-metal3-retest/outcome.json','performance-idle-metal4/outcome.json','performance/outcome.json']}
bindings['report']=dict(path=str(report),sha256=sha(report))
d=dict(status='complete-C-Q-fresh-metal3-metal4-comparison',completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),primarySessions=8,referenceSessions=8,totalCompletedSessions=16,bindings=bindings,groups=summary['groups'],sourceAndBuild='Q frozen, not promoted',selectedCandidate='C unchanged',candidatePromoted=False,sourceAndAppInventoriesVerified=summary['sourceBuildQPreserved'] and summary['appsCQInventoriesExact'],userProfilesAndLauncherExact=summary['userProfilesAndLauncherExact'],screenRestored=summary['screenRestored'],awakeReleased=summary['awakeReleased'],cleanup=summary['cleanup'],limits=summary['limitations'])
(O/'coordinator-completion.json').write_text(json.dumps(d,indent=2)+'\n')
print('Final coordinator record bound to source/readiness/performance reviews and eight fresh results.')
