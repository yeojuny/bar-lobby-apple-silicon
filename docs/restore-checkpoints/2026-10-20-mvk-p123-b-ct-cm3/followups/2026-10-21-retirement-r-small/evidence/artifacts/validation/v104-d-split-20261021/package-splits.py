from pathlib import Path
import importlib.util,json,shutil
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text())
def module(name,rel):
 s=importlib.util.spec_from_file_location(name,R/rel);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('pkg','tools/package-metal4-bar-candidate.py');c=module('closure','tools/run95-package-stack.py');before=read(O/'before.json');assert read(O/'build-comparison.json')['status']=='completed-four-source-state-builds';assert read(O/'restore-D.json')['sourcePinsExact']
parent=Path(before['CApp']);original=m.inventory(parent);assert original==read(O/'C-inventory.json');dInventory=read(O/'D-inventory.json');reports=[]
for label,slug in [('L','lookup-only'),('S','stats-only-off')]:
 app=R/f'artifacts/runtime/v104-d-split-{slug}-20261021/BAR.app';assert not app.parent.exists();m.run('/usr/bin/codesign','--verify','--deep','--strict',str(parent));app.parent.mkdir();m.run('/bin/cp','-cR',str(parent),str(app));assert m.inventory(app)==original
 rel='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib';raw=O/(label+'-raw-MoltenVK.dylib');target=app/rel;assert c.loads(raw)==c.loads(parent/rel) and c.rpaths(raw)==[];shutil.copy2(raw,target);m.run('/usr/bin/install_name_tool','-id',c.dylib_id(parent/rel),str(target));m.run('/usr/bin/codesign','--force','--sign','-',str(target));assert m.text_sha(raw)==m.text_sha(target)
 edges=c.closure([app/'Contents/Resources/bundled-assets/engine'/v/'spring' for v in ['2026.07.04','2026.09.01-24-g01efdf4 master']],app);m.run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(app));m.run('/usr/bin/codesign','--verify','--deep','--strict',str(app));after=m.inventory(app);changed=sorted(k for k in original if original[k]!=after[k]);assert set(changed)<={rel,'Contents/MacOS/BAR','Contents/_CodeSignature/CodeResources'};assert set(after)==set(original);assert m.text_sha(app/'Contents/MacOS/BAR')==m.text_sha(parent/'Contents/MacOS/BAR');assert m.inventory(parent)==original
 (O/(label+'-inventory.json')).write_text(json.dumps(after,indent=2));row=dict(role=label,app=str(app),entries=len(after),rawSHA256=m.sha(raw),packagedSHA256=m.sha(target),changedFiles=changed,closureEdges=len(edges),deepStrictSignature=True,displayedVersion='1.0.3',localCandidate='v1.0.4',diagnosticsCompile=False,inventoryExactWithC=after==original,inventoryExactWithD=after==dInventory);reports.append(row);(O/(label+'-package.json')).write_text(json.dumps(row,indent=2));print(json.dumps(row),flush=True)
(O/'package-comparison.json').write_text(json.dumps(reports,indent=2))
