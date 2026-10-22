#!/usr/bin/env python3
"""Run actual prepared-resource header with explicit mocked native retention."""
import argparse
import json
from pathlib import Path
import subprocess
from prepare import OUT, sha

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage',choices=['baseline','08b','08b+09'],required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output.resolve()
    if out.parent!=OUT or out.exists():raise SystemExit('Output must be a new direct evidence directory')
    module=json.loads((OUT/'modules/08b-partial-group-replay/module.json').read_text())
    variant='after09' if args.stage=='08b+09' else 'R-and-Small'
    version='before' if args.stage=='baseline' else 'after'
    row=module['variants'][variant]['files'][0][version]
    header=OUT/row['path'];assert sha(header.read_bytes())==row['sha256']
    out.mkdir();source=out/'fixture.cpp'
    source.write_text('#include '+json.dumps(str(header))+'\n'+(OUT/'partial-checks.cpp').read_text())
    command=['/usr/bin/clang++','-std=c++17','-O1','-g','-fsanitize=address,undefined',
             '-fno-omit-frame-pointer','-pthread','-DEXPECT_PARTIAL='+str(int(args.stage!='baseline')),
             str(source),'-o',str(out/'check')]
    receipt={'stage':args.stage,'status':'compile-failed','headerSHA256':sha(header.read_bytes()),
             'fixtureSHA256':sha(source.read_bytes()),'command':command,'activeSourceWrites':0,
             'productBuilds':0,'actualGPU':False,
             'boundaries':'Actual whole production header. Native retention is a weak-proof/id mock; legal descriptor updates supplied by test. No Metal device, execution or race-freedom claim.'}
    try:
        run=subprocess.run(command,capture_output=True,text=True,timeout=120)
        (out/'compile.log').write_text(run.stdout+run.stderr);receipt['compileExit']=run.returncode
        if run.returncode==0:
            receipt['status']='run-failed'
            run=subprocess.run([str(out/'check')],capture_output=True,text=True,timeout=30)
            (out/'run.log').write_text(run.stdout+run.stderr);receipt['runExit']=run.returncode
            if run.returncode==0:receipt.update(status='passed-cpu-contracts-only',result=json.loads(run.stdout))
    except subprocess.TimeoutExpired as error:
        receipt['status']='timeout';(out/'timeout.log').write_bytes((error.stdout or b'')+(error.stderr or b''))
    (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'stage':args.stage,'status':receipt['status'],'result':receipt.get('result'),'receipt':str(out/'receipt.json')}))
    return 0 if receipt['status'].startswith('passed') else 1

if __name__=='__main__':raise SystemExit(main())
