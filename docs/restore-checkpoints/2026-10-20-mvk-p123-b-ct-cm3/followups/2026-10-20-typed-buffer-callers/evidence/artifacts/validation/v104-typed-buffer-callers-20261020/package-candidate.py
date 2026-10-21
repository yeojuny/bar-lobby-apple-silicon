from pathlib import Path
import importlib.util, json, shutil

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, R / relative)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
m = module('package_helpers', 'tools/package-metal4-bar-candidate.py')
c = module('closure_helpers', 'tools/run95-package-stack.py')
read = lambda p: json.loads(p.read_text())
write = lambda p, d: p.write_text(json.dumps(d, indent=2, sort_keys=True) + '\n')
b = read(O / 'before.json'); pins = read(O / 'review-pins.json')
for rel, h in b['files'].items():
    assert m.sha(R / rel) == pins.get(rel, h), rel
assert all(row['exitCode'] == 0 for row in read(O / 'validation/syntax.json'))
build = read(O / 'validation/build.json'); assert build['exitCode'] == 0
assert read(O / 'cpu-registration/receipt.json')['result']['assertions'] == 410
first = read(O / 'validation/vulkan-receipt.json')
assert first['backends'][0]['result']['passed'] == 7
followup = read(O / 'validation/followup-receipt.json')
assert len(followup['backends']) == 2 and all(x['exitCode'] == 0 for x in followup['backends'])
baseline = read(O / 'validation/baseline-m3-exact-receipt.json')
assert baseline['validBaselineComparison'] and baseline['exitCode'] == 1
m3 = read(O / 'validation/m3-stdout.json')
assert baseline['result']['tests'][-1]['error'] == m3['tests'][-1]['error']
raw = R / 'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'
assert m.sha(raw) == build['rawLibrarySHA256']
parent = Path(b['parentApp']); app = R / 'artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app'
assert not app.parent.exists()
old = m.inventory(parent); assert old == read(O / 'parent-inventory.json')
m.run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(parent))
app.parent.mkdir(); m.run('/bin/cp', '-cR', str(parent), str(app)); assert m.inventory(app) == old
rel = 'Contents/Resources/bundled-assets/runtime/moltenvk-pr2746/lib/libMoltenVK.1.4.3.dylib'
target = app / rel
assert c.loads(raw) == c.loads(parent / rel) and c.rpaths(raw) == c.rpaths(parent / rel) == []
assert all(x.startswith(('/System/Library/', '/usr/lib/')) for x in c.loads(raw))
shutil.copy2(raw, target)
m.run('/usr/bin/install_name_tool', '-id', c.dylib_id(parent / rel), str(target))
m.run('/usr/bin/codesign', '--force', '--sign', '-', str(target))
assert c.loads(target) == c.loads(parent / rel) and c.dylib_id(target) == c.dylib_id(parent / rel)
assert m.text_sha(raw) == m.text_sha(target)
roots = [app / 'Contents/Resources/bundled-assets/engine' / v / 'spring' for v in ('2026.07.04', '2026.09.01-24-g01efdf4 master')]
edges = c.closure(roots, app); write(O / 'dependency-closure.json', edges)
m.run('/usr/bin/codesign', '--force', '--sign', '-', '--preserve-metadata=identifier,entitlements,requirements,flags,runtime', str(app))
m.run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
assert m.text_sha(app / 'Contents/MacOS/BAR') == m.text_sha(parent / 'Contents/MacOS/BAR')
after = m.inventory(app); assert set(old) == set(after)
changed = sorted(k for k in old if old[k] != after[k])
assert set(changed) == {rel, 'Contents/MacOS/BAR', 'Contents/_CodeSignature/CodeResources'}, changed
assert m.inventory(parent) == old
write(O / 'candidate-inventory.json', after)
receipt = dict(status='signed-local-candidate-review-pending', app=str(app), parent=str(parent), entries=len(after),
    changedFiles=changed, sourcePins=pins, rawLibrarySHA256=m.sha(raw), packagedLibrarySHA256=m.sha(target),
    deepStrictSignatureVerified=True, dependencyClosureEdges=len(edges), enginesAndLauncherCodeUnchanged=True,
    included='All previous cumulative changes including drawable-size helper + typed Buffer registration callsites',
    displayedVersion='1.0.3', candidateDesignation='local v1.0.4 candidate', CPUAssertions=410,
    Metal4Validation='7 initial cases + 2 followup cases passed; parallel byte-copy repeated once',
    Metal3Validation='7 common case outputs passed; timestamp host/GPU mismatch reproduced on exact unchanged baseline',
    knownUnresolved=['pre-existing Metal3 timestamp fixture mismatch', 'previous sampled BAR native-exit observation'],
    gameExecuted=False, FPSBenefitUnmeasured=True, installed=False, formalReleasePublished=False)
write(O / 'package-receipt.json', receipt)
print(json.dumps({k:v for k,v in receipt.items() if k != 'sourcePins'}))
