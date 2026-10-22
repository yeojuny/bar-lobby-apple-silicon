from pathlib import Path
import json,subprocess,os,hashlib,sys,time,shlex,re,shutil
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';role=sys.argv[1];assert role in ['R','Combined'];V=O/role;V.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(B/'GPUObjects/MVKMetal4PreparedResource.h')==sha(O/(role+'-next.h'))
def run(label,args,env=None,timeout=180):
 assert not (V/(label+'.json')).exists(),label
 t=time.monotonic();p=subprocess.run(args,capture_output=True,text=True,env=env,timeout=timeout)
 (V/(label+'.log')).write_text(p.stdout+p.stderr);(V/(label+'.json')).write_text(json.dumps(dict(arguments=args,exitCode=p.returncode,seconds=time.monotonic()-t),indent=2)+'\n');print(role,label,p.returncode,p.stdout[-1200:],flush=True);assert p.returncode==0,(label,p.stderr[-2200:]);return p
old=(O/'group-cache-before.inc').read_text();new=(O/'group-cache-after.inc').read_text()
ref=O/'reference-group-cache.inc';ref.write_text(old.replace('MVKMetal4PreparedGroupCache','ReferenceGroupCache'))
counted=O/'counted-group-caches.inc';counted.write_text('struct CountingHash { inline static uint64_t calls=0; size_t operator()(uint64_t v)const {++calls;return std::hash<uint64_t>{}(v);} };\n'+old.replace('MVKMetal4PreparedGroupCache','CountedReferenceGroupCache').replace('std::unordered_map<uint64_t, Entry>','std::unordered_map<uint64_t, Entry, CountingHash>')+new.replace('MVKMetal4PreparedGroupCache','CountedCurrentGroupCache').replace('std::unordered_map<uint64_t, Entry>','std::unordered_map<uint64_t, Entry, CountingHash>'))
env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1',MVK_CONFIG_BACKEND_TIMELINE='0',MVK_CONFIG_BACKEND_COST_STATS='0',MVK_CONFIG_METAL4_STATS='0',MVK_CONFIG_METAL4_QUEUE_STATS='0',MTL_DEBUG_LAYER='1')
exe=V/'group-locator-cpu';run('cpu-build',['/usr/bin/xcrun','clang++','-std=c++17','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',f'-DMVK_GROUP_LOOKUP_HEADER="{B}/GPUObjects/MVKMetal4PreparedResource.h"',f'-DMVK_GROUP_REFERENCE_BODY="{ref}"',f'-DMVK_GROUP_COUNTED_BODIES="{counted}"',str(R/'tools/tests/metal4-group-locator-cpu.cpp'),'-o',str(exe)]);run('cpu-run',[str(exe)],env)
run('mvk-build',['/opt/homebrew/bin/ninja','-C',str(R/'build/metal4-mvk-20261002'),'-j6','MoltenVK'],timeout=240)
lib=R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib';raw=O/(role+'-next-raw-MoltenVK.dylib');shutil.copy2(lib,raw)
base=['/usr/bin/xcrun','clang++','-std=c++17','-fno-objc-arc','-fblocks','-mmacosx-version-min=27.0','-Wno-deprecated-declarations','-O1','-g','-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0','-framework','Foundation','-framework','Metal','-I'+str(B/'GPUObjects'),'-I'+str(B/'Commands')]
source=(R/'tools/tests/metal4-r49-lifetime-native.mm').read_text();src=V/'sequential-native.mm';src.write_text(source[:source.index('\nint main(')]+'''\nint main(){@autoreleasepool{try{Owned<id<MTLDevice>> device(MTLCreateSystemDefaultDevice());require(device.get()!=nil,"native device");sequentialPrimaryTableSnapshots(device.get());puts("PASS sequential primary GPU output, recording-end proof clear and new-recording miss");return 0;}catch(const std::exception& e){fprintf(stderr,"FAIL %s\\n",e.what());return 1;}}}\n''')
exe=V/'sequential-native';run('native-build',base+[str(src),str(B/'GPUObjects/MVKMetal4Submission.mm'),str(B/'Commands/MVKMetal4ArgumentTable.mm'),str(B/'GPUObjects/MVKBackendTimeline.cpp'),'-o',str(exe)]);run('native-run',[str(exe)],env)
n=(R/'build/metal4-mvk-20261002/build.ninja').read_text();block=n[n.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCmdDraw.mm.o:'):];extra=shlex.split(re.search(r'  INCLUDES = (.*)',block).group(1))+shlex.split(re.search(r'  DEFINES = (.*)',block).group(1))
original=(R/'tools/tests/metal4-vulkan-integration.mm').read_text();prefix=original[:original.index('\nint main(')];a=prefix.index('void compute(Context&');e=prefix.index('\nvoid sequentialPrimaryBindings(',a);compute=prefix[a:e];variant=compute.replace('void compute(', 'void computeCompatible(',1).replace('allocate.pSetLayouts = &setLayout;', 'allocate.pSetLayouts = &compatibleSetLayout;');marker='    VkDescriptorSetAllocateInfo allocate';insert='    VkDescriptorSetLayout compatibleSetLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &compatibleSetLayout));\n    c.cleanup.push_back([&, compatibleSetLayout] { vkDestroyDescriptorSetLayout(c.device, compatibleSetLayout, nullptr); });\n';assert variant.count(marker)==1;variant=variant.replace(marker,insert+marker)
source=V/'selected-vulkan.mm';source.write_text(prefix+'\n'+variant+r'''
int main(int argc,char**argv){bool native=argc<2||std::strcmp(argv[1],"m3");setenv("MVK_CONFIG_USE_METAL4",native?"1":"0",1);@autoreleasepool{try{
 {Context c;c.initialize(false,native);compute(c,false,3);}
 {Context c;c.initialize(false,native);computeCompatible(c,false,3);}
 {Context c;c.initialize(false,native);render(c,true);}
 printf("PASS descriptor revision/new recording, compatible layout, fragment texture/sampler; native=%d\n",native);return 0;
 }catch(const std::exception&e){fprintf(stderr,"FAIL %s\n",e.what());return 1;}}}
''')
exe=V/'selected-vulkan';run('vulkan-build',base+extra+['-I'+str(R/'build/run66-moltenvk-src-20260903/External/SPIRV-Headers/include'),'-I'+str(R/'tools/tests'),str(source),str(lib),'-Wl,-rpath,'+str(lib.parent),'-o',str(exe)])
env.update(MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS='1',MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS='0',MVK_CONFIG_LOG_LEVEL='3')
for backend in ['m4','m3']:run('vulkan-'+backend,[str(exe),backend],env)
# Header is shared with foundation-OFF translation units: narrow syntax gate.
defs=[x for x in extra if not x.startswith('-DMVK_BUILD_METAL4_FOUNDATION=')]+['-DMVK_BUILD_METAL4_FOUNDATION=0']
run('foundation-off',base+defs+['-fsyntax-only',str(B/'GPUObjects/MVKMetal4Submission.mm')])
pins={p:sha(R/p) for p in json.loads((O/'before.json').read_text())['sourcePins']}
(V/'source-pins.json').write_text(json.dumps(pins,indent=2)+'\n')
(V/'completion.json').write_text(json.dumps(dict(status='passed',role=role,rawSHA256=sha(raw),headerSHA256=sha(B/'GPUObjects/MVKMetal4PreparedResource.h'),cpuASanUBSan=True,nativeCases=1,vulkanCasesPerBackend=3,backends=['Metal4','Metal3'],diagnosticsCompile=0,countLimit=32,FPSMeasured=False),indent=2)+'\n')
