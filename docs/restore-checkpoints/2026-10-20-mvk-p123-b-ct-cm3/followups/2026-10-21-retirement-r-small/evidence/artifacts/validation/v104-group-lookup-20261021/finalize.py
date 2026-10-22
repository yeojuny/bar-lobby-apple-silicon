from pathlib import Path
import json,hashlib,datetime
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
review=read(O/'independent-readiness-review.json');assert review['actionableFindings']==[] and 'pending' not in review['status']
c=read(O/'completion.json');report=Path(c['report']);assert sha(report)==c['reportSHA256']==review['reviewedReportSHA256']
assert all(sha(R/p)==h for p,h in read(O/'R/source-pins.json').items())
before=read(O/'before.json');candidate=R/'artifacts/runtime/v104-local-candidate.json';assert read(candidate)==before['currentCandidate']
assert read(O/'derived-cleanup-completion.json')['allAbsent']
assert sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib')==read(O/'R/completion.json')['rawSHA256']
assert sha(R/'build/metal4-mvk-20261002/CMakeCache.txt')==before['CMakeCacheSHA256']
for role in ['R','Combined']:
 package=read(O/(role+'-next-package.json'));relative=before['libraryRelativePath'];assert sha(Path(package['app'])/relative)==package['packagedSHA256']
 assert sha(Path(before['apps'][role])/relative)==before['packageSHA256'][role]
c.update(status='both-candidates-implemented-validated-independently-reviewed-and-packaged',independentReadinessReviewSHA256=sha(O/'independent-readiness-review.json'),independentSourceReviewSHA256=sha(O/'independent-source-review.json'),candidatePromoted=False)
(O/'completion.json').write_text(json.dumps(c,indent=2)+'\n')
pending=R/'artifacts/runtime/v104-group-locator-candidates.json';p=read(pending);p.update(status='independently-verified-ready-for-comparison-not-promoted',completionSHA256=sha(O/'completion.json'));pending.write_text(json.dumps(p,indent=2)+'\n')
names=['root-source-build-grant.json','before.json','application.json','R-next.patch','Combined-next.patch','group-cache-before.inc','group-cache-after.inc','packages.json','R-next-package.json','Combined-next-package.json','R-next-inventory.json','Combined-next-inventory.json','R/source-pins.json','Combined/source-pins.json','R/completion.json','Combined/completion.json','independent-source-review.json','independent-readiness-review.json','derived-cleanup-selection.json','derived-cleanup-completion.json','completion.json']
bindings={name:dict(path=str(O/name),sha256=sha(O/name)) for name in names}
for label,path in [('report',report),('selectedCandidate',candidate),('newCandidates',pending),('fixture',R/'tools/tests/metal4-group-locator-cpu.cpp')]:bindings[label]=dict(path=str(path),sha256=sha(path))
(O/'coordinator-completion.json').write_text(json.dumps(dict(status='complete',completedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),samePatchOnTwoBaselines=True,selectedCandidate='R',currentSourceBuild='R-plus-group-locator',apps={k:v['app'] for k,v in c['packages'].items()},FPSMeasured=False,gameSessions=0,countLimit=32,diagnosticsCompile=0,extraRecordingMetadataBytes=96,formalPublication=False,bindings=bindings),indent=2)+'\n')
print('Both candidates complete; independent source/readiness reviews bound; original R remains selected; no FPS claim.')
