from pathlib import Path
import hashlib, json
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent
read=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
selected={R/'reports/v104-three-candidate-performance-20261020.md'}
suffixes={'.json','.jsonl','.py','.mjs','.cjs','.lua','.txt','.log'}
for p in O.iterdir():
    if p.is_file() and p.suffix in suffixes and p.name not in ('github-handoff.json','restoration-selection.json','publication-link.json'):selected.add(p)
for item in read(O/'preparation.json')['plans']:
    selected.add(Path(item['plan']['path']));selected.add(Path(item['host']['path']))
    r=read(O/f"arm-{item['ordinal']}-result.json");receipt=Path(r['receipt']);selected.add(receipt)
    for rel in ('state/data/infolog.txt','state/data/stack-game.stderr.log','state/data/hidden-window-events.jsonl','state/data/LuaUI/Config/v104-performance-result.json'):
        p=receipt.parent/rel
        if p.is_file():selected.add(p)
# Exact previously qualified hidden-fullscreen sidecar; no apps, user settings or content assets.
selected.add(O/'libhidden-fullscreen.dylib')
rows=[]
for p in sorted(selected):
    assert p.is_relative_to(R) and p.is_file() and not p.is_symlink()
    rows.append(dict(path=str(p.relative_to(R)),sha256=sha(p),bytes=p.stat().st_size,mode=p.stat().st_mode&511))
manifest=dict(status='frozen-exact-performance-evidence-selection',baseRestoreCommit='146bce2cbd060b15eb708c5bba68e27042471a8a',
    files=rows,fileCount=len(rows),totalBytes=sum(x['bytes'] for x in rows),
    scope='12 actual BAR comparison runs, execution order/settings/FPS/frame samples, source/app pins and cleanup proof; no app binary duplication or actual user profile bytes')
(O/'restoration-selection.json').write_text(json.dumps(manifest,indent=2)+'\n')
handoff=dict(status='ready-for-existing-authorized-publisher',repository='yeojuny/bar-lobby-apple-silicon',branch='restore/mvk-20261020-p123-b-ct-cm3',
    knownParent=manifest['baseRestoreCommit'],selection=dict(path=str(O/'restoration-selection.json'),sha256=sha(O/'restoration-selection.json')),
    completion=str(O/'completion.json'),report=str(R/'reports/v104-three-candidate-performance-20261020.md'),newProductChanges=False,
    noNewTestsBuildsGames=True,noFormalReleaseOrHomebrew=True,priorAppCheckpointImmutable=True,
    qualifications='n=2 per app/backend, same 1512x950 safe fullscreen viewport while hidden at default 1x; SDL native presentation deferred; historical failures not claimed fixed')
(O/'github-handoff.json').write_text(json.dumps(handoff,indent=2)+'\n')
print(json.dumps(dict(files=len(rows),bytes=manifest['totalBytes'])))
