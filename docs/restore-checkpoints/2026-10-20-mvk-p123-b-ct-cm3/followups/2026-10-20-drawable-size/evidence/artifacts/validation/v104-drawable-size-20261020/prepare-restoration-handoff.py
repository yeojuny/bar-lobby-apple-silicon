from pathlib import Path
import hashlib,json

ROOT=Path(__file__).resolve().parents[3]
IMPL=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
completion=read(IMPL/'completion.json');assert completion['status']=='implemented-reviewed-compared-observation-exit-unresolved'
selected=set(ROOT/p for p in read(IMPL/'review-pins.json'))
selected.add(ROOT/'reports/v104-drawable-size-20261020.md')
for path in IMPL.rglob('*'):
    if path.is_file() and path.suffix in {'.json','.py','.md','.patch','.log','.mm','.h','.cpp','.stderr','.jsonl'} and path.name not in {'github-handoff.json','restoration-selection.json','publication-link.json'} and '.dSYM' not in str(path) and '/version-' not in str(path):selected.add(path)
for name in ['v104-drawable-size-performance-20261020','v104-drawable-size-observation-20261020']:
    base=ROOT/'artifacts/validation'/name
    for path in base.iterdir():
        if path.is_file() and path.suffix in {'.json','.jsonl','.py','.m','.c','.patch','.mjs','.cjs','.lua','.txt','.log','.dylib'}:selected.add(path)
    for plan in read(base/'preparation.json')['plans']:
        selected.update([Path(plan['plan']['path']),Path(plan['host']['path'])])
        arm=read(base/f'arm-{plan["ordinal"]}-result.json');receipt=Path(arm['receipt']);selected.add(receipt)
        relatives=['state/data/LuaUI/Config/v104-performance-result.json','state/data/stack-game.stderr.log','state/data/hidden-window-events.jsonl','cpu-sample.txt','cpu-sample-stderr.txt']
        if 'observation' in name:relatives+=['events.jsonl','state/data/infolog.txt','state/data/LuaUI/Config/v104-performance-status.txt','state/data/LuaUI/Config/v104-performance-request.txt']
        for rel in relatives:
            path=receipt.parent/rel
            if path.is_file():selected.add(path)
package=read(IMPL/'package-receipt.json');app=Path(package['app'])
for relative in package['changedFiles']:selected.add(app/relative)
rows=[]
for path in sorted(selected):
    assert path.is_relative_to(ROOT) and path.is_file() and not path.is_symlink()
    assert '/inputs/' not in str(path) and '/version-' not in str(path),'Private profile input/CLI scratch not selected'
    rows.append({'path':str(path.relative_to(ROOT)),'sha256':sha(path),'bytes':path.stat().st_size,'mode':path.stat().st_mode&511})
manifest={'status':'frozen-exact-selection','scope':'Narrow live window/drawable size query implementation in both native engines, CPU/build/package/independent review, one separate OS observation and8 concurrent-user-workload reference comparisons; exact signed app4-file delta; no actual user profile contents or game archives.','baseRestoreCommit':'7a3a24591f75d53a9022487a3f2e25d3d5c05afa','baseApp':package['parent'],'candidateApp':package['app'],'candidateInventory':str((IMPL/'candidate-inventory.json').relative_to(ROOT)),'appDelta':package['changedFiles'],'files':rows,'fileCount':len(rows),'totalBytes':sum(x['bytes'] for x in rows)}
(IMPL/'restoration-selection.json').write_text(json.dumps(manifest,indent=2)+'\n')
handoff={'status':'ready-for-authorized-existing-publisher','repository':'yeojuny/bar-lobby-apple-silicon','branch':'restore/mvk-20261020-p123-b-ct-cm3','knownParent':manifest['baseRestoreCommit'],'selectedManifest':{'path':str(IMPL/'restoration-selection.json'),'sha256':sha(IMPL/'restoration-selection.json')},'sourceReview':str(IMPL/'independent-review.json'),'completion':str(IMPL/'completion.json'),'report':str(ROOT/'reports/v104-drawable-size-20261020.md'),'publishOnlyRestorationBranch':True,'formalReleaseHomebrewRequested':False,'rebuildOrGameExecutionRequested':False,'sourceOrAppEditingRequested':False,'snapshotBytesImmutable':True,'conditions':'Game fullscreen hidden1512x950 safe viewport, AC+Low Power ON, Ultra/AA Off/Spring; native macOS Space presentation deferred while hidden.','qualification':'User confirmed concurrent other work;8FPS results are reference only,no isolated causal speedup claim. Separate sampled run collected data but failed15-second native exit check; cause unresolved,private failure profile/cache retained,no retry. Sampled FPS excluded.','latestResults':completion['performance']['groups'],'rawEngineBinariesNotDuplicated':'Exact signed engines plus source preimages/after/patch, full inventory, raw build digests and preserved local raw backups suffice for this restoration delta.'}
(IMPL/'github-handoff.json').write_text(json.dumps(handoff,indent=2)+'\n')
print(json.dumps({'files':len(rows),'bytes':manifest['totalBytes'],'manifest':str(IMPL/'restoration-selection.json')},ensure_ascii=False))
