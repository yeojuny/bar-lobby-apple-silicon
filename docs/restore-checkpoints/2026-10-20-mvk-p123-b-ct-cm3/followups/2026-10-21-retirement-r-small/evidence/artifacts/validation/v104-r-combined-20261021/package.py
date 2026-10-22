from pathlib import Path
import importlib.util,json,shutil
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text())
def module(name,rel):
 s=importlib.util.spec_from_file_location(name,R/rel);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('pkg','tools/package-metal4-bar-candidate.py');c=module('closure','tools/run95-package-stack.py');before=read(O/'before.json')
assert read(O/'combined-build.json')['exitCode']==0 and read(O/'allocator-32/completion.json')['status']=='passed' and read(O/'gpu-complete.json')['status']=='passed' and read(O/'cpu-complete.json')['status']=='passed'
parent=Path(before['RApp']);original=m.inventory(parent);assert original==read(R/'artifacts/validation/v104-idle-first-allocator-20261021/R-inventory.json')
app=Path(before['CombinedApp']);assert not app.parent.exists();m.run('/usr/bin/codesign','--verify','--deep','--strict',str(parent));app.parent.mkdir();m.run('/bin/cp','-cR',str(parent),str(app));assert m.inventory(app)==original
rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib';raw=O/'combined-raw-MoltenVK.dylib';target=app/rel;assert c.loads(raw)==c.loads(parent/rel) and c.rpaths(raw)==[];shutil.copy2(raw,target);m.run('/usr/bin/install_name_tool','-id',c.dylib_id(parent/rel),str(target));m.run('/usr/bin/codesign','--force','--sign','-',str(target));assert m.text_sha(raw)==m.text_sha(target)
edges=c.closure([app/'Contents/Resources/bundled-assets/engine'/v/'spring' for v in ['2026.07.04','2026.09.01-24-g01efdf4 master']],app);m.run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app));m.run('/usr/bin/codesign','--verify','--deep','--strict',str(app));after=m.inventory(app);changed=sorted(k for k in original if original[k]!=after[k]);assert set(changed)=={rel,'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'};assert set(after)==set(original) and len(after)==1194;assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR');assert m.inventory(parent)==original
for label,inventory in [('R',original),('Combined',after)]:(O/(label+'-inventory.json')).write_text(json.dumps(inventory,indent=2)+'\n')
row=dict(role='Combined',app=str(app),parent=str(parent),entries=len(after),rawSHA256=m.sha(raw),packagedSHA256=m.sha(target),changedFiles=changed,closureEdges=len(edges),deepStrictSignature=True,displayedVersion='1.0.3',localCandidate='v1.0.4',diagnosticsCompile=0,sourcePins=read(O/'combined-source-pins.json'),productDelta='R plus D E1 E2 E3; Q last-use reset and R idle-first retained; count32/growth2MiB/available8/idle64MiB unchanged',sourcePatchSHA256=m.sha(O/'combined-from-R.patch'))
(O/'combined-package.json').write_text(json.dumps(row,indent=2)+'\n');print(json.dumps(row),flush=True)
