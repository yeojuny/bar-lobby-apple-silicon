#!/usr/bin/env python3
"""Full existing Objective-C++ TUs, redirected by Clang VFS to exact capsules."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
from prepare import ROOT, OUT, sha

BASE=ROOT/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
BUILD=ROOT/'build/metal4-mvk-20261002'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--module',action='append',required=True,help='module-id:exact-variant')
    p.add_argument('--tu',action='append',required=True,help='MoltenVK-relative existing .mm file')
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();out=args.output.resolve()
    if out.parent!=OUT or out.exists():raise SystemExit('Output must be a new direct evidence directory')
    overrides={};applied=[]
    for selection in args.module:
        name,variant=selection.split(':',1)
        if '/' in name or '..' in name:raise ValueError('Unsafe module name')
        module=json.loads((OUT/'modules'/name/'module.json').read_text())
        for row in module['variants'][variant]['files']:
            target=(ROOT/row['target']).resolve()
            if not target.is_relative_to(ROOT) or not target.is_file():raise ValueError('Invalid source target')
            before=(OUT/row['before']['path']).read_bytes();after=(OUT/row['after']['path']).read_bytes()
            assert sha(before)==row['before']['sha256'] and sha(after)==row['after']['sha256']
            if target in overrides:
                assert overrides[target].read_bytes()==before,'Overlapping modules require exact staged pins'
            else:
                assert target.read_bytes()==before,'Live baseline differs; select exact staged parent'
            overrides[target]=OUT/row['after']['path']
        applied.append({'id':name,'variant':variant,'moduleSHA256':sha((OUT/'modules'/name/'module.json').read_bytes())})
    out.mkdir()
    overlay={'version':0,'roots':[{'type':'file','name':str(src),'external-contents':str(dst)} for src,dst in overrides.items()]}
    overlaypath=out/'overlay.json';overlaypath.write_text(json.dumps(overlay,indent=2)+'\n')
    ninja=(BUILD/'build.ninja').read_text().splitlines()
    rows=[]
    for tu in args.tu:
        target=(BASE/tu).resolve()
        if not target.is_relative_to(BASE) or not target.is_file() or target.suffix!='.mm':raise ValueError('Invalid existing TU')
        prefix='build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/'+tu+'.o:'
        indices=[i for i,line in enumerate(ninja) if line.startswith(prefix)]
        assert len(indices)==1
        flags={}
        for line in ninja[indices[0]+1:]:
            if not line.startswith('  '):break
            k,v=line.strip().split(' = ',1);flags[k]=v
        for foundation in (0,1):
            defines=flags['DEFINES'].replace('-DMVK_BUILD_METAL4_FOUNDATION=1',f'-DMVK_BUILD_METAL4_FOUNDATION={foundation}')
            command=['/usr/bin/c++']+shlex.split(defines+' '+flags['FLAGS']+' '+flags['INCLUDES'])+[
                '-ivfsoverlay',str(overlaypath),'-fsyntax-only',str(target)]
            run=subprocess.run(command,cwd=BUILD,capture_output=True,text=True,timeout=120)
            label=target.stem+'-foundation'+str(foundation)
            (out/(label+'.log')).write_text(run.stdout+run.stderr)
            rows.append({'tu':tu,'foundation':foundation,'command':command,'flags':flags,'exit':run.returncode})
            (out/'receipt.json').write_text(json.dumps({'status':'running','modules':applied,'runs':rows},indent=2)+'\n')
            print(json.dumps({'tu':tu,'foundation':foundation,'exit':run.returncode}),flush=True)
            if run.returncode:break
        if rows[-1]['exit']:break
    status='passed-full-source-syntax-only' if len(rows)==2*len(args.tu) and all(x['exit']==0 for x in rows) else 'failed'
    receipt={'status':status,'modules':applied,'runs':rows,'sourceWrites':0,'productBuilds':0,'actualGPU':False,
             'ninjaSHA256':sha((BUILD/'build.ninja').read_bytes()),'limits':'Syntax only; no native objects, library, app or GPU execution.'}
    (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return 0 if status.startswith('passed') else 1


if __name__=='__main__':raise SystemExit(main())
