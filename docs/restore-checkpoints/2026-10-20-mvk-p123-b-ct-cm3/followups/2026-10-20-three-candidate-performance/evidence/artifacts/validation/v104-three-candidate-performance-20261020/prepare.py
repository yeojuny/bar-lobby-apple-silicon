from pathlib import Path
import hashlib, importlib.util, json, plistlib, shutil, subprocess

R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
OLD = R / 'artifacts/validation/v104-drawable-size-performance-20261020'
read = lambda p: json.loads(Path(p).read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
pin = lambda p: {'path': str(p), 'sha256': sha(p)}
def save(p, value):
    with p.open('x') as f: json.dump(value, f, indent=2, ensure_ascii=False); f.write('\n')
old = read(OLD / 'preparation.json')
assert read(OLD / 'outcome.json')['status'] == 'completed'
apps = {
    'A': R / 'artifacts/runtime/v104-c-reg-candidate-20261020/BAR.app',
    'B': R / 'artifacts/runtime/v104-drawable-size-candidate-20261020/BAR.app',
    'C': R / 'artifacts/runtime/v104-typed-buffer-callers-candidate-20261020/BAR.app',
}
descriptions = {'A': 'P1/P2/P3+B+C-T+C-M3+C-REG', 'B': 'A + live window/drawable size query', 'C': 'B + typed Buffer registration callers'}
for name in ('controller.lua', 'scene.txt', 'benchmark-bootstrap.cjs', 'metal-bootstrap.cjs', 'content-files.json',
             'content-receipt.json', 'launcher-main-sha256.json', 'screen-guard-locked-allowed.py',
             'libhidden-fullscreen.dylib', 'sdl-hidden-preflight.json', 'inventory-digest.mjs'):
    shutil.copy2(OLD / name, O / name)
shutil.copytree(OLD / 'inputs', O / 'inputs')
runner = (OLD / 'run-comparison.py').read_text()
runner = runner.replace("assert len(prep['plans'])==8", "assert len(prep['plans'])==12")
runner = runner.replace("item['ordinal']<8", "item['ordinal']<12")
runner = runner.replace('len(results)==8', 'len(results)==12').replace("'maximumGameSessions':8", "'maximumGameSessions':12")
(O / 'run-comparison.py').write_text(runner)
assert sha(O/'controller.lua') == sha(OLD/'controller.lua')
spec = importlib.util.spec_from_file_location('inventory', R / 'tools/lib/run95_app_transaction.py')
inventory = importlib.util.module_from_spec(spec); spec.loader.exec_module(inventory)
saved = {'A': R/'artifacts/validation/v104-c-reg-20261020/candidate-inventory.json',
         'B': R/'artifacts/validation/v104-drawable-size-20261020/candidate-inventory.json',
         'C': R/'artifacts/validation/v104-typed-buffer-callers-20261020/candidate-inventory.json'}
digests = {}; identities = {}
for role, app in apps.items():
    contents = inventory.inventory(app); assert contents == read(saved[role]), role
    save(O / (role + '-inventory.json'), contents)
    digests[str(app)] = subprocess.check_output(['/opt/homebrew/bin/node', str(O/'inventory-digest.mjs'), str(app)], text=True).strip()
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    identities[role] = dict(app=str(app), label=descriptions[role], version=info.get('CFBundleShortVersionString'),
        inventoryDigest=digests[str(app)], entries=len(contents))
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
protected = read(OLD/'protected-inputs.json'); protected['apps'] = digests
for entry in protected['userState'].values(): entry['sha256'] = sha(entry['path'])
save(O/'protected-inputs.json', protected)
launcher = R/'sources/bar-lobby'
sourcePins = {}
for file in ('v104-typed-buffer-callers-20261020/review-pins.json', 'v104-drawable-size-20261020/review-pins.json'):
    sourcePins.update(read(R/'artifacts/validation'/file))
for name, h in sourcePins.items(): assert sha(R/name)==h, name
save(O/'protected-source-launcher.json', dict(sourcePins=sourcePins,
    HEAD=subprocess.check_output(['git','rev-parse','HEAD'], cwd=launcher, text=True).strip(),
    indexSHA256=sha(launcher/'.git/index'), status=subprocess.check_output(['git','status','--short'], cwd=launcher, text=True)))
order = [('metal3', r) for r in ('A','B','C','C','B','A')] + [('metal4', r) for r in ('C','B','A','A','B','C')]
save(O/'authorization.json', dict(humanTask='Compare previous/drawable-size/typed-buffer candidates on Metal3 and Metal4, AC + Low Power, notch-excluded fullscreen rendering with hidden windows.',
    order=order, maximumGameSessions=12, retries=False, productChanges=False, sampler=False, cachePolicy='fresh private profile and cold cache per session; retire only successful-session regenerable caches after exit verification',
    resolution='1512x982 logical container, 1512x950 safe viewport, default 1x; SDL native display/Space presentation deferred while hidden'))
plans = []
for ordinal, (backend, role) in enumerate(order,1):
    templateRole = 'parent' if role=='A' else 'candidate'
    template = next(p for p in old['plans'] if p['role']==templateRole and p['backend']==backend)
    folder = O/f'{ordinal}-{role}-{backend}'; folder.mkdir()
    schema = f'v104-three-candidate-{ordinal}-{role}-{backend}-v1'
    app = apps[role]; templateApp = old[templateRole]
    def adapt(text):
        return text.replace(template['folder'],str(folder)).replace(str(OLD),str(O)).replace(template['schema'],schema).replace(templateApp,str(app))
    plan = json.loads(adapt(Path(template['plan']['path']).read_text()))
    plan.update(benchmarkRole={'A':'parent','B':'r41','C':'r42'}[role], comparisonVariant=role,
        testIdentity=folder.name, authorization=pin(O/'authorization.json'),
        protectedApps=[{'app':a,'inventorySha256':h} for a,h in digests.items()],
        limits=['Three cumulative frozen candidates; 12 sessions, reversed order, no retries',
                'Identical controller/scene/seed/settings/cache policy/fullscreen guard; no sampler or diagnostics',
                'A->B isolates drawable-size helper; B->C isolates typed Buffer callers; no app/source changes during measurement'])
    plan['app'] = dict(app=str(app), inventorySha256=digests[str(app)])
    for rel, data in plan['lanes'].items():
        data['engine']['sha256']=sha(data['engine']['path']);data['engine']['bytes']=Path(data['engine']['path']).stat().st_size
    plan['buildDigest']=plan['lanes']['lobby']['engine']['sha256']
    host = adapt(Path(template['host']['path']).read_text())
    hostfile = folder/'effective-host.mjs';hostfile.write_text(host)
    def repin(value):
        if isinstance(value,list):return [repin(v) for v in value]
        if isinstance(value,dict):
            result={k:repin(v) for k,v in value.items()}
            if 'path' in result and 'sha256' in result:result['sha256']=sha(result['path'])
            return result
        return value
    plan=repin(plan)
    assert plan['nativeMetal4']==(backend=='metal4')
    assert plan['gameFullscreen'] and plan['expectedDrawable']=={'width':1512,'height':950}
    save(folder/'plan.json', plan)
    subprocess.run(['/opt/homebrew/bin/node','--check',str(hostfile)], check=True, capture_output=True)
    plans.append(dict(ordinal=ordinal,role=role,backend=backend,folder=str(folder),schema=schema,plan=pin(folder/'plan.json'),host=pin(hostfile)))
save(O/'preparation.json', dict(plans=plans,apps=identities,previousEvidence=str(OLD),order=order,
    controllerUnchanged=True, hostChanges='Only private paths, schema, allowed historical three-runtime role labels and selected app/engine/runtime pins; no measurement/shutdown/hidden contract changes.',
    resolution={'width':1512,'height':950}, noHistoricalFPSPooled=True, newPremeasurementDeletion=False))
spec=importlib.util.spec_from_file_location('screen',O/'screen-guard-locked-allowed.py'); screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
assert screen.power()=={'lowPower':True,'thermal':0}
assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
save(O/'preflight.json',dict(power=screen.power(),desktop=screen.desktop(),screenIdle=screen.idle(),
    appInventoriesAndSignaturesPassed=3, nodeHostSyntaxPassed=12, uptime=subprocess.check_output(['/usr/bin/uptime'],text=True)))
print(json.dumps(dict(prepared=len(plans),apps=identities),ensure_ascii=False))
