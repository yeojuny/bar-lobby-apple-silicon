#!/usr/bin/env python3
"""CPU tests of staged production bodies. No active source, native build or GPU."""
import argparse
import json
from pathlib import Path
import subprocess
from prepare import OUT, ROOT, sha


def body(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    level = 1
    end = opening + 1
    while level:
        level += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[opening:end]


def files(module):
    data = json.loads((OUT/'modules'/module/'module.json').read_text())
    result = {}
    for row in data['variants']['R-and-Small']['files']:
        values = {}
        for version in ['before','after']:
            value = (OUT/row[version]['path']).read_bytes()
            assert sha(value) == row[version]['sha256']
            values[version] = value.decode()
            values[version+'Path'] = str(OUT/row[version]['path'])
        result[Path(row['target']).name] = values
    return result


PREFIX = r'''
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>
static int checks = 0;
static void check(bool ok) { ++checks; if (!ok) { std::fprintf(stderr,"failed check %d\n",checks); std::abort(); } }
'''


def layout_test(data):
    cpp = data['MVKCmdPipeline.mm']
    create = data['MVKDescriptorSet.mm']['after']
    start = create.index('\tfor (uint32_t i = 0; i < numBindings; i++) {', create.index('MVKDescriptorSetLayout* MVKDescriptorSetLayout::Create('))
    finish = create.index('\n\tqsort(',start)
    loop = create[start:finish]
    before = body(cpp['before'],'MVKCmdBindDescriptorSetsStatic<N>::getMetal4RecordPolicy()')
    after = body(cpp['after'],'MVKCmdBindDescriptorSetsStatic<N>::getMetal4RecordPolicy()')
    getter = body(data['MVKDescriptorSet.h']['after'],'bool metal4EarlyRecordEligible() const')
    return PREFIX + r'''
#include <vulkan/vulkan_core.h>
constexpr uint32_t MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS = 0x0f;
enum class MVKMetal4RecordPolicy { Deferred, State };
// Creation/allocation is mocked; the cache update and policy bodies below are
// extracted verbatim. Full production TUs are checked separately by Clang.
struct Binding {
    VkDescriptorType descriptorType; uint32_t flags=0, descriptorCount=0;
    void populate(const VkDescriptorSetLayoutBinding& v) {
        descriptorType=v.descriptorType; descriptorCount=v.descriptorCount;
        flags=v.pImmutableSamplers ? 0x10 : 0;
    }
};
struct Layout {
    std::vector<Binding> _bindings;
    bool _metal4EarlyRecordEligible=true;
    const std::vector<Binding>& bindings() const { return _bindings; }
    bool metal4EarlyRecordEligible() const ''' + getter + r'''
};
struct Set { Layout* layout; };
struct Command {
    void* _pipelineLayout=nullptr; std::vector<Set*> _descriptorSets;
    MVKMetal4RecordPolicy before() const ''' + before + r'''
    MVKMetal4RecordPolicy after() const ''' + after + r'''
};
static Layout create(std::vector<VkDescriptorSetLayoutBinding> bindings,
                     std::vector<VkDescriptorBindingFlags> flags, bool withFlags=true) {
    Layout result; result._bindings.resize(bindings.size());
    Layout* ret=&result;
    VkDescriptorSetLayoutCreateInfo info{}; info.pBindings=bindings.data(); info.bindingCount=bindings.size();
    auto* pCreateInfo=&info; auto* flagList=withFlags ? flags.data() : nullptr;
    uint32_t numBindings=bindings.size();
''' + loop + r'''
    return result;
}
int main() {
    std::array<VkDescriptorType,17> types{{
        VK_DESCRIPTOR_TYPE_SAMPLER,VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
        VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK,
        VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR,VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_NV,
        VK_DESCRIPTOR_TYPE_MUTABLE_EXT,VK_DESCRIPTOR_TYPE_MAX_ENUM,static_cast<VkDescriptorType>(223344)
    }};
    Command cmd; int marker=0; cmd._pipelineLayout=&marker;
    Layout empty=create({},{}); Set set{&empty}; cmd._descriptorSets={&set};
    check(cmd.before()==cmd.after()); check(cmd.after()==MVKMetal4RecordPolicy::State);
    VkSampler fake=nullptr;
    for(auto type:types) for(uint32_t flags=0;flags<32;++flags)
      for(uint32_t count:{0u,1u,16u}) for(bool flagList:{false,true}) {
        VkDescriptorSetLayoutBinding b{};b.binding=7;b.descriptorType=type;b.descriptorCount=count;
        b.pImmutableSamplers=&fake;
        auto layout=create({b},{flags},flagList); set.layout=&layout;
        check(cmd.before()==cmd.after());
        VkDescriptorSetLayoutBinding good{};good.binding=2;good.descriptorType=VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;good.descriptorCount=1;
        auto mixed=create({good,b},{0,flags},flagList);set.layout=&mixed;
        check(cmd.before()==cmd.after());
        std::reverse(mixed._bindings.begin(),mixed._bindings.end());
        check(cmd.before()==cmd.after()); // Sorting must not change the cached result.
      }
    set.layout=&empty;
    cmd._pipelineLayout=nullptr;check(cmd.before()==cmd.after());
    cmd._pipelineLayout=&marker;cmd._descriptorSets={nullptr};check(cmd.before()==cmd.after());
    set.layout=nullptr;cmd._descriptorSets={&set};check(cmd.before()==cmd.after());
    cmd._descriptorSets={};check(cmd.before()==cmd.after());
    std::printf("{\"status\":\"passed\",\"checks\":%d,\"actualGPU\":false}\n",checks);
}
'''


def chain_test(data):
    after=data['MVKCommandBuffer.mm']['after']
    methods=['releaseCommands','releaseRecordedCommands','releaseMetal4PreparedReplay','restoreMetal4PreparedReplay']
    extracted={name:body(after,'void MVKCommandBuffer::'+name+'(') for name in methods}
    declarations = '''
void Buffer::releaseCommands(MVKCommand* command, bool asyncReturn) %s
void Buffer::releaseRecordedCommands(bool asyncReturn) %s
void Buffer::releaseMetal4PreparedReplay(bool asyncReturn) %s
void Buffer::restoreMetal4PreparedReplay() %s
''' % tuple(extracted[x] for x in methods)
    return PREFIX + r'''
struct Pool;
struct MVKCommand { MVKCommand* _next=nullptr; int id=0,returns=0; Pool* pool=nullptr;
    Pool* getTypePool(Pool*) {return pool;} };
struct Pool { std::vector<int> returned;
    void returnObject(MVKCommand* x) {check(++x->returns==1);returned.push_back(x->id);x->_next=x;}
    void returnObjectAsync(MVKCommand* x) {returnObject(x);} // Immediately reuses the link.
};
struct Buffer {
    Pool pool; MVKCommand* _head=nullptr;MVKCommand* _tail=nullptr;
    MVKCommand* _metal4PreparedReplayHead=nullptr;MVKCommand* _metal4PreparedReplayTail=nullptr;
    MVKCommand* _metal4PreparedTimestamp=nullptr; bool _metal4RetainPreparedReplay=false;
    Pool* getCommandPool() {return &pool;}
    void releaseCommands(MVKCommand*,bool=false);void releaseRecordedCommands(bool=false);
    void releaseMetal4PreparedReplay(bool=false);void restoreMetal4PreparedReplay();
    // Native encoder/context destruction is outside this CPU shell. The actual
    // clear method calls this same replay-release method after disposing them.
    void clearMetal4PreparedRecording(){releaseMetal4PreparedReplay();}
};
''' + declarations + r'''
static std::vector<int> order(MVKCommand* p,size_t cap) {
    std::vector<int> result;
    while(p){check(result.size()<cap);result.push_back(p->id);p=p->_next;}return result;
}
int main(){
  for(size_t count:{size_t(0),size_t(1),size_t(2),size_t(257)})
   for(size_t suffix:{size_t(0),size_t(1),size_t(5)})
    for(bool restore:{false,true}) for(bool async:{false,true}) {
      Buffer b;std::vector<MVKCommand> nodes(count+suffix);std::vector<int> expected;
      for(size_t i=0;i<nodes.size();++i){nodes[i].id=i;nodes[i].pool=&b.pool;expected.push_back(i);}
      b._metal4RetainPreparedReplay=true;
      // One completed staged pass may be traversed repeatedly for multiview
      // before transfer. The transfer occurs only after the last traversal.
      size_t split=count/2;
      for(size_t first=0;first<count;){size_t end=first==0&&split?split:count;
        for(size_t i=first;i+1<end;++i)nodes[i]._next=&nodes[i+1];
        auto before=order(&nodes[first],count+1);
        check(order(&nodes[first],count+1)==before);
        b.releaseCommands(&nodes[first]);first=end;
      }
      check(b.pool.returned.empty());
      check(order(b._metal4PreparedReplayHead,count+1)==std::vector<int>(expected.begin(),expected.begin()+count));
      if(count){check(b._metal4PreparedReplayTail==&nodes[count-1]);check(!b._metal4PreparedReplayTail->_next);}
      if(suffix){b._head=&nodes[count];b._tail=&nodes.back();
        for(size_t i=count;i+1<nodes.size();++i)nodes[i]._next=&nodes[i+1];}
      if(restore){
        b.restoreMetal4PreparedReplay();
        check(order(b._head,nodes.size()+1)==expected);
        check(!b._metal4PreparedReplayHead&&!b._metal4PreparedReplayTail);
        check(b.pool.returned.empty());
        // A later suffix pass can still use its own ordinary chain.
        if(suffix)check(order(&nodes[count],suffix+1)==std::vector<int>(expected.begin()+count,expected.end()));
        b.releaseRecordedCommands(async);
      }else{b.releaseMetal4PreparedReplay(async);b.releaseRecordedCommands(async);}
      check(b.pool.returned==expected);
      b.releaseMetal4PreparedReplay(async);b.releaseRecordedCommands(async);b.restoreMetal4PreparedReplay();
      check(b.pool.returned==expected);
      check(!b._head&&!b._tail&&!b._metal4PreparedReplayHead&&!b._metal4PreparedReplayTail);
      for(auto& n:nodes)check(n.returns==1);
    }
  std::printf("{\"status\":\"passed\",\"checks\":%d,\"actualGPU\":false}\n",checks);
}
'''


def snapshot_test(data):
    path=data['MVKMetal4PreparedResource.h']['afterPath']
    return '#include '+json.dumps(path)+'\n'+(OUT/'snapshot-checks.cpp').read_text()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--module',choices=['02-layout-policy','03-owned-replay-chain','09-snapshot-unlocked-retain'],required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();out=args.output.resolve()
    if out.parent!=OUT or out.exists():raise SystemExit('Output must be a new direct evidence directory')
    data=files(args.module)
    generate={'02-layout-policy':layout_test,'03-owned-replay-chain':chain_test,'09-snapshot-unlocked-retain':snapshot_test}[args.module]
    text=generate(data);out.mkdir()
    source=out/'fixture.cpp';source.write_text(text)
    command=['/usr/bin/clang++','-std=c++17','-O1','-g','-DMVK_BUILD_METAL4_FOUNDATION=1',
             '-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',
             '-I'+str(ROOT/'build/run66-vulkan-headers-src-20260903/include'),str(source),'-o',str(out/'check')]
    compiled=subprocess.run(command,capture_output=True,text=True,timeout=120)
    (out/'compile.log').write_text(compiled.stdout+compiled.stderr)
    receipt={'module':args.module,'compile':command,'compileExit':compiled.returncode,'sourceSHA256':sha(source.read_bytes()),
             'productBuilds':0,'activeSourceWrites':0,'actualGPU':False,'status':'compile-failed'}
    if compiled.returncode==0:
        try:
            run=subprocess.run([str(out/'check')],capture_output=True,text=True,timeout=20)
            (out/'run.log').write_text(run.stdout+run.stderr)
            receipt.update(runExit=run.returncode,status='passed-cpu-contracts-only' if run.returncode==0 else 'run-failed')
            if run.returncode==0:receipt['result']=json.loads(run.stdout)
        except subprocess.TimeoutExpired as error:
            receipt.update(status='run-timeout',timeoutSeconds=20)
            (out/'run.log').write_bytes((error.stdout or b'')+(error.stderr or b''))
    (out/'receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':receipt['status'],'module':args.module,'result':receipt.get('result'),'output':str(out)}))
    return 0 if receipt['status']=='passed-cpu-contracts-only' else 1


if __name__=='__main__':raise SystemExit(main())
