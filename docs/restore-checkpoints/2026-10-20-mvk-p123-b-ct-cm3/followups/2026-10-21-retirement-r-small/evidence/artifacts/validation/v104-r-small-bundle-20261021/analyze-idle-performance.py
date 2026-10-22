from pathlib import Path
import json,hashlib,statistics,subprocess,datetime,importlib.util,sys
R=Path(__file__).resolve().parents[3];TASK=Path(__file__).resolve().parent;P=TASK/sys.argv[1];assert P.name in ('performance-idle-forward','performance-idle-reverse');O=P;read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
before=read(TASK/'performance-before.json');prep=read(P/'preparation.json');outcome=read(P/'outcome.json')
order=[('metal4',x) for x in ['R','Small','Small','R']]+[('metal3',x) for x in ['Small','R','R','Small']]
if P.name.endswith('reverse'):order.reverse()
roles=[x[1] for x in order]
assert sha(P/'run-comparison.py')==prep['runnerSHA256'] and sha(P/'idle-input-guard.py')==prep['idleHelperSHA256']
specidle=importlib.util.spec_from_file_location('idle',P/'idle-input-guard.py');idle=importlib.util.module_from_spec(specidle);specidle.loader.exec_module(idle)
labels={'R':'R','Small':'R+bounded-positive-reserve'}
assert outcome['status']=='completed' and len(outcome['results'])==8
assert [p['role'] for p in prep['plans']]==roles
assert subprocess.check_output(['/usr/bin/sw_vers'],text=True)==before['osSwVers']
rows=[];powers=[];conditions=None
for item,a in zip(prep['plans'],outcome['results']):
 assert (item['backend'],item['role'])==order[item['ordinal']-1]
 window=read(P/f'arm-{item["ordinal"]}-input-window.json');assert window['noInputObserved'] and idle.assert_input_idle_window(P,a['receipt'])==window
 assert a['ordinal']==item['ordinal'] and a['role']==item['role'] and a['backend']==item['backend']
 for k in ['plan','host']:assert sha(item[k]['path'])==item[k]['sha256']
 plan=read(item['plan']['path']);r=read(a['receipt']);b=r['benchmark'];m=b['benchmark']
 assert r['status']=='completed-not-promoted' and r['protectedInputsUnchanged'] and r['powerConditionsPassed'] and not r['remainingOwnedProcesses']
 assert r['loadedRuntimeLibraries']['verified'] and r['runtimeEnvironment']['diagnosticsOff']
 assert r['app']==before['apps'][item['role']]
 assert (m['startFrame'],m['endFrame'],m['simulationFrames'])==(240,1140,900)
 assert b['resolution']==dict(width=1512,height=950) and b['camera']['name']=='spring'
 assert r['fullscreenMode']['window']==dict(width=1512,height=982) and r['fullscreenMode']['viewport']==dict(width=1512,height=950)
 assert all(r['fullscreenMode'][k] for k in ['gameFullscreen','SDLFullscreen','SDLHidden']) and r['officialNativeReport']['present']
 if item['backend']=='metal4':assert r['nativeMetal4']['requested'] and r['nativeMetal4']['proved'] and r['nativeMetal4']['activeQueues']>0
 else:assert not r['nativeMetal4']['requested'] and r['nativeMetal4']['activeQueues']==0
 actual={k:b[k] for k in ['quality','camera','resolution','seed','workload','officialCommand','game','map']}
 if conditions is None:conditions=actual
 assert actual==conditions
 expected={p['path']:p['sha256'] for p in plan['sharedRuntime']}
 for lib in r['loadedRuntimeLibraries']['libraries']:assert lib['sha256']==expected[lib['path']]
 mvk=[lib for lib in r['loadedRuntimeLibraries']['libraries'] if lib['path'].endswith('/libMoltenVK.1.4.3.dylib')];assert len(mvk)==1 and mvk[0]['sha256']==before['packageSHA256'][item['role']]
 for p in r['powerObservations']:
  assert p['passed'] and p['isLowPowerModeEnabled'] and "'AC Power'" in p['battery'];powers.append(dict(ordinal=item['ordinal'],thermal=p['thermalState']))
 assert a['fps']==m['drawIntervals']['meanFPS']
 rows.append(dict(ordinal=item['ordinal'],role=item['role'],label=labels[item['role']],backend=item['backend'],app=r['app'],displayedVersion='1.0.3',localCandidate='v1.0.4',FPS=a['fps'],p95Ms=a['p95Ms'],p99Ms=a['p99Ms'],drawIntervals=m['drawIntervals']['count'],simulationFrames=900,receipt=a['receipt'],receiptSHA256=sha(a['receipt']),loadedMoltenVKSHA256=mvk[0]['sha256'],benchmarkStartUnixMS=r['timing']['benchmarkStartUnixMS']))
