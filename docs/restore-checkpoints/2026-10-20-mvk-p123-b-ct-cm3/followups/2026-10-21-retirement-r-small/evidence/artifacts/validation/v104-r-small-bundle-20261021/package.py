from pathlib import Path
import difflib, importlib.util, json, shutil, hashlib, subprocess, datetime
R=Path(__file__).resolve().parents[3]
O=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text())
def module(name,rel):
    s=importlib.util.spec_from_file_location(name,R/rel);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('small_bundle_pkg','tools/package-metal4-bar-candidate.py')
c=module('small_bundle_closure','tools/run95-package-stack.py')
assert read(O/'validation.json')['status']=='passed'
assert read(O/'header-mtime-rebuild.json')['exitCode']==0
pins=read(O/'candidate-source-pins.json')
assert all(m.sha(R/p)==h for p,h in pins.items())
protected={}
for label,receipt,inventory in [
 ('R','v104-idle-first-allocator-20261021/R-package.json','v104-idle-first-allocator-20261021/R-inventory.json'),
 ('Combined','v104-r-combined-20261021/combined-package.json','v104-r-combined-20261021/Combined-inventory.json'),
 ('RLookup','v104-group-lookup-20261021/R-next-package.json','v104-group-lookup-20261021/R-next-inventory.json'),
 ('CombinedLookup','v104-group-lookup-20261021/Combined-next-package.json','v104-group-lookup-20261021/Combined-next-inventory.json')]:
    p=Path(read(R/'artifacts/validation'/receipt)['app'])
    expected=read(R/'artifacts/validation'/inventory)
    assert m.inventory(p)==expected,label
    protected[label]=(p,expected)
parent,original=protected['R']
app=R/'artifacts/runtime/v104-r-small-bundle-candidate-20261021/BAR.app'
assert not app.parent.exists()
(O/'execution-state.json').write_text(json.dumps(dict(stage='packaging-qualified-candidate',nativeGpuStarted=True,barGameFPS=False),indent=2)+'\n')
m.run('/usr/bin/codesign','--verify','--deep','--strict',str(parent))
app.parent.mkdir()
m.run('/bin/cp','-cR',str(parent),str(app))
assert m.inventory(app)==original
rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
raw=O/'qualified-raw-MoltenVK.dylib'
assert m.sha(raw)==read(O/'validation.json')['rawSHA256']
target=app/rel
assert c.loads(raw)==c.loads(parent/rel) and c.rpaths(raw)==[]
shutil.copy2(raw,target)
m.run('/usr/bin/install_name_tool','-id',c.dylib_id(parent/rel),str(target))
m.run('/usr/bin/codesign','--force','--sign','-',str(target))
assert m.text_sha(raw)==m.text_sha(target)
edges=c.closure([app/'Contents/Resources/bundled-assets/engine'/v/'spring' for v in ['2026.07.04','2026.09.01-24-g01efdf4 master']],app)
m.run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app))
m.run('/usr/bin/codesign','--verify','--deep','--strict',str(app))
after=m.inventory(app)
assert set(after)==set(original) and len(after)==1194
changed=sorted(k for k in original if original[k]!=after[k])
assert set(changed)=={rel,'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'},changed
assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR')
for label,(path,expected) in protected.items():assert m.inventory(path)==expected,label
launcher=R/'sources/bar-lobby'
state={'HEAD':m.run('git','-C',str(launcher),'rev-parse','HEAD').strip(),
       'indexSHA256':m.sha(launcher/'.git/index'),
       'statusSHA256':hashlib.sha256(subprocess.check_output(['git','--no-optional-locks','-C',str(launcher),'status','--porcelain=v1','-z'])).hexdigest()}
assert state==read(O/'launcher-before.json')
assert all(m.sha(R/p)==h for p,h in pins.items())
(O/'candidate-inventory.json').write_text(json.dumps(after,indent=2)+'\n')
(O/'launcher-after.json').write_text(json.dumps(state,indent=2)+'\n')
fixturePins={}
patch=''
for name in ['metal4-prepared-texture-cpu.py','metal4-descriptor-preparation-cpu.py']:
    relpath='tools/tests/'+name
    pre=O/'fixture-preimage'/name
    current=R/relpath
    patch+=''.join(difflib.unified_diff(pre.read_text().splitlines(True),current.read_text().splitlines(True),fromfile='a/'+relpath,tofile='b/'+relpath))
    fixturePins[relpath]={'preimageSHA256':m.sha(pre),'currentSHA256':m.sha(current)}
(O/'fixture-compatibility.patch').write_text(patch)
row=dict(status='frozen-related-validation-passed-awaiting-coordinator-performance',app=str(app),parent=str(parent),
    entries=len(after),rawSHA256=m.sha(raw),packagedSHA256=m.sha(target),changedFiles=changed,
    closureEdges=len(edges),deepStrictSignature=True,launcherCodePreserved=True,engineBytesPreserved=True,
    displayedVersion='1.0.3',localCandidate='v1.0.4',diagnosticsCompile=0,diagnosticsRuntime=0,
    sourcePins=pins,sourcePatchSHA256=m.sha(O/'unit1.patch'),fixturePins=fixturePins,
    fixturePatchSHA256=m.sha(O/'fixture-compatibility.patch'),protectedFourAppsExact=True,
    unit2Applied=False,barGameFPS=False,installed=False,published=False,cleanupExecuted=False,
    headerMtimeRebuildReceiptSHA256=m.sha(O/'header-mtime-rebuild.json'),
    frozenUTC=datetime.datetime.now(datetime.timezone.utc).isoformat())
(O/'package.json').write_text(json.dumps(row,indent=2)+'\n')
(O/'execution-state.json').write_text(json.dumps(dict(stage='frozen-no-further-source-build-gpu-work',nativeGpuCompleted=True,barGameFPS=False,
    packageReceipt=str(O/'package.json'),coordinatorOwnsPerformance=True),indent=2)+'\n')
print(json.dumps({k:v for k,v in row.items() if k not in ['sourcePins','fixturePins']}),flush=True)
