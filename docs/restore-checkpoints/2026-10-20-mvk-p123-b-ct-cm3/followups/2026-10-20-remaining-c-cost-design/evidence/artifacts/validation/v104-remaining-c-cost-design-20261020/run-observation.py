from pathlib import Path
import importlib.util,json,hashlib,subprocess,threading,os,time,sys,shutil
root=Path('/Users/yeojun/Desktop/BAR-AppleSilicon-App');base=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('screen',base/'screen-guard-locked-allowed.py');screen=importlib.util.module_from_spec(spec);spec.loader.exec_module(screen)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(name,data):
 p=base/name
 with p.open('x') as f:json.dump(data,f,indent=2)
prep=json.loads((base/'preparation.json').read_text());assert len(prep['plans'])==2
assert not (base/'outcome.json').exists() and not (base/'screen-guard.json').exists()
assert screen.power()=={'lowPower':True,'thermal':0}
assert "'AC Power'" in subprocess.check_output(['/usr/bin/pmset','-g','batt'],text=True)
for item in prep['plans']:
 for name in ['plan','host']:assert sha(item[name]['path'])==item[name]['sha256']
stop=threading.Event();failures=[];results=[];child=None
observations=base/'screen-observations.jsonl'
def check():
 row=screen.check();assert row['power']['lowPower'] is True;row['atUnix']=time.time()
 with observations.open('a') as f:f.write(json.dumps(row)+'\n')
def monitor():
 while not stop.wait(2):
  try:check()
  except BaseException as e:
   failures.append(str(e));(base/'screen-stop.json').write_text(json.dumps({'error':str(e),'ownerPID':os.getpid()}));stop.set()
error=None
try:
 with screen.guard(base/'screen-guard.json') as guard:
  check();thread=threading.Thread(target=monitor,daemon=True);thread.start()
  try:
   for item in prep['plans']:
    if failures:raise RuntimeError(failures)
    check();planfile=Path(item['plan']['path']);plan=json.loads(planfile.read_text());folder=Path(item['folder']);grant=folder/'grant.json'
    with grant.open('x') as f:json.dump({'schema':item['schema']+'-grant','authorized':True,'authorizationSource':plan['authorization'],'planSha256':item['plan']['sha256'],'strictHiddenOnly':True,'visibleFallbackAllowed':False,'maximumGameSessions':1,'lane':'lobby','cacheMode':'single','sessionOrdinal':1,'expiresAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()+1800))},f)
    env=os.environ.copy()
    for key in ['MVK_CONFIG_BACKEND_TIMELINE','MVK_CONFIG_BACKEND_TIMELINE_FILE','MVK_METAL4_INVARIANT_DIAGNOSTIC_DIR','MVK_CONFIG_SHADER_DUMP_DIR','BAR_ZINK_MVK_DISABLE_ASYNC_WAIT','ZINK_DEBUG','GALLIUM_THREAD','MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS']:env.pop(key,None)
    print(json.dumps({'event':'starting','ordinal':item['ordinal'],'role':item['role'],'backend':item['backend']}),flush=True)
    with (folder/'host.log').open('x') as log:
     child=subprocess.Popen(['/opt/homebrew/bin/node','--input-type=module','-',str(planfile),str(grant)],stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT,cwd=root,env=env)
     (base/'owned-runner.json').write_text(json.dumps({'runnerPID':os.getpid(),'hostPID':child.pid,'ordinal':item['ordinal']}))
     child.communicate(Path(item['host']['path']).read_bytes());code=child.returncode
    receiptfiles=list((folder/'sessions').glob('*/execution-receipt.json'));r=json.loads(receiptfiles[0].read_text()) if len(receiptfiles)==1 else {};b=r.get('benchmark',{});stats=b.get('benchmark',{}).get('drawIntervals',{})
    result={'ordinal':item['ordinal'],'role':item['role'],'backend':item['backend'],'exit':code,'status':r.get('status'),'error':r.get('error'),'cacheError':r.get('cacheError'),'receipt':str(receiptfiles[0]) if len(receiptfiles)==1 else None,'fps':stats.get('meanFPS'),'p50Ms':stats.get('p50Ms'),'p95Ms':stats.get('p95Ms'),'p99Ms':stats.get('p99Ms'),'remainingOwnedProcesses':r.get('remainingOwnedProcesses'),'protectedInputsUnchanged':r.get('protectedInputsUnchanged'),'resolution':b.get('resolution'),'camera':b.get('camera'),'runtimeUUID':r.get('runtimeUUID'),'nativeMetal4':r.get('nativeMetal4')};results.append(result);write(f'arm-{item["ordinal"]}-result.json',result);print(json.dumps({'event':'finished',**result}),flush=True)
    if code or r.get('status')!='completed-not-promoted' or not r.get('protectedInputsUnchanged') or r.get('remainingOwnedProcesses') or not r.get('powerConditionsPassed'):raise RuntimeError('First failed arm; stop remaining comparison, no automatic retry')
    # Only regenerateable cache is retired after verified owned-process shutdown.
    caches=[];cacheLeaves=[]
    session=Path(result['receipt']).parent
    for relative in ('state/data/cache','state/GPUCache','state/DawnGraphiteCache','state/DawnWebGPUCache','state/Cache','state/Code Cache'):
     cache=session/relative
     if not cache.is_dir():continue
     assert cache.resolve()==cache and not cache.is_symlink() and cache.is_relative_to(folder)
     for entry in cache.rglob('*'):
      if entry.is_file() or entry.is_symlink():
       assert entry.suffix.lower()!='.md'
       info=entry.lstat();cacheLeaves.append({'path':str(entry),'bytes':info.st_size,'dev':info.st_dev,'ino':info.st_ino})
     caches.append(cache)
    deletion={'ordinal':item['ordinal'],'roots':[str(x) for x in caches],'leaves':cacheLeaves,'logicalBytes':sum(x['bytes'] for x in cacheLeaves),'remainingOwnedProcesses':[],'logsResultsAndMarkdownPreserved':True,'physicalBytesNotMeasured':True}
    write(f'arm-{item["ordinal"]}-cache-cleanup-selection.json',deletion)
    for leaf in cacheLeaves:
     info=Path(leaf['path']).lstat();assert (info.st_dev,info.st_ino,info.st_size)==(leaf['dev'],leaf['ino'],leaf['bytes'])
    for cache in caches:shutil.rmtree(cache)
    write(f'arm-{item["ordinal"]}-cache-cleanup-completion.json',{'rootsRemoved':len(caches),'leavesRemoved':len(cacheLeaves),'logicalBytesRemoved':deletion['logicalBytes'],'allAbsent':all(not x.exists() for x in caches),'logsResultsAndMarkdownPreserved':True})
    if item['ordinal']<2:time.sleep(5)
  finally:stop.set();thread.join(timeout=10);assert not thread.is_alive()
except BaseException as e:
 error=repr(e);print(error,flush=True)
finally:
 write('outcome.json',{'status':'completed' if len(results)==2 and not error and not failures else 'stopped','error':error,'screenFailures':failures,'results':results,'maximumGameSessions':2,'automaticRetry':False,'appPromoted':False,'powerSettingsModified':False})
if error or failures:sys.exit(1)
