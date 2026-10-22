from pathlib import Path
import json,statistics
O=Path(__file__).resolve().parent;D=O/'diagnostic';out=json.loads((D/'outcome.json').read_text());assert out['status']=='completed' and len(out['results'])==3
summaries=[];selected=[];excluded=[];counterRecords=[]
for a in out['results']:
 r=json.loads(Path(a['receipt']).read_text());assert r['status']=='completed-not-promoted' and r['protectedInputsUnchanged'] and r['powerConditionsPassed'] and not r['remainingOwnedProcesses'];on=a['ordinal']==2;assert r['runtimeEnvironment']['diagnosticsOff']==(not on)
 summaries.append(dict(ordinal=a['ordinal'],collector=on,FPS=a['fps'],p95Ms=a['p95Ms'],receipt=a['receipt']))
 if not on:continue
 log=Path(a['receipt']).parent/'state/data/stack-game.stderr.log';text=log.read_text();records=[json.loads(line.split('] ',1)[1]) for line in text.splitlines() if line.startswith('[mvk-backend-cost] ')];assert records
 start=r['timing']['benchmarkStartUnixMS'];end=r['timing']['benchmarkFinishUnixMS'];fields=['indirectGroupChecks','indirectGroupHits','indirectGroupPreparations','groupRecordingPartial','groupSnapshotFull','groupSnapshotPartial','bindingVisits','bindingBufferHits','textureCacheHits','bindingSnapshotHits','bindingSlowSuccess','bindingResidualVisits','bindingSlowResourceSlots','drawCalls']
 for qi,q in enumerate(records):
  assert q['invalid_encoding']==0
  for raw in q['bins']:
   row=dict(zip(q['columns'],raw));lo=q['unix_anchor_ms']+row['second']*1000;hi=lo+1000;row.update(queueRecord=qi,beginUnixMS=lo,endUnixMS=hi)
   if lo>=start and hi<=end and row['encoding_record_count']>0:counterRecords.append(row)
   else:excluded.append(dict(queueRecord=qi,second=row['second'],reason='outside full contained measurement bin or no encoding delivery'))
 # Select the first 20 fully-contained one-second delivery bins, across all
 # queues. Group by whole-second offset relative to benchmark start before sum.
 groups={}
 for row in counterRecords:
  slot=int((row['beginUnixMS']-start)//1000);groups.setdefault(slot,[]).append(row)
 slots=sorted(groups)[:20];assert len(slots)>=10,('insufficient-full-bins',len(slots))
 selected=[row for slot in slots for row in groups[slot]]
 unselected=[row for slot in sorted(groups) if slot not in slots for row in groups[slot]]
 for row in selected:
  assert row['bindingVisits']==row['bindingBufferHits']+row['textureCacheHits']+row['bindingSnapshotHits']+row['bindingSlowSuccess']
  assert row['bindingResidualVisits']<=row['bindingVisits']
 totals={f:sum(row[f] for row in selected) for f in fields};totalFull=totals['indirectGroupHits']+totals['groupSnapshotFull'];partial=totals['groupRecordingPartial']+totals['groupSnapshotPartial'];assert totalFull+partial<=totals['indirectGroupChecks']
 def ratio(n,d):return n/d if d else None
 ratios=dict(fullGroupFraction=ratio(totalFull,totals['indirectGroupChecks']),partialGroupFraction=ratio(partial,totals['indirectGroupChecks']),wholeWalkGroupFraction=ratio(totals['indirectGroupChecks']-totalFull-partial,totals['indirectGroupChecks']),bindingBufferHitFraction=ratio(totals['bindingBufferHits'],totals['bindingVisits']),bindingTextureHitFraction=ratio(totals['textureCacheHits'],totals['bindingVisits']),bindingSnapshotHitFraction=ratio(totals['bindingSnapshotHits'],totals['bindingVisits']),bindingSlowSuccessFraction=ratio(totals['bindingSlowSuccess'],totals['bindingVisits']),bindingResidualVisitFraction=ratio(totals['bindingResidualVisits'],totals['bindingVisits']))
offs=[x['FPS'] for x in summaries if not x['collector']];on=next(x['FPS'] for x in summaries if x['collector']);summary=dict(status='completed',runs=summaries,OFFMeanFPS=statistics.mean(offs),ONFPS=on,ONChangePercent=(on/statistics.mean(offs)-1)*100,OFFSpreadPercent=(max(offs)/min(offs)-1)*100,eligibleDeliveryBins=len(groups),eligibleQueueBinRows=len(counterRecords),selectedDeliveryBins=len(slots),selectedQueueBinRows=len(selected),eligibleUnselectedQueueBinRows=len(unselected),eligibleUnselected=unselected,totals=totals,ratios=ratios,selected=selected,excluded=excluded,limitations=['Counts are delivery-time bins and CPU descriptor reads, not GPU accesses, simulation frames, CPU times or unique resources.','Runtime OFF/ON/OFF controls collector overhead only; diagnostic compilation differs from release-OFF.','Root/direct/allocator/pass/sync and detailed miss reasons remain unmeasured.'])
(O/'diagnostic-summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps({k:v for k,v in summary.items() if k not in ['selected','excluded']},indent=2))
