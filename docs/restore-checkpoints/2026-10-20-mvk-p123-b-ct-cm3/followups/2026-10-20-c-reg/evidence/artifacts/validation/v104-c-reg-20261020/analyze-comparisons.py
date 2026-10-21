from pathlib import Path
import json,hashlib,statistics,subprocess,importlib.util,plistlib
R=Path(__file__).resolve().parents[3];I=Path(__file__).resolve().parent
read=lambda p:json.loads(Path(p).read_text());sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n')
comparisons=[]
for name,fullscreen in [('v104-c-reg-performance-20261020',False),('v104-c-reg-fullscreen-reverse-20261020',True)]:
 O=R/'artifacts/validation'/name;out=read(O/'outcome.json');prep=read(O/'preparation.json');assert out['status']=='completed' and len(out['results'])==8
 records=[];power=[];conditions=[]
 for row in out['results']:
  receipt=Path(row['receipt']);d=read(receipt);b=d['benchmark'];assert d['status']=='completed-not-promoted' and d['protectedInputsUnchanged'] and not d['remainingOwnedProcesses'] and d['powerConditionsPassed']
  assert d['loadedRuntimeLibraries']['verified'] and d['strictHiddenWindow']
  assert b['benchmark']['simulationFrames']==900 and b['benchmark']['startFrame']==240 and b['benchmark']['endFrame']==1140
  assert b['resolution']==({'width':1512,'height':950} if fullscreen else {'width':1432,'height':902})
  native=d['nativeMetal4'];assert native['requested']==(row['backend']=='metal4')
  if row['backend']=='metal4':assert native['proved'] and native['activeQueues']>=1
  else:assert native['activeQueues']==0
  if fullscreen:
   f=d['fullscreenMode'];assert f['gameFullscreen'] and f['SDLFullscreen'] and f['SDLHidden'] and f['viewport']==b['resolution'] and f['window']=={'width':1512,'height':982}
  for q in d['powerObservations']:
   assert q['passed'] and q['isLowPowerModeEnabled'] and "'AC Power'" in q['battery'];power.append(q['thermalState'])
  condition={k:b[k] for k in ('camera','resolution','game','map','seed','officialCommand')};condition['qualityConfig']=b['quality']['config'];condition['qualityOptions']=b['quality']['optionValues'];conditions.append(condition)
  assert b['quality']['ultraVerified'] and b['quality']['glSamples']==0
  actualLib=next(x for x in d['loadedRuntimeLibraries']['libraries'] if 'libMoltenVK.' in x['path'])
  expectedLib=prep['parentMvk'] if row['role']=='parent' else prep['candidateMvk'];assert actualLib==expectedLib
  records.append({**row,'receiptSHA256':sha(receipt),'library':actualLib,'frameCount':900,'drawIntervals':b['benchmark']['drawIntervals'],'fullscreenMode':d.get('fullscreenMode'),'officialNativeReport':d['officialNativeReport']})
 assert all(x==conditions[0] for x in conditions),'Workload or quality differs'
 groups={}
 for backend in ('metal3','metal4'):
  groups[backend]={}
  for role in ('parent','candidate'):
   rows=[x for x in records if x['backend']==backend and x['role']==role];assert len(rows)==2
   groups[backend][role]={'ordinals':[x['ordinal'] for x in rows],'fps':[x['fps'] for x in rows],'meanFPS':statistics.mean(x['fps'] for x in rows),'meanRunP95Ms':statistics.mean(x['p95Ms'] for x in rows),'meanRunP99Ms':statistics.mean(x['p99Ms'] for x in rows),'minFPS':min(x['fps'] for x in rows),'maxFPS':max(x['fps'] for x in rows)}
  p,c=groups[backend]['parent'],groups[backend]['candidate'];groups[backend]['deltaFPSPercent']=(c['meanFPS']/p['meanFPS']-1)*100;groups[backend]['deltaP95Percent']=(c['meanRunP95Ms']/p['meanRunP95Ms']-1)*100
 clean=[read(O/f'arm-{i}-cache-cleanup-completion.json') for i in range(1,9)];assert all(x['allAbsent'] for x in clean)
 guard=read(O/'screen-guard.json');assert guard['restored'] and guard['awakeReleased'] and guard['afterIdleTime']==guard['beforeIdleTime']
 result={'status':'completed','evidence':str(O),'fullscreenGame':fullscreen,'nativeDisplayPresentationDeferredWhileHidden':fullscreen,'resolution':conditions[0]['resolution'],'order':prep['order'],'groups':groups,'records':records,'conditions':conditions[0],'thermalStates':sorted(set(power)),'powerObservationCount':len(power),'allAppsAndInputsUnchangedPerRun':True,'loadedLibraryIdentityVerifiedPerRun':True,'screenGuardRestored':True,'cacheCleanup':{'roots':sum(x['rootsRemoved'] for x in clean),'leaves':sum(x['leavesRemoved'] for x in clean),'logicalBytes':sum(x['logicalBytesRemoved'] for x in clean),'physicalBytesNotMeasured':True},'summaryMethod':'Arithmetic mean of two run FPS; p95/p99 are means of per-run percentiles, not pooled percentiles. No statistical significance claimed.'}
 save(O/'comparison-summary.json',result);comparisons.append(result)
# Final protection check after all game sessions finish.
before=read(I/'before.json');review=read(I/'independent-review.json');assert review['findings']==[]
for n,h in before['files'].items():
 if n not in before['selectedEdits']:assert sha(R/n)==h,n
for n,h in review['reviewedPins'].items():assert sha(R/n)==h,n
launcher=R/'sources/bar-lobby';assert subprocess.check_output(['git','-C',str(launcher),'rev-parse','HEAD'],text=True).strip()==before['launcher']['head'];assert sha(launcher/'.git/index')==before['launcher']['index'];assert subprocess.check_output(['git','-C',str(launcher),'status','--porcelain=v1'],text=True)==before['launcher']['status']
O=R/'artifacts/validation/v104-c-reg-fullscreen-reverse-20261020';protected=read(O/'protected-inputs.json')
for pin in protected['userState'].values():assert sha(Path(pin['path']))==pin['sha256']
spec=importlib.util.spec_from_file_location('inventory',R/'tools/lib/run95_app_transaction.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
prep=read(O/'preparation.json');versions={}
for role in ('parent','candidate'):
 app=Path(prep[role]);assert m.inventory(app)==read(O/(role+'-inventory.json'))
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes());versions[role]={'app':str(app),'CFBundleShortVersionString':info.get('CFBundleShortVersionString'),'CFBundleVersion':info.get('CFBundleVersion')}
result={'status':'implemented-reviewed-validated-and-compared','product':'C-REG on cumulative P1/P2/P3+B+C-T+C-M3','sourcePins':review['reviewedPins'],'appVersions':versions,'validation':read(I/'validation-summary.json'),'review':{'status':review['status'],'path':str(I/'independent-review.json'),'sha256':sha(I/'independent-review.json')},'comparisons':[{'path':x['evidence']+'/comparison-summary.json','fullscreenGame':x['fullscreenGame'],'resolution':x['resolution'],'groups':x['groups']} for x in comparisons],'allProtectedPinsAndAppsExact':True,'launcherHeadIndexStatusExact':True,'userProfilesExact':True,'formalReleasePublished':False,'restorationCheckpoint':'pending'}
save(I/'completion.json',result)
print(json.dumps({'comparisons':result['comparisons'],'versions':versions,'protectedInputs':'exact'},ensure_ascii=False))
