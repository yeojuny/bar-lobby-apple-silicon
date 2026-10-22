from pathlib import Path
import json,importlib.util,shutil
ROOT=Path(__file__).resolve().parents[3];OUT=Path(__file__).resolve().parent

def module(name,rel):
 spec=importlib.util.spec_from_file_location(name,ROOT/rel);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
m=module('mvk_helpers','tools/package-metal4-bar-candidate.py');c=module('closure_helpers','tools/run95-package-stack.py')
sha,inventory,run=m.sha,m.inventory,m.run
read=lambda p:json.loads(p.read_text())
def write(p,d):p.write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
validation=read(OUT/'validation-summary.json');review=read(OUT/'independent-review-common.json')
assert review['status']=='review-complete-no-actionable-findings' and not review['findings']
assert review['reviewPins']==validation['sourcePins']
for n,pin in validation['sourcePins'].items():assert sha(ROOT/n)==pin,n
raw=ROOT/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib';assert sha(raw)==validation['rawLibrarySHA256']==review['observations']['currentRawLibrarySHA256']
parent=ROOT/'artifacts/runtime/v104-performance-ab-candidate-20261020/BAR.app'
baseline=ROOT/'artifacts/runtime/healthbar-standalone-1.0.3-20261018/app-builder-output/mac-arm64/BAR.app'
p1=ROOT/'artifacts/runtime/v104-performance-candidate-20261020/BAR.app'
app=ROOT/'artifacts/runtime/v104-descriptor-candidate-20261020/BAR.app'
assert not app.parent.exists(),'Existing result must be inspected before retry'
old=inventory(parent);base=inventory(baseline);p1before=inventory(p1)
assert old==read(ROOT/'artifacts/validation/v104-followup-ab-20261020/ab-candidate-inventory.json')
assert base==read(ROOT/'artifacts/validation/v104-performance-comparison-20261020/parent-inventory.json')
assert p1before==read(ROOT/'artifacts/validation/v104-performance-comparison-20261020/candidate-inventory.json')
run('/usr/bin/codesign','--verify','--deep','--strict',str(parent));app.parent.mkdir();run('/bin/cp','-cR',str(parent),str(app));assert inventory(app)==old
rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib';target=app/rel
assert c.loads(raw)==c.loads(parent/rel) and c.rpaths(raw)==c.rpaths(parent/rel)==[]
assert all(s.startswith(('/System/Library/','/usr/lib/')) for s in c.loads(raw))
shutil.copy2(raw,target);run('/usr/bin/install_name_tool','-id',c.dylib_id(parent/rel),str(target));run('/usr/bin/codesign','--force','--sign','-',str(target))
assert c.loads(target)==c.loads(parent/rel) and c.dylib_id(target)==c.dylib_id(parent/rel) and m.text_sha(raw)==m.text_sha(target)
roots=[app/'Contents/Resources/bundled-assets/engine'/v/'spring' for v in ('2026.07.04','2026.09.01-24-g01efdf4 master')]
edges=c.closure(roots,app);write(OUT/'dependency-closure.json',edges)
run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app));run('/usr/bin/codesign','--verify','--deep','--strict',str(app))
assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR')
after=inventory(app);assert set(after)==set(old)
changed=sorted(k for k in old if old[k]!=after[k]);assert set(changed)=={rel,'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'},changed
assert inventory(parent)==old and inventory(baseline)==base and inventory(p1)==p1before
before=read(OUT/'before.json');excluded=before['selectedEdits']
for name,pin in before['files'].items():
 if name not in excluded:assert sha(ROOT/name)==pin,name
for n,pin in validation['sourcePins'].items():assert sha(ROOT/n)==pin,n
write(OUT/'candidate-inventory.json',after)
result={'status':'signed-local-cumulative-candidate','app':str(app),'parent':str(parent),'entries':len(after),'changedFromAB':changed,
 'included':'P1/P2/P3+B+C-T+C-M3; A excluded and vertex cache not reintroduced','rawLibrarySHA256':sha(raw),'packagedLibrarySHA256':sha(target),
 'sourcePins':validation['sourcePins'],'deepStrictSignatureVerified':True,'dependencyClosureEdges':len(edges),'enginesAndLauncherCodeUnchanged':True,
 'frozenV103AndPriorTwoCandidateInventoriesUnchanged':True,'protectedRecordedPinsExact':validation['protectedRecordedPinsExact'],
 'independentReview':'Astra High complete, no actionable findings','priorValidation':{'cpuOn':629,'cpuOff':134,'productionSyntaxOnOff':4,'nativeSuite':6,'commonBackendCases':['Metal3 6 cycles plus graphics','Metal4 6 cycles plus graphics']},
 'versionMetadata':'1.0.3 retained; local v1.0.4 candidate designation only','gameExecuted':False,'FPSBenefitUnmeasured':True,'installed':False,'published':False}
write(OUT/'package-receipt.json',result);print(json.dumps({k:v for k,v in result.items() if k!='sourcePins'}))