assert conditions==read(R/'artifacts/validation/v104-group-lookup-performance-20261021/comparison-summary.json')['conditions']
groups={}
for backend in ['metal3','metal4']:
 g={}
 for role in ['R','Small']:
  rr=[r for r in rows if r['role']==role and r['backend']==backend];assert len(rr)==2
  g[role]=dict(FPS=[r['FPS'] for r in rr],meanFPS=statistics.mean(r['FPS'] for r in rr),meanP95Ms=statistics.mean(r['p95Ms'] for r in rr),ordinals=[r['ordinal'] for r in rr])
 for role,a in g.items():a['changeFromRPercent']=(a['meanFPS']/g['R']['meanFPS']-1)*100
 groups[backend]=g
for rel,h in before['sourcePins'].items():assert sha(R/rel)==h,rel
assert sha(R/'build/metal4-mvk-20261002/CMakeCache.txt')==before['CMakeCacheSHA256']
assert sha(R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib')==before['rawSHA256']
assert read(R/'artifacts/runtime/v104-local-candidate.json')==before['currentCandidate']
for role,app in before['apps'].items():assert sha(Path(app)/before['libraryRelativePath'])==before['packageSHA256'][role]
for p in read(P/'protected-inputs.json')['userState'].values():assert sha(p['path'])==p['sha256']
src=read(P/'protected-source-launcher.json');launcher=R/'sources/bar-lobby'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=launcher,text=True).strip()==src['HEAD']
assert sha(launcher/'.git/index')==src['indexSHA256'] and subprocess.check_output(['git','status','--short'],cwd=launcher,text=True)==src['status']
spec=importlib.util.spec_from_file_location('inv',R/'tools/lib/run95_app_transaction.py');inv=importlib.util.module_from_spec(spec);spec.loader.exec_module(inv)
for role,app in before['apps'].items():assert inv.inventory(Path(app))==read(TASK/(role+'-inventory.json'))
guard=read(P/'screen-guard.json');assert guard['restored'] and guard['awakeReleased']
cleanup=[read(P/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,9)];assert all(c['allAbsent'] for c in cleanup)
summary=dict(status='completed-input-idle-R-bounded-reserve-Metal3-Metal4-comparison',orderDirection=P.name,noInputDuringMeasuredWindows=True,OSLoadObservedNotEliminated=True,groups=groups,executionOrder=rows,apps=prep['apps'],conditions=conditions,nPerAppPerBackend=2,powerObservations=len(powers),thermalStates=sorted(set(p['thermal'] for p in powers)),osSwVers=before['osSwVers'],sourceBuildFrozen=True,bothAppInventoriesExact=True,userProfilesAndLauncherExact=True,screenRestored=True,awakeReleased=True,selectedCandidate='R-unchanged',cleanup=dict(roots=sum(c['rootsRemoved'] for c in cleanup),leaves=sum(c['leavesRemoved'] for c in cleanup),logicalBytes=sum(c['logicalBytesRemoved'] for c in cleanup),physicalBytesMeasured=False),limitations=['n2 per app/backend within each batch; HID idle and pre-arm CPU gates passed, but background load/clocks not fully controlled.','Per-run FPS and p95 arithmetic means; no historical FPS pooled.','Bounded reserve is tested on exact R. Code work reduction is not a causal FPS gain.','Late capture failure can retain greater temporary capacity, bounded by16resources; no peak-memory benefit established.','Existing sampled native-exit and timestamp fixture failures not claimed repaired.'])
(O/'comparison-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
(O/'performance-completion.json').write_text(json.dumps(dict(status='comparison-completed-awaiting-independent-data-review',completedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),summarySHA256=sha(O/'comparison-summary.json'),groups=groups,gameSessions=8,selectedCandidateUnchanged=True,candidatePromoted=False),indent=2)+'\n')
print(json.dumps(groups,indent=2))
