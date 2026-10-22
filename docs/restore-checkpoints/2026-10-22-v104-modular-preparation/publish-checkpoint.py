#!/usr/bin/env python3
"""Exact compact backup via an alternate index; never check out or stage product files."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.parse
import urllib.request
from prepare import OUT, ROOT, sha

REPO=ROOT/'sources/bar-lobby'
REMOTE='apple-silicon'
SLUG='yeojuny/bar-lobby-apple-silicon'
BRANCH='restore/v104-modular-preparation-20261022'
PARENT='ff8908bcdf75b28ef9ce24bef0e654be72a9b46f'
PREFIX='docs/restore-checkpoints/2026-10-22-v104-modular-preparation'
STAGING=OUT/'publication-staging'
BASE_ENV=dict(os.environ,GIT_OPTIONAL_LOCKS='0')

def git(args,data=None,env=None):
    return subprocess.check_output(['git','-C',str(REPO),*args],input=data,env=env or BASE_ENV)

def launcher():
    gitdir=Path(git(['rev-parse','--absolute-git-dir']).decode().strip())
    return {'HEAD':git(['rev-parse','HEAD']).decode().strip(),'indexSHA256':sha((gitdir/'index').read_bytes()),
        'statusPorcelainV1AllSHA256':sha(git(['status','--porcelain=v1','--untracked-files=all'])),
        'diffBinarySHA256':sha(git(['diff','--binary']))}

def sources():
    for path in sorted(OUT.rglob('*')):
        rel=path.relative_to(OUT)
        if any(part in ('__pycache__','publication-staging') or part.endswith('.dSYM') for part in rel.parts):continue
        if path.is_symlink():raise ValueError('Unexpected symlink in evidence')
        if not path.is_file() or path.name=='work-state.json' or path.name.startswith('publication-'):continue
        if path.suffix not in {'.py','.h','.cpp','.mm','.json','.md','.patch','.log','.txt','.tsv'} and path.parent.name!='payload':continue
        yield path,rel.as_posix()

def prepare():
    if STAGING.exists():raise SystemExit('Staging already exists; do not overwrite')
    assert json.loads((OUT/'independent-final-package-review.json').read_text())['blockingFindings']==[]
    assert json.loads((OUT/'frozen-inputs-final.json').read_text())['status']=='verified-frozen'
    before=launcher()
    expected=json.loads((OUT/'frozen-inputs-final.json').read_text())['launcher']
    assert all(before[k]==expected[k] for k in before)
    assert git(['remote','get-url',REMOTE]).decode().strip()=='https://github.com/'+SLUG+'.git'
    assert git(['rev-parse',PARENT+'^{commit}']).decode().strip()==PARENT
    assert not git(['ls-remote',REMOTE,'refs/heads/'+BRANCH]).strip()
    STAGING.mkdir();env=dict(BASE_ENV,GIT_INDEX_FILE=str(STAGING/'index'))
    git(['read-tree',PARENT],env=env)
    assert not git(['ls-tree','-r','--name-only',PARENT,'--',PREFIX]).strip()
    entries=[];updates=[]
    for path,rel in sources():
        data=path.read_bytes();data.decode('utf-8')
        blob=git(['hash-object','-w','--stdin'],data).decode().strip()
        target=PREFIX+'/'+rel
        entries.append({'path':rel,'sha256':sha(data),'bytes':len(data),'gitBlob':blob,'mode':'100644'})
        updates.append(('100644 '+blob+'\t'+target+'\0').encode())
    manifest={'kind':'Unapplied source capsules, full exact before/after payloads, designs and CPU/syntax receipts',
        'baseCommit':PARENT,'destinationBranch':BRANCH,'prefix':PREFIX,'files':entries,
        'includedBytes':sum(f['bytes'] for f in entries),'excluded':'Compiled test executables/debug objects, transient work-state, live apps/builds and user profile contents',
        'restoration':'Materialize the prior R/Small checkpoint, then put this folder at artifacts/validation/v104-modular-preparation-20261022 in the BAR workspace. Verify hashes before application. No GPU/performance qualification.'}
    manifest_data=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    (STAGING/'MANIFEST.json').write_bytes(manifest_data)
    blob=git(['hash-object','-w','--stdin'],manifest_data).decode().strip()
    updates.append(('100644 '+blob+'\t'+PREFIX+'/MANIFEST.json\0').encode())
    git(['update-index','-z','--index-info'],b''.join(updates),env=env)
    tree=git(['write-tree'],env=env).decode().strip()
    message=b'Preserve nine unapplied v1.0.4 optimization modules and all thirteen work contracts\n\nExact R/Small parent variants, reversible composition, independent review, CPU/syntax evidence and explicit remaining design boundaries. No active product source, app, Release or Homebrew change.\n'
    commit=git(['commit-tree',tree,'-p',PARENT],message).decode().strip()
    assert launcher()==before
    state={'status':'prepared-not-pushed','commit':commit,'tree':tree,'parent':PARENT,'branch':BRANCH,
        'prefix':PREFIX,'fileCount':len(entries)+1,'payloadBytes':sum(f['bytes'] for f in entries)+len(manifest_data),
        'manifestSHA256':sha(manifest_data),'manifestGitBlob':blob,'launcherBefore':before}
    (OUT/'publication-prepared.json').write_text(json.dumps(state,indent=2)+'\n')
    print(json.dumps({k:state[k] for k in ('status','commit','fileCount','payloadBytes')}))

def publish():
    state=json.loads((OUT/'publication-prepared.json').read_text())
    assert launcher()==state['launcherBefore']
    manifest=json.loads((STAGING/'MANIFEST.json').read_text())
    for row in manifest['files']:
        assert sha((OUT/row['path']).read_bytes())==row['sha256'],row['path']
    assert not git(['ls-remote',REMOTE,'refs/heads/'+BRANCH]).strip()
    run=subprocess.run(['git','-C',str(REPO),'push',REMOTE,state['commit']+':refs/heads/'+BRANCH],env=BASE_ENV,capture_output=True,text=True,timeout=120)
    (STAGING/'push.log').write_text(run.stdout+run.stderr)
    assert run.returncode==0,run.stderr
    assert launcher()==state['launcherBefore']
    (OUT/'publication-pushed.json').write_text(json.dumps(dict(state,status='pushed-awaiting-readback'),indent=2)+'\n')
    print(json.dumps({'status':'pushed','commit':state['commit']}))

def api(path):
    return json.loads(subprocess.check_output(['/opt/homebrew/bin/gh','api','repos/'+SLUG+'/'+path],env=BASE_ENV))

def verify():
    state=json.loads((OUT/'publication-pushed.json').read_text())
    manifest_data=(STAGING/'MANIFEST.json').read_bytes();assert sha(manifest_data)==state['manifestSHA256']
    manifest=json.loads(manifest_data)
    branch=api('git/ref/heads/'+BRANCH);assert branch['object']['sha']==state['commit']
    commit=api('git/commits/'+state['commit']);assert commit['tree']['sha']==state['tree'] and [p['sha'] for p in commit['parents']]==[PARENT]
    tree=state['tree']
    for part in PREFIX.split('/'):
        result=api('git/trees/'+tree)
        match=[e for e in result['tree'] if e['path']==part and e['type']=='tree'];assert len(match)==1
        tree=match[0]['sha']
    listing=api('git/trees/'+tree+'?recursive=1');assert not listing.get('truncated')
    expected={r['path']:r for r in manifest['files']}
    expected['MANIFEST.json']={'sha256':sha(manifest_data),'bytes':len(manifest_data),'gitBlob':state['manifestGitBlob'],'mode':'100644'}
    remote={r['path']:r for r in listing['tree'] if r['type']=='blob'}
    assert set(remote)==set(expected)
    for path,row in expected.items():
        assert remote[path]['sha']==row['gitBlob'] and remote[path]['mode']==row['mode'] and remote[path]['size']==row['bytes'],path
    # Read every exact published file anonymously at the immutable commit URL.
    def read(row):
        path,item=row
        url='https://raw.githubusercontent.com/'+SLUG+'/'+state['commit']+'/'+urllib.parse.quote(PREFIX+'/'+path,safe='/')
        try:
            with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'BAR-source-checkpoint-verifier'}),timeout=30) as response:data=response.read()
            return {'path':path,'sha256':sha(data),'bytes':len(data),'matched':sha(data)==item['sha256'] and len(data)==item['bytes']}
        except Exception as error:return {'path':path,'matched':False,'error':str(error)}
    rows=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for row in pool.map(read,expected.items()):
            rows.append(row)
            if len(rows)%75==0:print(json.dumps({'anonymousFilesChecked':len(rows),'total':len(expected)}),flush=True)
    (STAGING/'anonymous-readback.json').write_text(json.dumps(rows,indent=2)+'\n')
    failed=[r for r in rows if not r['matched']]
    after=launcher();assert after==state['launcherBefore']
    result={'status':'verified-published' if not failed else 'published-readback-incomplete',
        'commit':state['commit'],'tree':state['tree'],'branch':BRANCH,'fileCount':len(expected),
        'bytes':state['payloadBytes'],'anonymousReadbackMatched':len(rows)-len(failed),'failed':failed,
        'URL':'https://github.com/'+SLUG+'/tree/'+state['commit']+'/'+PREFIX,
        'launcherUnchanged':True,'productSourceApplied':False,'productBuilds':0,'GPUOrGameRuns':0,
        'ReleaseHomebrewDefaultBranchChanged':False,'localRetirementPerformed':False}
    (OUT/'publication-completion.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    return 0 if not failed else 1

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('mode',choices=['prepare','publish','verify']);args=parser.parse_args()
    result={'prepare':prepare,'publish':publish,'verify':verify}[args.mode]()
    raise SystemExit(result or 0)
