from pathlib import Path
import hashlib, importlib.util, json, shutil, subprocess

ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
def module(name,relative):
    spec=importlib.util.spec_from_file_location(name,ROOT/relative)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
m=module('package_helpers','tools/package-metal4-bar-candidate.py')
c=module('closure_helpers','tools/run95-package-stack.py')
sha,inventory,run=m.sha,m.inventory,m.run
before=json.loads((OUT/'before.json').read_text())
pins=json.loads((OUT/'review-pins.json').read_text())
builds=json.loads((OUT/'native-build.json').read_text())
assert len(builds)==2 and all(b['exitCode']==0 for b in builds)
for rel,h in pins.items():assert sha(ROOT/rel)==h,rel
for rel,h in before['protectedPins'].items():assert sha(ROOT/rel)==h,rel
parent=ROOT/before['parentApp']
app=ROOT/'artifacts/runtime/v104-drawable-size-candidate-20261020/BAR.app'
assert not app.parent.exists()
old=inventory(parent)
assert old==json.loads((ROOT/'artifacts/validation/v104-c-reg-20261020/candidate-inventory.json').read_text())
run('/usr/bin/codesign','--verify','--deep','--strict',str(parent))
app.parent.mkdir();run('/bin/cp','-cR',str(parent),str(app));assert inventory(app)==old
engines=[]
for lane,info in before['lanes'].items():
    build=next(x for x in builds if x['lane']==lane)
    raw=Path(build['rawPath']);assert sha(raw)==build['rawSHA256']
    rel='Contents/Resources/bundled-assets/engine/'+info['version']+'/spring'
    previous=parent/rel;target=app/rel
    assert m.text_sha(ROOT/info['rawBackup'])==m.text_sha(previous),'Baseline executable differs: '+lane
    previous_loads=c.loads(previous);previous_rpaths=c.rpaths(previous)
    names={Path(n).name:n for n in previous_loads};assert len(names)==len(previous_loads)
    shutil.copy2(raw,target)
    for load in c.loads(target):
        if load in previous_loads:continue
        replacement=names.get(Path(load).name)
        assert replacement and replacement.startswith('@rpath/'),load
        run('/usr/bin/install_name_tool','-change',load,replacement,str(target))
    for path in c.rpaths(target):run('/usr/bin/install_name_tool','-delete_rpath',path,str(target))
    for path in previous_rpaths:run('/usr/bin/install_name_tool','-add_rpath',path,str(target))
    run('/usr/bin/codesign','--force','--sign','-',str(target))
    assert c.loads(target)==previous_loads and c.rpaths(target)==previous_rpaths
    assert m.text_sha(raw)==m.text_sha(target)
    engines.append({'lane':lane,'relativePath':rel,'rawSHA256':sha(raw),'packagedSHA256':sha(target),'textSHA256':m.text_sha(target),'priorPackagedSHA256':sha(previous),'loads':previous_loads,'rpaths':previous_rpaths})
roots=[app/e['relativePath'] for e in engines]
edges=c.closure(roots,app)
(OUT/'dependency-closure.json').write_text(json.dumps(edges,indent=2)+'\n')
run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app))
run('/usr/bin/codesign','--verify','--deep','--strict',str(app))
assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR')
after=inventory(app);assert set(after)==set(old)
changed=sorted(k for k in old if old[k]!=after[k])
assert set(changed)=={e['relativePath'] for e in engines}|{'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'},changed
assert inventory(parent)==old
for rel,h in pins.items():assert sha(ROOT/rel)==h,rel
for rel,h in before['protectedPins'].items():assert sha(ROOT/rel)==h,rel
for name,data in [('parent-inventory.json',old),('candidate-inventory.json',after)]:
    (OUT/name).write_text(json.dumps(data,sort_keys=True,indent=2)+'\n')
receipt={'status':'signed-local-cumulative-candidate','app':str(app),'parent':str(parent),'entries':len(after),'changedFiles':changed,'engines':engines,'sourcePins':pins,'deepStrictSignatureVerified':True,'dependencyClosureEdges':len(edges),'translationStackAndLauncherCodeUnchanged':True,'retainedPriorRawEngines':True,'versionMetadata':'1.0.3 retained; local v1.0.4 cumulative candidate','included':'P1/P2/P3+B+C-T+C-M3+C-REG plus narrow live window/drawable size query in both engines','independentReview':'pending','gameExecuted':False,'installed':False,'formalReleasePublished':False}
(OUT/'package-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({k:v for k,v in receipt.items() if k not in ['sourcePins','engines']},ensure_ascii=False))
