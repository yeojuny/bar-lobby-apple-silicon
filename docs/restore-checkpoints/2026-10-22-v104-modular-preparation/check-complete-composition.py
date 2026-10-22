#!/usr/bin/env python3
"""Review complete R/Small source compositions in memory; no activation."""
import importlib.util
import json
from pathlib import Path
from prepare import OUT, sha

spec=importlib.util.spec_from_file_location('capsule_check',OUT/'check-modules.py')
check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)
modules={p.parent.name:json.loads(p.read_text()) for p in (OUT/'modules').glob('*/module.json')}
def compose(route):
    current={};before={};history=[]
    for module_id,variant in route:
        module=modules[module_id];files=module['variants'][variant]['files']
        for f in files:
            if f['target'] not in current:current[f['target']]=before[f['target']]=check.blob(f['before'])
        subset={f['target']:current[f['target']] for f in files}
        current.update(check.exact_variant(module,variant,subset));history.append((module,variant))
    final=dict(current)
    for module,variant in reversed(history):
        subset={f['target']:current[f['target']] for f in module['variants'][variant]['files']}
        current.update(check.exact_variant(module,variant,subset,reverse=True))
    assert current==before
    return {'route':[a+':'+b for a,b in route],'exactReverse':True,
            'before':{p:sha(v) for p,v in before.items()},'after':{p:sha(v) for p,v in final.items()}}

rows={}
for parent in ('R','Small'):
    forward=[('11a-typed-frame-discard','R-and-Small'),('08a-conservative-rebind',parent),
        ('06-success-notify','R-and-Small'),('07-signal-order-proof','after06'),
        ('02-layout-policy','R-and-Small'),('03-owned-replay-chain','R-and-Small'),
        ('04-compact-cpu-state','after02'),('08b-partial-group-replay','R-and-Small'),
        ('09-snapshot-unlocked-retain','after08b')]
    alternate=[('09-snapshot-unlocked-retain','R-and-Small'),('08b-partial-group-replay','after09'),
        ('04-compact-cpu-state','R-and-Small'),('03-owned-replay-chain','R-and-Small'),
        ('02-layout-policy','after04'),('07-signal-order-proof','R-and-Small'),
        ('06-success-notify','after07'),('08a-conservative-rebind',parent),('11a-typed-frame-discard','R-and-Small')]
    left,right=compose(forward),compose(alternate)
    assert left['before']==right['before'] and left['after']==right['after']
    rows[parent]={'forward':left,'alternate':right,'orderIndependentBytes':True}
path=OUT/'complete-composition.json'
if path.exists():raise SystemExit('Do not overwrite a completed composition check')
path.write_text(json.dumps({'status':'passed-memory-only-composition','parents':rows,
    'moduleManifestHashes':{k:sha((OUT/'modules'/k/'module.json').read_bytes()) for k in modules},
    'activeSourceWrites':0,'productBuilds':0,'gameSessions':0,
    'limits':'Nine prepared modules only,14 distinct target files. Complete bytes and reversal are proved; GPU behavior, performance and safe simultaneous adoption are not.'},indent=2)+'\n')
print(json.dumps({'parents':list(rows),'modules':len(modules),'targets':len(rows['R']['forward']['after']),'status':'passed'}))
