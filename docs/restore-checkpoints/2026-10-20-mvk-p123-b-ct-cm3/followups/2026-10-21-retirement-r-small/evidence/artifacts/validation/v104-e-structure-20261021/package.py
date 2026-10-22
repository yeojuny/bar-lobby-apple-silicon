from pathlib import Path
import importlib.util,json,shutil,sys,hashlib,subprocess
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;label=sys.argv[1];assert label in ['E32','E64'];count=int(label[1:]);B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
def module(name,rel):
 s=importlib.util.spec_from_file_location(name,R/rel);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('pkg','tools/package-metal4-bar-candidate.py');c=module('closure','tools/run95-package-stack.py')
proposal=json.loads((O/'proposal.json').read_text());grant=json.loads((O/'root-source-build-grant.json').read_text());pins={f:m.sha(B/f) for f in proposal['originalPins']}
assert pins==proposal[label+'Pins'];assert m.sha(R/'build/metal4-mvk-20261002/CMakeCache.txt')==grant['CMakeCacheSHA256']
assert json.loads((O/f'allocator-{count}/completion.json').read_text())['status']=='passed'
assert json.loads((O/'gpu-complete.json').read_text())['status']=='passed'
parent=R/'artifacts/runtime/v104-lookup-descriptor-release-20261020/BAR.app';app=Path(grant[label+'App']);assert not app.parent.exists()
old=m.inventory(parent);assert old==json.loads((R/'artifacts/validation/v104-lookup-descriptor-20261020/release-inventory.json').read_text());assert len(old)==1194
m.run('/usr/bin/codesign','--verify','--deep','--strict',str(parent));app.parent.mkdir();m.run('/bin/cp','-cR',str(parent),str(app));assert m.inventory(app)==old
rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib';raw=R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib';target=app/rel
assert c.loads(raw)==c.loads(parent/rel) and c.rpaths(raw)==[]
shutil.copy2(raw,O/f'{label}-raw-MoltenVK.dylib');shutil.copy2(raw,target);m.run('/usr/bin/install_name_tool','-id',c.dylib_id(parent/rel),str(target));m.run('/usr/bin/codesign','--force','--sign','-',str(target));assert m.text_sha(raw)==m.text_sha(target)
edges=c.closure([app/'Contents/Resources/bundled-assets/engine'/v/'spring' for v in ['2026.07.04','2026.09.01-24-g01efdf4 master']],app)
m.run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app));m.run('/usr/bin/codesign','--verify','--deep','--strict',str(app));after=m.inventory(app);changed=sorted(k for k in old if old[k]!=after[k]);assert set(old)==set(after)
assert set(changed)=={rel,'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'};assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR');assert m.inventory(parent)==old
for f,h in pins.items():
 assert m.sha(B/f)==h;dst=O/'source-states'/label/f;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(B/f,dst)
(O/f'{label}-inventory.json').write_text(json.dumps(after,indent=2)+'\n');(O/f'{label}-source-pins.json').write_text(json.dumps(pins,indent=2)+'\n')
receipt=dict(app=str(app),parent=str(parent),entries=len(after),changedFiles=changed,rawSHA256=m.sha(raw),packagedSHA256=m.sha(target),strictDeepSignature=True,closureEdges=len(edges),displayedVersion='1.0.3',localCandidate='v1.0.4',allocatorCount=count,diagnosticsCompile=0,sourcePins=pins,CMakeCacheSHA256=grant['CMakeCacheSHA256'],gameExecuted=False,inventory=str(O/f'{label}-inventory.json'),nativeEnginesUnchanged=True)
(O/f'{label}-package.json').write_text(json.dumps(receipt,indent=2)+'\n');print(label,'packaged',len(after),'entries',len(edges),'closure edges',receipt['rawSHA256'],flush=True)
