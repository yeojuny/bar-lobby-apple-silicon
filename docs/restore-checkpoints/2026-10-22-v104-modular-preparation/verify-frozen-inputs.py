#!/usr/bin/env python3
"""Read-only product/benchmark preservation check; never starts a host or game."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
from prepare import OUT, ROOT, sha

def hash_file(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for data in iter(lambda:f.read(1024*1024),b''):h.update(data)
    return h.hexdigest()

def inventory(root):
    data={}
    for folder,dirs,files in os.walk(root,followlinks=False):
        for name in dirs+files:
            file=Path(folder)/name;st=file.lstat();mode=stat.S_IMODE(st.st_mode)&0o777
            if file.is_symlink():value={'type':'link','mode':mode,'target':os.readlink(file)}
            elif file.is_file():value={'type':'file','mode':mode,'size':st.st_size,'sha256':hash_file(file)}
            elif file.is_dir():continue
            else:raise ValueError('Unexpected special app input')
            data[str(file.relative_to(root))]=value
    return data

def main():
    destination=OUT/'frozen-inputs-final.json'
    if destination.exists():raise SystemExit('Do not overwrite completed verification')
    bench=ROOT/'artifacts/validation/v104-r-small-bundle-20261021'
    original=json.loads((bench/'performance-before.json').read_text())
    pins=json.loads((OUT/'active-input-pins.json').read_text())['files']
    mismatches=[path for path,digest in pins.items() if hash_file(ROOT/path)!=digest]
    apps={}
    for name,app in original['apps'].items():
        expected=json.loads((bench/(name+'-inventory.json')).read_text())
        actual=inventory(Path(app));difference=[key for key in set(expected)|set(actual) if expected.get(key)!=actual.get(key)]
        apps[name]={'entries':len(actual),'mismatches':sorted(difference),
                    'MVKSHA256':hash_file(Path(app)/original['libraryRelativePath'])}
        assert apps[name]['MVKSHA256']==original['packageSHA256'][name]
    prepared={}
    for direction in ('forward','reverse'):
        folder=bench/('performance-idle-'+direction)
        plans=json.loads((folder/'preparation.json').read_text())['plans'];bad=[]
        for item in plans:
            for key in ('plan','host'):
                if hash_file(Path(item[key]['path']))!=item[key]['sha256']:bad.append(item[key]['path'])
        protected=json.loads((folder/'protected-inputs.json').read_text())
        user_bad=[name for name,item in protected['userState'].items() if hash_file(Path(item['path']))!=item['sha256']]
        prepared[direction]={'planCount':len(plans),'planHostMismatches':bad,'userStateMismatches':user_bad,
            'gameGrants':len(list(folder.rglob('grant.json'))),'executionReceipts':len(list(folder.rglob('execution-receipt.json')))}
    raw=ROOT/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'
    repo=ROOT/'sources/bar-lobby';env=dict(os.environ,GIT_OPTIONAL_LOCKS='0')
    def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],env=env)
    gitdir=Path(git('rev-parse','--absolute-git-dir').decode().strip())
    launcher={'HEAD':git('rev-parse','HEAD').decode().strip(),'indexSHA256':hash_file(gitdir/'index'),
        'statusPorcelainV1AllSHA256':sha(git('status','--porcelain=v1','--untracked-files=all')),
        'diffBinarySHA256':sha(git('diff','--binary'))}
    launcher['historicalHEADAndIndexMatch']=(launcher['HEAD']=='6a3b298c236cd10eff8fd7ce27d15cdb589f650f' and launcher['indexSHA256']=='073483d1f4a62c9cda7006b467f60da926f889d1c8f126dc0016e3a23b761c87')
    result={'status':'verified-frozen','sourcePinCount':len(pins),'sourcePinMismatches':mismatches,
        'apps':apps,'preparedBenchmarks':prepared,'rawMVKSHA256':hash_file(raw),
        'rawMatches':hash_file(raw)==original['rawSHA256'],'launcher':launcher,
        'newProductBuilds':0,'newGPUOrGameRuns':0,'localRetirementPerformed':False}
    passed=not mismatches and result['rawMatches'] and launcher['historicalHEADAndIndexMatch'] and all(not a['mismatches'] for a in apps.values()) and all(not a['planHostMismatches'] and not a['userStateMismatches'] and a['gameGrants']==a['executionReceipts']==0 for a in prepared.values())
    if not passed:result['status']='preservation-mismatch'
    destination.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'sources':len(pins),'appEntries':{n:v['entries'] for n,v in apps.items()},'prepared':prepared}))
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
