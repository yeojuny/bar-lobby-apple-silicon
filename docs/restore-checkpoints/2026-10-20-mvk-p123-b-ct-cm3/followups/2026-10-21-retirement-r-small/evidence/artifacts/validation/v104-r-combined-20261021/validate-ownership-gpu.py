from pathlib import Path
import json,subprocess,os,time
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;V=O/'gpu-validation';V.mkdir(exist_ok=False);B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';lib=R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'
def run(label,args,env=None):
 t=time.monotonic();p=subprocess.run(args,capture_output=True,text=True,env=env,timeout=60);(V/(label+'.stdout')).write_text(p.stdout);(V/(label+'.stderr')).write_text(p.stderr);(V/(label+'.json')).write_text(json.dumps(dict(arguments=args,exitCode=p.returncode,seconds=time.monotonic()-t),indent=2));print(label,p.returncode,p.stdout[:800],flush=True);assert p.returncode==0,(label,p.stderr[-1200:]);return p
base=['/usr/bin/xcrun','clang++','-std=c++17','-fno-objc-arc','-fblocks','-mmacosx-version-min=27.0','-Wno-deprecated-declarations','-O1','-g','-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0','-framework','Foundation','-framework','Metal','-I'+str(B/'GPUObjects'),'-I'+str(B/'Commands')]
exe=V/'native-registration';run('native-build',base+['-fsanitize=address,undefined','-fno-omit-frame-pointer',str(R/'tools/tests/metal4-r49-lifetime-native.mm'),str(B/'GPUObjects/MVKMetal4Submission.mm'),str(B/'Commands/MVKMetal4ArgumentTable.mm'),str(B/'GPUObjects/MVKBackendTimeline.cpp'),'-o',str(exe)])
env=dict(os.environ,MTL_DEBUG_LAYER='1',MVK_CONFIG_METAL4_STATS='0',MVK_CONFIG_METAL4_QUEUE_STATS='0',MVK_CONFIG_BACKEND_COST_STATS='0',MVK_CONFIG_BACKEND_TIMELINE='0',ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1');run('native-registration',[str(exe),'--resource-registration'],env)
original=(R/'tools/tests/metal4-prepared-recording-vulkan.mm').read_text();source=V/'prepared-selected.mm';source.write_text(original[:original.index('\nint main(')]+r'''
int main(int argc, char** argv) {
 const bool native = argc == 1 || !std::strcmp(argv[1], "m4");
 setenv("MVK_CONFIG_USE_METAL4", native ? "1" : "0", 1);
 @autoreleasepool {
 try {
  if(argc>1) { Context c; c.oneTime=true;c.initialize(true,native); compactUniformSnapshot(c); }
  else { for(int i=0;i<3;i++){ Context c;c.oneTime=true;c.initialize(i==2);
   if(i==0)canceledPrepared(c);else if(i==1)reverseRecordedThreePools(c);else hostLatestAndUpdateSnapshot(c); } }
  std::printf("{\"passed\":true,\"cases\":%d,\"native\":%s}\n",argc>1?1:3,native?"true":"false");return 0;
 }catch(const std::exception& e){std::fprintf(stderr,"%s\n",e.what());return 1;}
 }
}
''')
exe=V/'prepared-selected';args=base+['-I'+str(R/'tools/tests'),'-I'+str(R/'build/run66-vulkan-headers-src-20260903/include'),'-I'+str(R/'build/run66-moltenvk-src-20260903/External/SPIRV-Headers/include'),str(source),str(lib),'-Wl,-rpath,'+str(lib.parent),'-o',str(exe)];run('prepared-build',args)
env.update(MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS='1',MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS='0',MVK_CONFIG_LOG_LEVEL='3',MVK_CONFIG_BACKEND_COST_STATS='0')
for label,args in [('prepared-m4',[str(exe)]),('template-m4',[str(exe),'m4']),('template-m3',[str(exe),'m3'])]:run(label,args,env)
print('Selected native ownership and Vulkan cancellation/reuse/output passed.',flush=True)

(O/'ownership-gpu-complete.json').write_text(json.dumps(dict(status='passed',nativeRegistrationCases=6,preparedRecordingCases=3,compactTemplateBackends=['Metal3','Metal4'],diagnosticsCompile=0),indent=2)+'\n')
