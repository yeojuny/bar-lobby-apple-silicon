from pathlib import Path
import json, hashlib, subprocess, os, re, shlex
R=Path(__file__).resolve().parents[3];O=Path(__file__).resolve().parent;B=R/'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK';V=O/'cpu';V.mkdir(exist_ok=True)
def extract(text,sig):
 s=text.index(sig);p=text.index('{',s);depth=1;e=p+1
 while depth:
  depth+=(text[e]=='{')-(text[e]=='}');e+=1
 return text[s:e]
def run(label,args,env=None):
 originalLabel=label; attempt=1
 while (V/(label+'.log')).exists():attempt+=1;label=originalLabel+'-attempt'+str(attempt)
 p=subprocess.run(args,capture_output=True,text=True,env=env,timeout=120)
 (V/(label+'.log')).write_text(p.stdout+p.stderr);(V/(label+'.json')).write_text(json.dumps(dict(arguments=args,exitCode=p.returncode),indent=2)+'\n')
 print(label,p.returncode,p.stdout[:700],flush=True);assert p.returncode==0,(label,p.stderr[-2000:]);return p
n=(R/'build/metal4-mvk-20261002/build.ninja').read_text();block=n[n.index('build MoltenVK/CMakeFiles/MoltenVK.dir/MoltenVK/Commands/MVKCmdDraw.mm.o:'):]
incs=shlex.split(re.search(r'  INCLUDES = (.*)',block).group(1));defs=shlex.split(re.search(r'  DEFINES = (.*)',block).group(1))
base=['/usr/bin/xcrun','clang++','-std=c++17','-mmacosx-version-min=27.0','-O1','-g','-fno-objc-arc','-fblocks','-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0','-Wno-deprecated-declarations','-framework','Foundation','-framework','Metal']
env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
san=['-fsanitize=address,undefined','-fno-omit-frame-pointer']

# Exact production plan with actual descriptor types, including inline-before-variable.
plan=V/'binding-plan.mm';plan.write_text(r'''
#include "MVKDescriptorSet.h"
BINDING_PLAN_PRODUCTION_SOURCE
#include <cassert>
#include <cstdio>
int main(){unsigned checks=0;
 const auto* layout=reinterpret_cast<const MVKDescriptorSetLayout*>(uintptr_t(16));
 for(auto type:{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK})
 for(auto cpu:{MVKDescriptorCPULayout::None,MVKDescriptorCPULayout::OneID,MVKDescriptorCPULayout::OneIDMeta,MVKDescriptorCPULayout::InlineData})
 for(bool variable:{false,true})for(bool immutable:{false,true})for(unsigned fixed:{0u,1u,5u})for(unsigned actual:{0u,2u,5u}){
  MVKDescriptorBinding b{};b.descriptorType=type;b.descriptorCount=fixed;b.cpuLayout=cpu;b.cpuOffset=24;
  b.flags=(variable?MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT:0)|(immutable?MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT:0);
  b.immSamplerIndex=7;b.perDescriptorResourceCount={3,1,1};
  MVKMetal4ResourceBindingPlan p(layout,b);
  assert(p.layout==layout && p.getDescriptorCount(actual)==b.getDescriptorCount(actual));
  assert(p.cpuStride==descriptorCPUSize(cpu)&&p.cpuOffset==b.cpuOffset&&p.cpuLayout==cpu);
  assert(p.hasImmutableSamplers()==b.hasImmutableSamplers()&&p.immSamplerIndex==(immutable?7:0));
  assert(p.perDescriptorResourceCount.texture==3&&p.perDescriptorResourceCount.buffer==1&&p.perDescriptorResourceCount.sampler==1);++checks;
 }
 printf("PASS %u plan cases; plan=%zu bytes binding=%zu bytes; live variable count preserved\n",checks,sizeof(MVKMetal4ResourceBindingPlan),sizeof(MVKMetal4ResourceBinding));
}
''')
header=(B/'GPUObjects/MVKPipeline.h').read_text();start=header.index('struct MVKMetal4ResourceBindingPlan {');end=header.index('\n#endif',start)
plan.write_text(plan.read_text().replace('BINDING_PLAN_PRODUCTION_SOURCE',header[start:end]))
run('binding-plan-build',base+incs+defs+san+[str(plan),'-o',str(V/'binding-plan')]);run('binding-plan',[str(V/'binding-plan')],env)

# Reuse the existing production-extraction fixture with typed native overload.
f=R/'tools/tests/metal4-suspend-resolve-cpu.mm'
text=(B/'GPUObjects/MVKRenderPass.mm').read_text();a=text.index('template<class Descriptor>\nvoid MVKRenderSubpass::populateMTLRenderPassDescriptorImpl(');e=text.index('\nvoid MVKRenderSubpass::encodeStoreActions(',a)
body=text[a:e]+'\n'+extract(text,'void MVKRenderSubpass::resolveUnresolvableAttachments(')+'\n'
old=(O/'preimage/GPUObjects/MVKRenderPass.mm').read_text();body+=extract(old,'void MVKRenderSubpass::populateMTLRenderPassDescriptor(').replace('::populateMTLRenderPassDescriptor','::populateLegacyReference',1)+'\n'
inc=V/'suspend-body.inc';inc.write_text(body)
args=base+san+['-DMVK_BUILD_METAL4_FOUNDATION=1','-DMVK_USE_METAL_PRIVATE_API=0','-I'+str(R/'build/run66-vulkan-headers-src-20260903/include'),f'-DMVK_SUSPEND_RESOLVE_BODY="{inc}"',str(f),'-o',str(V/'suspend-parity')]
run('suspend-parity-build',args);run('suspend-parity',[str(V/'suspend-parity')],env)

run('descriptor-existing',['python3',str(R/'tools/tests/metal4-descriptor-preparation-cpu.py'),str(V/'descriptor-existing')],env)
for name in ['metal4-r42-dependency-cpu','metal4-prepared-dependency-cpu']:
 run(name+'-build',['/usr/bin/xcrun','clang++','-std=c++17','-O1','-g']+san+[str(R/'tools/tests'/(name+'.cpp')),'-o',str(V/name)])
 run(name,[str(V/name)],env)
# Foundation OFF and private API OFF compile coverage for the changed typed code.
for foundation,private in [(0,1),(1,0)]:
 d=[x for x in defs if not x.startswith(('-DMVK_BUILD_METAL4_FOUNDATION=','-DMVK_USE_METAL_PRIVATE_API='))]+[f'-DMVK_BUILD_METAL4_FOUNDATION={foundation}',f'-DMVK_USE_METAL_PRIVATE_API={private}']
 for f in ['GPUObjects/MVKPipeline.mm','GPUObjects/MVKRenderPass.mm','Commands/MVKCommandBuffer.mm','Commands/MVKCommandEncoderState.mm']:
  run(f'syntax-{foundation}-{private}-'+Path(f).stem,base[:]+incs+d+['-fsyntax-only',str(B/f)])
(O/'cpu-complete.json').write_text(json.dumps(dict(status='passed',gpuExecuted=False),indent=2)+'\n')
