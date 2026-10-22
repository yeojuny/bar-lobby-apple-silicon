from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[3];I=Path(__file__).resolve().parent
read=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
selected=set();review=read(I/'review-pins.json');selected.update(R/n for n in review);selected.add(R/'reports/v104-c-reg-20261020.md')
for p in I.rglob('*'):
 if p.is_file() and p.suffix in ('.json','.py','.md','.patch','.log','.mm','.h','.cpp') and p.name not in ('github-handoff.json','restoration-selection.json') and '.dSYM' not in str(p):selected.add(p)
for folder in ('v104-c-reg-performance-20261020','v104-c-reg-fullscreen-reverse-20261020'):
 O=R/'artifacts/validation'/folder
 for p in O.iterdir():
  if p.is_file() and p.suffix in ('.json','.jsonl','.py','.m','.c','.patch','.mjs','.cjs','.lua','.txt','.log'):selected.add(p)
 for item in read(O/'preparation.json')['plans']:
  selected.add(Path(item['plan']['path']));selected.add(Path(item['host']['path']))
  arm=read(O/f'arm-{item["ordinal"]}-result.json');receipt=Path(arm['receipt']);selected.add(receipt)
  for rel in ('state/data/LuaUI/Config/v104-performance-result.json','state/data/stack-game.stderr.log','state/data/hidden-window-events.jsonl'):
   p=receipt.parent/rel
   if p.is_file():selected.add(p)
# Small exact private fullscreen guard is necessary to reproduce its binding.
selected.add(R/'artifacts/validation/v104-c-reg-fullscreen-reverse-20261020/libhidden-fullscreen.dylib')
package=read(I/'package-receipt.json');app=Path(package['app'])
for n in package['changedFromCTCM3']:selected.add(app/n)
selected.add(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib')
rows=[]
for p in sorted(selected):
 assert p.is_relative_to(R) and p.is_file() and not p.is_symlink()
 rows.append({'path':str(p.relative_to(R)),'sha256':sha(p),'bytes':p.stat().st_size,'mode':p.stat().st_mode&511})
manifest={'status':'frozen-exact-selection','scope':'C-REG implementation, validation, two completed comparisons, exact signed app delta from current C-T+C-M3 candidate; no actual user profile contents or content archives','baseRestoreCommit':'45e1bc37ccb68b95b630666497813c9bd1b95603','baseApp':package['parent'],'candidateApp':package['app'],'candidateInventory':str((I/'candidate-inventory.json').relative_to(R)),'appDelta':package['changedFromCTCM3'],'files':rows,'fileCount':len(rows),'totalBytes':sum(x['bytes'] for x in rows)}
(I/'restoration-selection.json').write_text(json.dumps(manifest,indent=2)+'\n')
handoff={'status':'ready-for-authorized-existing-publisher','repository':'yeojuny/bar-lobby-apple-silicon','branch':'restore/mvk-20261020-p123-b-ct-cm3','knownParent':'45e1bc37ccb68b95b630666497813c9bd1b95603','selectedManifest':{'path':str(I/'restoration-selection.json'),'sha256':sha(I/'restoration-selection.json')},'sourceReview':str(I/'independent-review.json'),'completion':str(I/'completion.json'),'report':str(R/'reports/v104-c-reg-20261020.md'),'publishOnlyRestorationBranch':True,'formalReleaseHomebrewRequested':False,'rebuildOrGameExecutionRequested':False,'sourceOrAppEditingRequested':False,'snapshotBytesImmutable':True,'physicalRetinaModeRequested':False,'fullscreenComparison':'game fullscreen ON, SDL fullscreen intent/flags, 1512x982 container, 1512x950 safe viewport, hidden native presentation deferred by SDL','benchmarks':'16 completed actual BAR sessions: initial windowed 1432x902, then user-requested fullscreen/reverse 1512x950, 8 each; no pooling between conditions','latestResults':{'Metal4FPSChangePercent':3.0514726313221274,'Metal3FPSChangePercent':-0.8688600939355751,'nPerAppBackend':2},'noGuaranteedNetBenefitOrGeneralizedFPSClaim':True}
(I/'github-handoff.json').write_text(json.dumps(handoff,indent=2)+'\n');print({'files':len(rows),'bytes':manifest['totalBytes'],'manifest':str(I/'restoration-selection.json')})
