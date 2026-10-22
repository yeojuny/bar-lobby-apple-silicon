from pathlib import Path
import json,hashlib,shutil
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';prior=R/'artifacts/validation/v104-r-combined-20261021';sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();read=lambda p:json.loads(Path(p).read_text())
assert read(O/'Combined/completion.json')['status']=='passed'
assert all(sha(R/p)==h for p,h in read(O/'Combined/source-pins.json').items())
rpins=read(R/'artifacts/validation/v104-idle-first-allocator-20261021/R-source-pins.json')
files=sorted(p for p in (prior/'preimage').rglob('*') if p.is_file());assert len(files)==11
for p in files:assert sha(p)==rpins[str(p.relative_to(prior/'preimage'))]
for p in files:
 rel=p.relative_to(prior/'preimage');f=B/rel;target=O/'source-states/Combined-next'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
 shutil.copy2(p,f)
 if str(rel)=='GPUObjects/MVKMetal4PreparedResource.h':shutil.copyfile(O/'R-next.h',f)
 target=O/'source-states/R-next'/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
expected=dict(read(O/'before.json')['sourcePins'])
for rel,h in rpins.items():expected[str((B/rel).relative_to(R))]=sha(B/rel)
assert all(sha(R/p)==h for p,h in expected.items())
(O/'R-expected-source-pins.json').write_text(json.dumps(expected,indent=2)+'\n')
print('Single active lane switched from frozen Combined+locator to R+same locator; 11-file variant states retained.')
