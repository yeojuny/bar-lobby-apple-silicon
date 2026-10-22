import importlib.util, json, shutil, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent

def module(name,rel):
 spec=importlib.util.spec_from_file_location(name,ROOT/rel)
 m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
m=module('mvk_helpers','tools/package-metal4-bar-candidate.py')
c=module('closure_helpers','tools/run95-package-stack.py')
sha,inventory,run=m.sha,m.inventory,m.run
read=lambda p:json.loads(p.read_text())
def write(p,d):p.write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
parent=ROOT/'artifacts/runtime/v104-performance-candidate-20261020/BAR.app'
baseline=ROOT/'artifacts/runtime/healthbar-standalone-1.0.3-20261018/app-builder-output/mac-arm64/BAR.app'
app=ROOT/'artifacts/runtime/v104-performance-ab-candidate-20261020/BAR.app'
assert not app.parent.exists(),'Existing candidate must be inspected before retry'
receipt=read(OUT/'completion.json')
source=ROOT/receipt['B']['source'];raw=ROOT/receipt['validation']['library']
assert sha(source)==receipt['B']['sourceSHA256'] and sha(raw)==receipt['validation']['librarySHA256']
old=inventory(parent);base=inventory(baseline)
assert old==read(ROOT/'artifacts/validation/v104-performance-comparison-20261020/candidate-inventory.json')
assert base==read(ROOT/'artifacts/validation/v104-performance-comparison-20261020/parent-inventory.json')
run('/usr/bin/codesign','--verify','--deep','--strict',str(parent))
app.parent.mkdir()
run('/bin/cp','-cR',str(parent),str(app))
assert inventory(app)==old
rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
target=app/rel;prior=parent/rel
assert c.loads(raw)==c.loads(prior) and all(x.startswith(('/System/Library/','/usr/lib/')) for x in c.loads(raw))
assert c.rpaths(raw)==c.rpaths(prior)==[]
assert run('/usr/bin/lipo','-archs',str(raw)).strip()=='arm64'
shutil.copy2(raw,target)
run('/usr/bin/install_name_tool','-id',c.dylib_id(prior),str(target))
assert c.loads(target)==c.loads(prior) and c.dylib_id(target)==c.dylib_id(prior)
run('/usr/bin/codesign','--force','--sign','-',str(target))
assert m.text_sha(raw)==m.text_sha(target)
roots=[app/'Contents/Resources/bundled-assets/engine'/v/'spring' for v in ('2026.07.04','2026.09.01-24-g01efdf4 master')]
edges=c.closure(roots,app)
write(OUT/'ab-dependency-closure.json',edges)
run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app))
run('/usr/bin/codesign','--verify','--deep','--strict',str(app))
assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR')
after=inventory(app)
assert set(after)==set(old)
changes=sorted(k for k in old if old[k]!=after[k])
assert set(changes)=={rel,'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'},changes
assert inventory(parent)==old and inventory(baseline)==base
for name,digest in read(OUT/'b-before.json')['files'].items():
 if name==receipt['B']['source']:continue
 assert sha(ROOT/name)==digest,name
write(OUT/'ab-candidate-inventory.json',after)
result={'app':str(app),'parent':str(parent),'baseline':str(baseline),'entries':len(after),'changedFromP1P2P3':changes,
 'included':'Cumulative P1/P2/P3 engines plus B small CPU scratch arrays; A excluded for actual-use reasons',
 'rawMVKSHA256':sha(raw),'packagedMVKSHA256':sha(target),'sourceSHA256':sha(source),'rawAndPackagedExecutableCodeIdentical':True,
 'P1P2P3EnginesUnchanged':True,'launcherExecutableCodeUnchanged':True,'parentAndBaselineFullInventoriesUnchanged':True,
 'protectedPinsExact':56,'dependencyClosureEdges':len(edges),'deepStrictSignatureVerified':True,
 'gameExecuted':False,'installed':False,'published':False,'CStartedHere':False,
 'versionMetadata':'1.0.3 retained; local v1.0.4 cumulative candidate designation only',
 'priorValidation':{'GPUPrepassPassed':29,'CPUStorageCases':6,'ASanUBSan':True},'FPSBenefitUnmeasured':True}
write(OUT/'ab-package-receipt.json',result)
print(json.dumps(result))
