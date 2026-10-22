from pathlib import Path
import importlib.util,json,shutil
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text())
def module(name,rel):
 s=importlib.util.spec_from_file_location(name,R/rel);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('pkg','tools/package-metal4-bar-candidate.py');c=module('closure','tools/run95-package-stack.py');before=read(O/'before.json');rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
apps={}
for role,slug in [('R','r'),('Combined','r-combined')]:
 completed=read(O/role/'completion.json');assert completed['status']=='passed'
 parent=Path(before['apps'][role]);original=m.inventory(parent);assert original==read(R/'artifacts/validation/v104-r-combined-reverse-20261021'/(role+'-inventory.json'))
 app=R/f'artifacts/runtime/v104-{slug}-group-locator-candidate-20261021/BAR.app';assert not app.parent.exists()
 m.run('/usr/bin/codesign','--verify','--deep','--strict',str(parent));app.parent.mkdir();m.run('/bin/cp','-cR',str(parent),str(app));assert m.inventory(app)==original
 raw=O/(role+'-next-raw-MoltenVK.dylib');assert m.sha(raw)==completed['rawSHA256'];target=app/rel
 assert c.loads(raw)==c.loads(parent/rel) and c.rpaths(raw)==[]
 shutil.copy2(raw,target);m.run('/usr/bin/install_name_tool','-id',c.dylib_id(parent/rel),str(target));m.run('/usr/bin/codesign','--force','--sign','-',str(target));assert m.text_sha(raw)==m.text_sha(target)
 edges=c.closure([app/'Contents/Resources/bundled-assets/engine'/v/'spring' for v in ['2026.07.04','2026.09.01-24-g01efdf4 master']],app)
 m.run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app));m.run('/usr/bin/codesign','--verify','--deep','--strict',str(app))
 after=m.inventory(app);changed=sorted(k for k in original if original[k]!=after[k]);assert set(changed)=={rel,'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'};assert set(after)==set(original) and len(after)==1194
 assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR');assert m.inventory(parent)==original
 (O/(role+'-next-inventory.json')).write_text(json.dumps(after,indent=2)+'\n')
 apps[role]=dict(app=str(app),parent=str(parent),entries=len(after),rawSHA256=m.sha(raw),packagedSHA256=m.sha(target),changedFiles=changed,closureEdges=len(edges),deepStrictSignature=True,displayedVersion='1.0.3',localCandidate='v1.0.4',diagnosticsCompile=0,countLimit=32,FPSMeasured=False,sourcePins=read(O/role/'source-pins.json'),patchSHA256=m.sha(O/(role+'-next.patch')))
 (O/(role+'-next-package.json')).write_text(json.dumps(apps[role],indent=2)+'\n');print(role,app,apps[role]['packagedSHA256'],flush=True)
(O/'packages.json').write_text(json.dumps(apps,indent=2)+'\n')
