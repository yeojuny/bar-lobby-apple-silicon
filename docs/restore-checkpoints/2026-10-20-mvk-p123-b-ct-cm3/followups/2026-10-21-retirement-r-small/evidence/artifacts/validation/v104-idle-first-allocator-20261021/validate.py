from pathlib import Path
import sys,json,subprocess,os,time
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;count=int(sys.argv[1]);assert count==32
B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';assert f'maxAllocatorEpochRecordings = {count};' in (B/'GPUObjects/MVKMetal4Submission.h').read_text()
V=O/f'allocator-{count}';V.mkdir(exist_ok=True)
def run(label,args,env=None):
 original=label;attempt=1
 while (V/(label+'.json')).exists():attempt+=1;label=original+'-attempt'+str(attempt)
 t=time.monotonic();p=subprocess.run(args,capture_output=True,text=True,env=env,timeout=120)
 (V/(label+'.log')).write_text(p.stdout+p.stderr);(V/(label+'.json')).write_text(json.dumps(dict(arguments=args,exitCode=p.returncode,seconds=time.monotonic()-t),indent=2)+'\n');print(label,p.returncode,p.stdout[-1300:],flush=True);assert p.returncode==0,(label,p.stderr[-2500:])
base=['/usr/bin/xcrun','clang++','-std=c++17','-O1','-g','-fno-objc-arc','-fblocks','-mmacosx-version-min=27.0','-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0','-Wno-deprecated-declarations','-framework','Foundation','-framework','Metal','-I'+str(B/'GPUObjects'),'-I'+str(B/'Commands')]
extra=[str(B/'Commands/MVKMetal4ArgumentTable.mm'),str(B/'GPUObjects/MVKBackendTimeline.cpp')]
exe=V/'allocator-cpu';run('cpu-build',base+['-fsanitize=address,undefined','-fno-omit-frame-pointer',str(R/'tools/tests/metal4-counter-completion-cpu.mm')]+extra+['-o',str(exe)])
env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1',MVK_CONFIG_METAL4_STATS='0',MVK_CONFIG_METAL4_QUEUE_STATS='0',MVK_CONFIG_BACKEND_TIMELINE='0',MVK_CONFIG_BACKEND_COST_STATS='0')
run('cpu-run',[str(exe),'idle-first-policy'],env)
source=(R/'tools/tests/metal4-r49-lifetime-native.mm').read_text();prefix=source[:source.index('\nint main(')]
main=r'''
int main(){@autoreleasepool{unsigned passed=0;Owned<id<MTLDevice>> device(MTLCreateSystemDefaultDevice());try{
 require(device.get()&&[device.get() supportsFamily:MTLGPUFamilyMetal4],"native device");
 allocatorEpochGPUReplay(device.get(), true);++passed;
 allocatorIdleFirstGPUReplay(device.get());++passed;
 resourcePackBlockedAndCancel(device.get());++passed;
 resourcePackPoisoned(device.get());++passed;
 multipleSubmissions(device.get());++passed;
 blockedEventLifetime(device.get());++passed;
 printf("{\"passed\":%u,\"countLimit\":%u,\"completedBatches\":%llu,\"resets\":%llu}\n",passed,MVKMetal4ResourcePoolStats::maxAllocatorEpochRecordings,(unsigned long long)allocatorEpochCompleted,(unsigned long long)allocatorEpochEvidence.allocatorResets);return 0;
}catch(const std::exception& e){fprintf(stderr,"FAIL after %u cases: %s\n",passed,e.what());return 1;}}}
'''
src=V/'allocator-native.mm';src.write_text(prefix+'\n'+main);exe=V/'allocator-native'
run('native-build',base+[str(src),str(B/'GPUObjects/MVKMetal4Submission.mm')]+extra+['-o',str(exe)])
env['MTL_DEBUG_LAYER']='1';run('native-run',[str(exe)],env)
(V/'completion.json').write_text(json.dumps(dict(status='passed',countLimit=count,cpu='actual production implementation with NSObject receivers; ASan+UBSan',nativeCases=6,quiescentReset=True,gameExecuted=False),indent=2)+'\n')
