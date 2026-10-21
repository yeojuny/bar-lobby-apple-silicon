from pathlib import Path
import datetime
import hashlib
import json
import re
import subprocess

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[2]
read=lambda p:json.loads(Path(p).read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(name,value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

before=read(ROOT/'artifacts/validation/v104-followup-c-t-20261020/before.json')
review=read(ROOT/'artifacts/validation/v104-followup-c-t-20261020/review-common-pins.json')
pins={k:v for k,v in before['files'].items() if k not in before['selectedEdits']}
pins.update(review)
checks={k:sha(ROOT/k)==v for k,v in pins.items()}
assert checks and all(checks.values()),[k for k,v in checks.items() if not v]
package=read(ROOT/'artifacts/validation/v104-followup-c-t-20261020/package-receipt.json')
raw=ROOT/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'
packaged=Path(package['app'])/'Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
assert sha(raw)==package['rawLibrarySHA256']
assert sha(packaged)==package['packagedLibrarySHA256']
launcher=ROOT/'sources/bar-lobby'
def git(*args):return subprocess.check_output(['git',*args],cwd=launcher).decode().strip()
old=read(ROOT/'artifacts/validation/v103-performance-p1-p3-20261020/before.json')['launcher']
head=git('rev-parse','HEAD')
index=Path(git('rev-parse','--git-path','index'))
if not index.is_absolute():index=launcher/index
index_hash=sha(index)
status=subprocess.check_output(['git','status','--porcelain'],cwd=launcher).decode()
assert head==old['head'] and index_hash==old['index'] and status==old['status']

inputs=[
'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.h',
'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.mm',
'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4PreparedResource.h',
'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm',
'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm',
'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCmdDraw.mm',
'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKQueue.mm',
'build/metal4-mvk-20261002/CMakeCache.txt',
'build/run91-recoil-src-694e9df7/rts/Rendering/GlobalRendering.cpp',
'build/run91-recoil-src-694e9df7/rts/System/Platform/Mac/MacSDL3EGLBridge.mm',
'tools/tests/metal4-native-foundation.mm',
'tools/tests/metal4-r49-lifetime-native.mm',
'tools/tests/metal4-recording-ownership.mm',
'tools/tests/metal4-prepared-recording-vulkan.mm',
]
source_pins={k:sha(ROOT/k) for k in inputs}
save('design-source-pins.json',{'scope':'Current read inputs bound to this design; not a new whole-tree before/after audit. Prior package/review pins separately verified.','files':source_pins})
assert '-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0' in (ROOT/'build/metal4-mvk-20261002/CMakeCache.txt').read_text()

outcome=read(OUT/'outcome.json')
assert outcome['status']=='completed' and len(outcome['results'])==2 and not outcome['screenFailures']
analysis=read(OUT/'sample-analysis.json')
observations=[]
for result in outcome['results']:
    receipt=read(result['receipt'])
    sample=receipt['cpuSample']
    assert receipt['status']=='completed-not-promoted' and receipt['powerConditionsPassed']
    assert receipt['protectedInputsUnchanged'] and receipt['remainingOwnedProcesses']==[]
    assert receipt['loadedRuntimeLibraries']['verified']
    assert sample['exitCode']==0 and sample['sha256']==sha(sample['output']) and not sample['usedForFPSComparison']
    text=Path(sample['output']).read_text()
    legacy_stack='MVKCommandEncoder::encode(id<MTLCommandBuffer>' in text
    native_stack='MVKQueueCommandBufferSubmission::executeMetal4()' in text
    if result['backend']=='metal3':assert legacy_stack and not native_stack and receipt['runtimeEnvironment']['nativeMetal4']=='0'
    else:assert native_stack and receipt['nativeMetal4']['proved']
    observation=next(x for x in analysis['observations'] if x['path']==sample['output'])
    assert observation['sha256']==sample['sha256'] and observation['childCountValidation']
    observations.append({'backend':result['backend'],'receipt':result['receipt'],'receiptSHA256':sha(result['receipt']),
      'sample':sample['output'],'sampleSHA256':sample['sha256'],'requestedDurationSeconds':10,
      'samplerProcessSecondsIncludingSymbols':(sample['endUnixMs']-sample['startUnixMs'])/1000,
      'sampleEndingSimulationFrameKnown':False,'usedForFPSComparison':False,
      'backendVerifiedByActualStack':True,'mappedLibraryHashesVerified':True,'protectedInputsUnchanged':True,
      'ownedProcessesAtExit':[], 'observedCounts':observation['aggregateInclusiveUnion']})

guard=read(OUT/'screen-guard.json')
screen=[json.loads(s) for s in (OUT/'screen-observations.jsonl').read_text().splitlines()]
assert guard['restored'] and guard['awakeReleased'] and guard['beforeIdleTime']==guard['afterIdleTime']==900
assert len(screen)==111 and all(not x['desktop']['consoleLocked'] and x['power']=={'lowPower':True,'thermal':0} for x in screen)
cache=[read(p) for p in sorted(OUT.glob('arm-*-cache-cleanup-completion.json'))]
assert len(cache)==2 and all(x['allAbsent'] and x['logsResultsAndMarkdownPreserved'] for x in cache)

report=ROOT/'reports/v104-remaining-c-cost-design-20261020.md'
# Check local document links, ignoring their optional verified line suffix.
missing=[]
for link in re.findall(r'\]\(([^)]+)\)',report.read_text()):
    if link.startswith('https://'):continue
    p=Path(re.sub(r':\d+$','',link))
    if not p.is_absolute():p=report.parent/p
    p=p.resolve()
    if p==OUT/'design-receipt.json':continue
    if not p.exists():missing.append(str(p))
assert not missing,missing

receipt={
 'status':'observation-and-design-complete; no product implementation',
 'completedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'humanSelectionCriterion':'Prioritize preserved semantics and proven net benefit; no zero-risk or guaranteed-FPS claim.',
 'report':str(report),'reportSHA256':sha(report),
 'detailedCandidate':{'id':'C-REG','scope':'Carry existing resource type through fresh recording registration and residency fallback.',
   'newCache':False,'crossRecordingOwnershipShared':False,'locksRemoved':False,'allocatorOrPassOrSyncChanged':False,
   'implemented':False,'FPSBenefitMeasured':False,'independentNewDesignReview':False},
 'held':['additional cross-recording payload/lease sharing','allocator limits/reset changes','pass/resolve merging','GPU barriers/query/completion waits'],
 'observations':observations,
 'sourcePackagePinsVerified':{'count':len(checks),'allExact':True,'reference':'v104-followup-c-t before excluding selected edits plus final review pins'},
 'rawLibrarySHA256':sha(raw),'packagedLibrarySHA256':sha(packaged),
 'currentReadSourcePins':'design-source-pins.json',
 'launcher':{'head':head,'indexSHA256':index_hash,'statusUnchanged':True,'statusSHA256':hashlib.sha256(status.encode()).hexdigest()},
 'screen':{'observations':len(screen),'allUnlocked':True,'lowPowerAndThermal0':True,'idleRestored':True,'awakeReleased':True},
 'cacheCleanup':{'roots':sum(x['rootsRemoved'] for x in cache),'leaves':sum(x['leavesRemoved'] for x in cache),'logicalBytes':sum(x['logicalBytesRemoved'] for x in cache),'rawEvidencePreserved':True},
 'newProductBuilds':0,'newProductEdits':0,'newGameObservations':2,'productTestSuitesRun':0,
 'installed':False,'stablePublished':False,'automationChanged':False,
 'limitations':analysis['limitations'],
 'scopeNote':'Current BAR MVK port only. Off-scope geometry call stacks recorded as a separate investigation lead.'}
save('design-receipt.json',receipt)

# Small, explicit restoration addendum: no app, game content, user profiles,
# caches, copied Apple documentation bodies, or unrelated files.
selected=[report]
selected += [p for p in OUT.iterdir() if p.is_file() and p.suffix in ('.json','.jsonl','.py','.lua','.txt','.cjs') and p.name not in ('restore-addendum-manifest.json',)]
selected += [OUT/'official/sources.json']
for item in outcome['results']:
    session=Path(item['receipt']).parent
    selected += [Path(item['receipt']),session/'cpu-sample.txt',session/'cpu-sample-stderr.txt']
    folder=session.parent.parent
    selected += [folder/'effective-host.mjs',folder/'plan.json']
selected=sorted(set(selected))
files=[{'path':str(p),'relativePath':str(p.relative_to(ROOT)),'sha256':sha(p),'bytes':p.stat().st_size} for p in selected]
save('restore-addendum-manifest.json',{'scope':'Read-only BAR cost observation and design followup; no implementation or FPS benefit claimed.',
 'files':files,'fileCount':len(files),'totalBytes':sum(x['bytes'] for x in files),
 'excluded':'App/native binary/game content/private profiles/caches and full third-party documentation bodies. Source read pins only; original source restoration checkpoint unchanged.'})
print(json.dumps({'status':receipt['status'],'pinsExact':len(checks),'launcherExact':True,'samples':len(observations),'cache':receipt['cacheCleanup'],
 'report':str(report),'restoreFiles':len(files),'restoreBytes':sum(x['bytes'] for x in files)},ensure_ascii=False))
