#!/usr/bin/env python3
"""Package one exact MoltenVK build in a recoverable Run95+VBO APFS clone."""
import importlib.util,json,re,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('bundle_inventory',ROOT/'tools/lib/run95_app_transaction.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
sha,inventory=mod.sha,mod.inventory
STAGE=ROOT/'artifacts/runtime/metal4-bar-candidate-20261002'
def run(*args):return subprocess.run(args,check=True,capture_output=True,text=True).stdout
def loads(p):return [v.strip().split(' (compatibility version')[0] for v in run('/usr/bin/otool','-L',str(p)).splitlines()[1:] if v.startswith('\t')]
def text_sha(p):
    import hashlib
    lines=run('/usr/bin/otool','-l',str(p)).splitlines()
    for i,line in enumerate(lines):
        if line.strip()!='sectname __text':continue
        block=lines[i+1:i+7]
        if not any(v.strip()=='segname __TEXT' for v in block):continue
        size=next(int(v.split()[1],16) for v in block if v.strip().startswith('size '))
        offset=next(int(v.split()[1]) for v in block if v.strip().startswith('offset '))
        return hashlib.sha256(p.read_bytes()[offset:offset+size]).hexdigest()
    raise RuntimeError('No Mach-O text section')
def normalized_saved(path):
    d=json.loads(path.read_text())
    for v in d.values():
        if v['type']=='file':v['size']=v.pop('bytes')
    return d
def without_link_modes(rows):
    return {k:{a:b for a,b in v.items() if not (v['type']=='link' and a=='mode')} for k,v in rows.items()}
def main():
    if len(sys.argv)!=2 or not sys.argv[1].replace('-','').isalnum():raise SystemExit('usage: package-metal4-bar-candidate.py EXACT_BUILD_ATTEMPT')
    build=sys.argv[1];evidence=ROOT/'artifacts/validation/metal4-vulkan-integration-20261002'/build
    receipt=json.loads((evidence/'build-receipt.json').read_text());library=ROOT/receipt['library']
    assert receipt['exitCode']==0 and receipt['sourceUnchangedDuringBuild'] and sha(library)==receipt['librarySha256']
    parent=ROOT/'artifacts/runtime/run95-luavbo-layout-20261002/BAR-luavbo-candidate.app';rootApp=ROOT/'BAR.app'
    before=inventory(parent);rootBefore=inventory(rootApp)
    assert without_link_modes(before)==normalized_saved(parent.parent/'candidate-inventory.json'),'Protected VBO parent changed'
    assert without_link_modes(rootBefore)==normalized_saved(parent.parent/'parent-inventory.json'),'Root app changed'
    out=STAGE/build;out.mkdir(parents=True,exist_ok=True);candidate=out/'BAR-metal4-candidate.app'
    assert not (out/'package-receipt.json').exists(),'Completed immutable package exists'
    run('/usr/bin/codesign','--verify','--deep','--strict',str(parent))
    if not candidate.exists():run('/bin/cp','-cR',str(parent),str(candidate))
    assert inventory(candidate)==before,'Existing partial candidate is not the unchanged parent'
    relative='Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
    target=candidate/relative
    oldLoads=loads(target);assert loads(library)[1:]==oldLoads[1:],'Unexpected library dependencies'
    assert all(p.startswith(('/System/Library/','/usr/lib/')) for p in oldLoads[1:]),'Non-system library dependency'
    assert 'LC_RPATH' not in run('/usr/bin/otool','-l',str(library)),'Unexpected library rpath'
    shutil.copy2(library,target)
    run('/usr/bin/install_name_tool','-id',oldLoads[0],str(target))
    assert loads(target)==oldLoads,'Packaged load contract differs'
    run('/usr/bin/codesign','--force','--sign','-',str(target))
    assert text_sha(library)==text_sha(target),'Signing altered executable code'
    run('/usr/bin/codesign','--force','--sign','-','--preserve-metadata=identifier,entitlements,requirements,flags,runtime',str(candidate))
    run('/usr/bin/codesign','--verify','--deep','--strict',str(candidate))
    after=inventory(candidate);changed=sorted(k for k in before if before[k]!=after[k])
    assert set(before)==set(after)
    assert set(changed)<= {relative,'Contents/_CodeSignature/CodeResources','Contents/MacOS/BAR'},changed
    assert text_sha(candidate/'Contents/MacOS/BAR')==text_sha(parent/'Contents/MacOS/BAR')
    engines={}
    for lane,version in [('lobby','2026.09.10-0-g694e9df7'),('chobby','2026.07.04')]:
        rel=f'Contents/Resources/bundled-assets/engine/{version}/spring'
        assert before[rel]==after[rel];engines[lane]=after[rel]['sha256']
    assert inventory(parent)==before and inventory(rootApp)==rootBefore
    for name in ('build-receipt.json','build-lock.json','source-manifest.json','headers-manifest.json'):shutil.copy2(evidence/name,out/name)
    for name,data in [('parent-inventory.json',before),('candidate-inventory.json',after)]: (out/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
    result=dict(schema='metal4-bar-package-v1',status='signed-experimental-runtime-candidate-not-accepted',candidate=str(candidate),parent=str(parent),buildDigest=receipt['buildDigest'],buildReceipt=str(evidence/'build-receipt.json'),rawLibrarySha256=sha(library),packagedLibrarySha256=sha(target),changedFiles=changed,engineHashes=engines,enginesUnchanged=True,sharedRuntimeBothLanes=True,syncedContentUnchanged=True,rootAppUnchanged=True,parentUnchanged=True,codesignDeepStrictVerified=True,gameExecuted=False,nativeOptInRequired={'MVK_CONFIG_USE_METAL4':'1'})
    (out/'package-receipt.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
