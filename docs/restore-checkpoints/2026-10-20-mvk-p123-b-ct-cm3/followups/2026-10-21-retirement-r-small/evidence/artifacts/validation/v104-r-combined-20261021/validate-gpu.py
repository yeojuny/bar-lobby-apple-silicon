from pathlib import Path
import json,hashlib,subprocess,os,re,shlex,time
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;V=O/'gpu';V.mkdir(exist_ok=True);B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';lib=R/'build/metal4-mvk-20261002/MoltenVK/libMoltenVK.1.4.3.dylib'
def run(label,args,env=None):
 originalLabel=label;attempt=1
 while (V/(label+'.json')).exists():attempt+=1;label=originalLabel+'-attempt'+str(attempt)
 t=time.monotonic();p=subprocess.run(args,capture_output=True,text=True,env=env,timeout=90)
 (V/(label+'.stdout')).write_text(p.stdout);(V/(label+'.stderr')).write_text(p.stderr);(V/(label+'.json')).write_text(json.dumps(dict(arguments=args,exitCode=p.returncode,seconds=time.monotonic()-t,rawSHA256=hashlib.sha256(lib.read_bytes()).hexdigest()),indent=2)+'\n')
 print(label,p.returncode,p.stdout[-1900:],flush=True);assert p.returncode==0,(label,p.stderr[-2000:]);return p
n=(R/'build/metal4-mvk-20261002/build.ninja').read_text();block=n[n.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCmdDraw.mm.o:'):];extra=shlex.split(re.search(r'  INCLUDES = (.*)',block).group(1))+shlex.split(re.search(r'  DEFINES = (.*)',block).group(1))
base=['/usr/bin/xcrun','clang++','-std=c++17','-fno-objc-arc','-fblocks','-mmacosx-version-min=27.0','-Wno-deprecated-declarations','-O1','-g','-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0','-framework','Foundation','-framework','Metal']
original=(R/'tools/tests/metal4-vulkan-integration.mm').read_text();prefix=original[:original.index('\nint main(')]
a=prefix.index('void compute(Context&');e=prefix.index('\nvoid sequentialPrimaryBindings(',a);compute=prefix[a:e]
variant=compute.replace('void compute(', 'void computeCompatible(',1).replace('allocate.pSetLayouts = &setLayout;', 'allocate.pSetLayouts = &compatibleSetLayout;')
marker='    VkDescriptorSetAllocateInfo allocate'
insert='    VkDescriptorSetLayout compatibleSetLayout; VK_CHECK(vkCreateDescriptorSetLayout(c.device, &setInfo, nullptr, &compatibleSetLayout));\n    c.cleanup.push_back([&, compatibleSetLayout] { vkDestroyDescriptorSetLayout(c.device, compatibleSetLayout, nullptr); });\n'
assert variant.count(marker)==1;variant=variant.replace(marker,insert+marker)
repeat='''void barrierRepeated(VkCommandBuffer command, VkPipelineStageFlags source, VkAccessFlags sourceAccess, VkPipelineStageFlags target, VkAccessFlags targetAccess) {
 barrier(command,source,sourceAccess,target,targetAccess);barrier(command,source,sourceAccess,target,targetAccess);
}
'''+compute.replace('void compute(', 'void computeRepeated(',1).replace('barrier(command,','barrierRepeated(command,')
main=r'''
int main(int argc,char** argv){bool native=argc<2||std::strcmp(argv[1],"m3");setenv("MVK_CONFIG_USE_METAL4",native?"1":"0",1);unsigned failed=0,passed=0;
@autoreleasepool{auto test=[&](const char* name,const std::function<void(Context&)>& body){try{Context c;c.initialize(false,native);body(c);++passed;printf("PASS %s\n",name);fflush(stdout);}catch(const std::exception& e){++failed;fprintf(stderr,"FAIL %s: %s\n",name,e.what());}};
test("compute_dynamic_push",[](Context& c){compute(c);});
test("compute_RAW",[](Context& c){compute(c,false,1);});
test("compute_WAR",[](Context& c){compute(c,false,2);});
test("descriptor_revision_recording",[](Context& c){compute(c,false,3);});
test("compatible_layout_fallback",[](Context& c){computeCompatible(c,false,3);});
test("repeated_barrier_and_current_producer_RAW",[](Context& c){computeRepeated(c,false,1);});
test("repeated_barrier_and_current_producer_WAR",[](Context& c){computeRepeated(c,false,2);});
test("indexed_render",[](Context& c){render(c);});
test("helper_restore",[](Context& c){compute(c,true);});
test("fragment_texture_sampler",[](Context& c){render(c,true);});
test("partial_clear_restore",[](Context& c){render(c,false,true);});
test("msaa_renderpass_resolve",[](Context& c){render(c,false,true,1);});
test("msaa_explicit_resolve",[](Context& c){render(c,false,false,2);});
test("occlusion_accumulation_reuse",[](Context& c){render(c,false,true,0,0,true);});
test("single_use_msaa_handoff",[](Context& c){c.oneTime=true;render(c,false,true,1);});
}printf("{\"native\":%s,\"passed\":%u,\"failed\":%u}\n",native?"true":"false",passed,failed);return failed?1:0;}
'''
source=V/'selected-vulkan.mm';source.write_text(prefix+'\n'+variant+'\n'+repeat+'\n'+main)
exe=V/'selected-vulkan';run('vulkan-build',base+extra+['-I'+str(R/'build/run66-moltenvk-src-20260903/External/SPIRV-Headers/include'),'-I'+str(R/'tools/tests'),str(source),str(lib),'-Wl,-rpath,'+str(lib.parent),'-o',str(exe)])
env=dict(os.environ,MTL_DEBUG_LAYER='1',MVK_CONFIG_METAL4_STATS='0',MVK_CONFIG_METAL4_QUEUE_STATS='0',MVK_CONFIG_BACKEND_COST_STATS='0',MVK_CONFIG_BACKEND_TIMELINE='0',MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS='1',MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS='0',MVK_CONFIG_LOG_LEVEL='3')
for backend in ['m4','m3']:run('vulkan-'+backend,[str(exe),backend],env)
(O/'gpu-complete.json').write_text(json.dumps(dict(status='passed',casesPerBackend=15,backends=['Metal4','Metal3'],rawSHA256=hashlib.sha256(lib.read_bytes()).hexdigest(),gameExecuted=False),indent=2)+'\n')
