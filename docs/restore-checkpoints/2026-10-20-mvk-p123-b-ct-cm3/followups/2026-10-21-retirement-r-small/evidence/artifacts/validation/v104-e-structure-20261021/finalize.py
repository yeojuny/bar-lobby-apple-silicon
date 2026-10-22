from pathlib import Path
import json,hashlib,importlib.util,difflib,datetime
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();g=json.loads((O/'root-source-build-grant.json').read_text());p=json.loads((O/'proposal.json').read_text())
s=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
protected={
'C':(R/'artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app',R/'artifacts/validation/v104-typed-buffer-callers-20261020/candidate-inventory.json'),
'D':(R/'artifacts/runtime/v104-lookup-descriptor-release-20261020/BAR.app',R/'artifacts/validation/v104-lookup-descriptor-20261020/release-inventory.json'),
'L':(R/'artifacts/runtime/v104-d-split-lookup-only-20261021/BAR.app',R/'artifacts/validation/v104-d-split-20261021/L-inventory.json'),
'S':(R/'artifacts/runtime/v104-d-split-stats-only-off-20261021/BAR.app',R/'artifacts/validation/v104-d-split-20261021/S-inventory.json'),
'E32':(Path(g['E32App']),O/'E32-inventory.json'),
'E64':(Path(g['E64App']),O/'E64-inventory.json')}
apps={}
for k,(a,manifest) in protected.items():
 inv=m.inventory(a);assert inv==json.loads(manifest.read_text()),k;apps[k]=dict(app=str(a),entries=len(inv),inventory=str(manifest),inventorySHA256=sha(manifest),exact=True)
for f,h in p['E64Pins'].items():assert sha(B/f)==h,f
assert sha(R/'build/metal4-mvk-20261002/CMakeCache.txt')==g['CMakeCacheSHA256']
unchanged={f:h for f,h in g['sourcePins'].items() if f not in ['build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.h','build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/MVKCommandEncoderState.mm']}
for f,h in unchanged.items():assert sha(R/f)==h
patch='';different=[]
for f in p['E64Pins']:
 a=(O/'source-states/E32'/f).read_text();b=(O/'source-states/E64'/f).read_text()
 if a!=b:
  different.append(f);patch+=''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile='E32/'+f,tofile='E64/'+f))
assert different==['GPUObjects/MVKMetal4Submission.h']
removed=[s for s in patch.splitlines() if s.startswith('-') and not s.startswith('---')];added=[s for s in patch.splitlines() if s.startswith('+') and not s.startswith('+++')]
assert removed==['-    static constexpr uint32_t maxAllocatorEpochRecordings = 32;']
assert added==['+    static constexpr uint32_t maxAllocatorEpochRecordings = 64;']
(O/'E32-to-E64.patch').write_text(patch)
raw=R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib';e64=json.loads((O/'E64-package.json').read_text());assert sha(raw)==e64['rawSHA256']
(O/'E64-build.json').write_text(json.dumps(dict(exitCode=0,log=str(O/'E64-build-1.log'),rawSHA256=sha(raw),sourcePins=p['E64Pins'],diagnosticsCompile=0),indent=2)+'\n')
fixtures={str(f.relative_to(R)):sha(f) for f in [R/'tools/tests'/n for n in ['metal4-suspend-resolve-cpu.mm','metal4-visibility-recycle-cpu.mm','metal4-counter-completion-cpu.mm','metal4-r49-lifetime-native.mm','metal4-queue-barrier-reuse-cpu.mm']]}
fixturepatch=''
for f in fixtures:
 fp=R/f;backup=O/'fixture-preimage'/fp.name;old=backup.read_text() if backup.exists() else '';new=fp.read_text()
 fixturepatch+=''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+f if backup.exists() else '/dev/null',tofile='b/'+f))
(O/'fixtures.patch').write_text(fixturepatch)
bindings=dict(apps=apps,sourcePins=p['E64Pins'],fixturePins=fixtures,rawSHA256=sha(raw),CMakeCacheSHA256=g['CMakeCacheSHA256'],E32E64DifferentProductFiles=different,countOnly=True,DUnchangedPins=unchanged,diagnosticsCompile=0)
(O/'final-bindings.json').write_text(json.dumps(bindings,indent=2)+'\n')
for path in ['cpu-complete.json','gpu-complete.json','visibility/completion.json','allocator-32/completion.json','allocator-64/completion.json']:
 assert json.loads((O/path).read_text())['status']=='passed',path
assert 'PASS 2097163 checks;' in (O/'cpu/queue-barrier-run.log').read_text()
assert json.loads((O/'protected-state.json').read_text())['launcherStatusExact']
report=R/'reports/v104-e-structure-20261021.md';assert report.exists()
result=dict(status='implementation-build-validation-packaging-complete-awaiting-root-review-and-performance',completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
 ownerThread=g['ownerThread'],sourceBuildOwnerReleased=True,sourceBuildFinal='E64',report=str(report),reportSHA256=sha(report),
 gate=str(O/'root-source-build-grant.json'),gateSHA256=sha(O/'root-source-build-grant.json'),finalBindings=str(O/'final-bindings.json'),finalBindingsSHA256=sha(O/'final-bindings.json'),
 E32Package=str(O/'E32-package.json'),E64Package=str(O/'E64-package.json'),apps=apps,rawSHA256=sha(raw),CMakeCacheSHA256=g['CMakeCacheSHA256'],sourcePins=p['E64Pins'],
 validation=dict(planMetadataCases=432,planBytes=32,resourceBindingBytes=40,descriptorDefaultsSubpassAssertions=20728,descriptorExistingCases=629,
 actualVisibilityBodies=dict(foundation1sdk26=196941,foundation0sdk26=196842,foundation0oldSDK=196761),
 actualQueueEmissionAndComputeLocalBlockAssertions=2097163,dependencyScopesAssertions=524606,preparedDependencyAssertions=4916882,
 E32VulkanGPU=dict(Metal3=15,Metal4=15),allocatorCPU=dict(E32=812,E64=1580),allocatorNative=dict(E32=dict(cases=5,batches=80,resets=5),E64=dict(cases=5,batches=160,resets=5))),
 preserved=dict(apps=['C','D','L','S','E32','E64'],launcherAndUserPins=str(O/'protected-state.json'),engineMesaLuaUnchanged=True),
 diagnosticsCompile=0,allocatorDiagnosticsCreated=False,allocatorChangedOnlyCount=True,gameExecuted=False,FPSMeasured=False,installed=False,published=False,
 remaining=['Root independent final applied-code/output review','Root C/E32/E64 x Metal3/Metal4 x two comparisons'],
 limitations=['Plan 432 cases exercise exact plan metadata, not full binder calls; compatible layouts/revision/recording are checked through Vulkan.',
 '20728 assertions cover real descriptor defaults and production subpass/software-resolve bodies, not all outer encoder state.',
 'Visibility initialization, failure and lease reuse use separately extracted actual typed production method with CPU mocks.',
 'Outer extent/layer/sample placement is preserved by extraction/source review; custom sample patterns not newly GPU-tested.',
 'No claim of BAR FPS improvement or peak-memory benefit. Growth threshold is not a total allocator memory cap.',
 'Historical M3 timestamp mismatch and sampled-exit failure were not rerun or closed.'])
(O/'completion.json').write_text(json.dumps(result,indent=2)+'\n')
print('Complete: source/build E64 frozen; C/D/L/S/E32/E64 inventories exact; root owns review and FPS.')
