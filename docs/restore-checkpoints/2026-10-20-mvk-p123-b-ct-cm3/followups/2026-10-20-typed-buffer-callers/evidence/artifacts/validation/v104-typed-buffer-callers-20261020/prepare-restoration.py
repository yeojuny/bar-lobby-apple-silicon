from pathlib import Path
import hashlib, json

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda p: json.loads(p.read_text())
selected = {R / rel for rel in read(O / 'review-pins.json')}
selected.add(R / 'reports/v104-typed-buffer-callers-20261020.md')
selected.add(R / 'reports/v104-binding-cost-design-20261020.md')
for folder in (O, R / 'artifacts/validation/v104-binding-cost-analysis-20261020'):
    for p in folder.rglob('*'):
        if p.is_file() and '.dSYM' not in p.parts and not any(x.endswith('.dSYM') for x in p.parts) and p.suffix in ('.json', '.py', '.md', '.patch', '.log', '.mm', '.cpp', '.txt'):
            if p.name not in ('github-handoff.json', 'restoration-selection.json', 'publication-link.json'):
                selected.add(p)
package = read(O / 'package-receipt.json')
for rel in package['changedFiles']: selected.add(Path(package['app']) / rel)
# Include original test bodies selected by the local runner; no new compiled test binaries.
for rel in ('tools/tests/metal4-vulkan-integration.mm', 'tools/tests/metal4-transfer-edge.mm', 'tools/tests/metal4-recording-host-state.mm', 'tools/tests/metal4-r50-texture-registration-cpu.py'):
    selected.add(R / rel)
rows = []
for p in sorted(selected):
    assert p.is_relative_to(R) and p.is_file() and not p.is_symlink(), p
    rows.append(dict(path=str(p.relative_to(R)), sha256=sha(p), bytes=p.stat().st_size, mode=p.stat().st_mode & 511))
manifest = dict(status='frozen-exact-selection', scope='typed Buffer callsites, design and validation including baseline failures, signed app delta from drawable-size candidate',
    baseRestoreCommit='7ca6c11f457f59681c0dde6a927aabea24ac9c50', baseApp=package['parent'], candidateApp=package['app'],
    appDelta=package['changedFiles'], candidateInventory=str((O / 'candidate-inventory.json').relative_to(R)),
    files=rows, fileCount=len(rows), totalBytes=sum(x['bytes'] for x in rows))
(O / 'restoration-selection.json').write_text(json.dumps(manifest, indent=2) + '\n')
handoff = dict(status='ready-for-existing-authorized-publisher', repository='yeojuny/bar-lobby-apple-silicon', branch='restore/mvk-20261020-p123-b-ct-cm3',
    knownParent=manifest['baseRestoreCommit'], selectedManifest=dict(path=str(O / 'restoration-selection.json'), sha256=sha(O / 'restoration-selection.json')),
    review=str(O / 'independent-review.json'), completion=str(O / 'completion.json'), report=str(R / 'reports/v104-typed-buffer-callers-20261020.md'),
    publishOnlyRestorationBranch=True, formalReleaseHomebrewRequested=False, newBuildOrGameRequested=False, sourceOrAppEditingRequested=False,
    snapshotBytesImmutable=True, FPSBenefitMeasured=False,
    preserveQualifications=['Metal3 timestamp mismatch reproduced with exact prior library; not fixed', 'previous sampled BAR native-exit failure unresolved', 'no new BAR game or FPS measurement'],
    avoidDuplicateBinaries='Only three signed app delta entries included; new raw library and compiled fixture executables are not needed for restoring the signed app and are not selected.')
(O / 'github-handoff.json').write_text(json.dumps(handoff, indent=2) + '\n')
print(json.dumps(dict(files=len(rows), bytes=manifest['totalBytes'])))
