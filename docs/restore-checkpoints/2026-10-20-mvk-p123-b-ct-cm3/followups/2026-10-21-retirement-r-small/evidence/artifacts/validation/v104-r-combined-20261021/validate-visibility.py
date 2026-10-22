from pathlib import Path
import json,hashlib,re,subprocess
root=Path(__file__).resolve().parents[3];out=Path(__file__).resolve().parent/"visibility";out.mkdir(exist_ok=True);core=root/"build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK"
(out/"cpu").mkdir(exist_ok=True)
def extract(text,sig):
 start=text.index(sig);pos=text.index('{',start);depth=1;end=pos+1
 while depth:
  if text[end]=='{':depth+=1
  elif text[end]=='}':depth-=1
  end+=1
 return text[start:end]
def save(name,data):
 p=out/name;p.write_text(data+'\n');return p
h=(core/'GPUObjects/MVKDevice.h').read_text();d=(core/'GPUObjects/MVKDevice.mm').read_text();c=(core/'Commands/MVKCommandBuffer.mm').read_text();s=(core/'Commands/MVKCommandPipelineStateFactoryShaderSource.h').read_text()
cls=save('visibility-class.inc',extract(h,'class MVKVisibilityBuffer {')+';')
buf=save('visibility-buffer.inc','\n\n'.join(extract(d,sig) for sig in ['MVKVisibilityBuffer::MVKVisibilityBuffer(','MVKVisibilityBuffer::~MVKVisibilityBuffer(','uint32_t MVKVisibilityBuffer::advanceOffset(']))
prep=save('visibility-prepare.inc',extract(c,'template<class Descriptor>\nbool MVKCommandEncoder::prepareVisibilityResultBuffer('))
start=s.index('typedef struct alignas(8) {\n\tuint32_t count;');end=s.index('typedef enum {\n\tInitial,',start)
metal=s[start:end]+extract(s,'kernel void accumulateOcclusionQueryResults(')
save('accumulation.metal','#include <metal_stdlib>\nusing namespace metal;\n'+metal)
host=re.sub(r'\[\[[^\]]+\]\]','',metal)
host=re.sub(r'\b(kernel|device|constant)\s+','',host)
kernel=save('visibility-kernel.inc',host)
base=['/usr/bin/xcrun','clang++','-std=c++17','-mmacosx-version-min=27.0','-g','-O1','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-I'+str(root/'build/run66-vulkan-headers-src-20260903/include'),'-I'+str(core/'Commands'),'-framework','Foundation','-framework','Metal']
fixture=root/'tools/tests/metal4-visibility-recycle-cpu.mm'
rows=[]
def add(label,foundation,xcode,mode,clsfile=cls,prepfile=prep,kernelfile=kernel,expected=0):
 args=base+[f'-DMVK_BUILD_METAL4_FOUNDATION={foundation}',f'-DMVK_XCODE_26={xcode}',f'-DMVK_VISIBILITY_CLASS="{clsfile}"',f'-DMVK_VISIBILITY_BUFFER_BODY="{buf}"',f'-DMVK_VISIBILITY_PREPARE_BODY="{prepfile}"',f'-DMVK_VISIBILITY_KERNEL_BODY="{kernelfile}"',str(fixture),'-o',str(out/'cpu'/label)]
 if mode=='sanitize':args+=['-fsanitize=address,undefined','-fno-omit-frame-pointer']
 rows.append({'label':label,'compile':args,'execute':[str(out/'cpu'/label)],'expected':expected})
for f,x in [(0,1),(1,1),(0,0)]:
 for mode in ['sanitize']:add(f'visibility-foundation{f}-sdk26-{x}-{mode}',f,x,mode)

for row in rows:
 for stage in ['compile','execute']:
  p=subprocess.run(row[stage],capture_output=True,text=True,timeout=90)
  (out/'cpu'/(row['label']+'-'+stage+'.log')).write_text(p.stdout+p.stderr)
  (out/'cpu'/(row['label']+'-'+stage+'.json')).write_text(json.dumps(dict(arguments=row[stage],exitCode=p.returncode),indent=2)+'\n')
  print(row['label'],stage,p.returncode,p.stdout,flush=True);assert p.returncode==0,p.stderr[-2000:]
(out/'completion.json').write_text(json.dumps(dict(status='passed',gpuExecuted=False,rows=rows),indent=2)+'\n')
