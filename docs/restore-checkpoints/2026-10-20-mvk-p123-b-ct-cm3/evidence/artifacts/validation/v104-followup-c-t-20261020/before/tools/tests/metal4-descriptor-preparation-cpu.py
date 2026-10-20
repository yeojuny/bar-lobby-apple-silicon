#!/usr/bin/env python3
"""CPU regression for exact production C++ metadata/cache; no Metal/GPU device.
The root runs this serially. Extracted helpers have no substitute implementation.
Full Vulkan/GPU mutation and resource lifetime coverage remains a separate gate.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
OUT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'artifacts/validation/metal4-r42-structural-20261004/buffer-regression-cpu'
FILES = ['GPUObjects/MVKDescriptorSet.h', 'GPUObjects/MVKDescriptorSet.mm',
         'Commands/MVKCommandEncoderState.h', 'Commands/MVKCommandEncoderState.mm',
         'GPUObjects/MVKDevice.h', 'GPUObjects/MVKDevice.mm',
         'Commands/MVKCmdPipeline.h', 'Commands/MVKCmdPipeline.mm',
         'GPUObjects/MVKMetal4PreparedResource.h', 'Vulkan/vulkan.mm']
sha = lambda data: hashlib.sha256(data).hexdigest()
pins = {name: sha((BASE / name).read_bytes()) for name in FILES}
header = (BASE / FILES[0]).read_text()
start = header.index('struct MVKMetal4DescriptorPreparationStamp {')
end = header.index('\n#endif', start)
helpers = header[start:end]
flags_start = header.index('enum MVKDescriptorBindingFlagBits {')
flags_end = header.index('\n};', flags_start) + len('\n};')
flags = header[flags_start:flags_end]
source = (BASE / FILES[1]).read_text()
state = (BASE / FILES[3]).read_text()
# The central helpers serve ordinary writes/copies/template updates. Push
# descriptors bypass these but have a zero stamp and remain outside the cache.
assert 'set->metal4Preparation.updated();' in source[source.index('static void writeDescriptorSetBinding('):source.index('template <MVKDescriptorGPULayout Layout>\nstatic void copyArgBuf')]
assert 'dstSet->metal4Preparation.updated();' in source[source.index('static void copyDescriptorSetBinding('):source.index('static void copyDescriptorSetBinding(') + 900]
assert 'writeDescriptorSetBinding(' in source[source.index('void mvkUpdateDescriptorSetWithTemplate('):source.index('void mvkPushDescriptorSet(')]
assert 'memset(set, 0, sizeof(*set));' in source and 'set->metal4Preparation.initialize(cacheEligible, groupEligible);' in source
assert '_metal4PreparedDescriptorBindings.clear();' in state[state.index('bool MVKCommandEncoderState::prepareMetal4ResourceRegistration('):state.index('bool MVKCommandEncoderState::registerMetal4Buffer(')]
assert 'if (!value || !live) { allBuffersLive = false; }' in state
assert 'if (allBuffersLive && generation == liveResources.buffers.generation())' in state
assert '!counts.texture && !counts.sampler && !binding.hasImmutableSamplers()' in state

bounds_start = state.index('\t\t\tif (binding.cpuOffset > set->cpuBufferSize')
bounds_end = state.index('\n\t\t\tfor (uint32_t i = 0; i < count;', bounds_start)
bounds_branch = state[bounds_start:bounds_end]
live_start = state.index('auto live = liveResources.buffers.isLive(value);', bounds_end)
live_end = state.index('\n\t\t\t\t\t} else {', live_start)
live_branch = state[live_start:live_end]
admit_start = state.index('\t\t\tif (allBuffersLive && generation == liveResources.buffers.generation())')
admit_end = state.index('\n\t\t\t}', admit_start) + len('\n\t\t\t}')
admit_branch = state[admit_start:admit_end]
branches = r'''
struct TestLiveBuffers {
    bool live; uint64_t currentGeneration; unsigned checks = 0;
    bool isLive(const void*) { ++checks; return live; }
    uint64_t generation() const { return currentGeneration; }
    MVKMetal4PreparedResourceProof membershipProof(const void*, bool) { return {}; }
};
struct TestLiveResources { TestLiveBuffers buffers; };
struct TestSink {
    int encoder = 0; bool succeeds; unsigned registrations = 0;
    bool bufferResource(const void*) { ++registrations; return succeeds; }
};
struct TestSet {
    MVKMetal4DescriptorPreparationStamp metal4Preparation;
    uint32_t cpuBufferSize; const char* cpuBuffer;
};
static bool metal4Failure(int, const char*) { return false; }
static bool proveBinding(MVKMetal4DescriptorPreparationCache& preparation, TestSet* set,
                         TestLiveResources& liveResources, TestSink& sink,
                         const void* value, uint32_t offset, uint64_t span,
                         uint64_t generation = 9) {
    struct { uint32_t cpuOffset; } binding{offset};
    struct { uint32_t bindingIdx; } used{0};
    bool allBuffersLive = true;
    bool snapshotEligible = false, allBuffersProven = false;
    uint32_t count = 1;
    std::vector<MVKMetal4PreparedResourceProof> bufferProofs;
    using Snapshots = MVKMetal4PreparedBindingSnapshots;
    auto captureSnapshot = [](auto, auto, auto) {};
    constexpr auto nil = nullptr;
''' + bounds_branch + '\n' + live_branch + '\n' + admit_branch + r'''
    return true;
}
'''

device = (BASE / 'GPUObjects/MVKDevice.mm').read_text()
device_header = (BASE / 'GPUObjects/MVKDevice.h').read_text()
member_start = device.index('void MVKLiveList::add(id object) {')
member_end = device.index('\nstd::pair<MVKLiveList::Lock*, bool>', member_start)
membership = device[member_start:member_end]
generation_method = re.search(r'uint64_t generation\(\) const \{[^}]*\}', device_header).group(0)
live_helpers = r'''
using id = const void*;
class FixtureLiveList {
public:
    using Lock = std::mutex;
    struct Group { Lock lock; std::unordered_map<id, uint32_t> entries; std::unordered_map<id, int> preparationIdentities, membershipIdentities; };
    Group groups[16];
    std::atomic<uint64_t> _generation{1};
    Group* getGroup(id object) { return &groups[(reinterpret_cast<uintptr_t>(object) >> 4) % 16]; }
    void add(id object);
    void remove(id object);
    void advanceGeneration();
''' + generation_method + r'''
};
''' + membership.replace('MVKLiveList::', 'FixtureLiveList::')

preamble = r'''
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <unordered_map>
#include <type_traits>
#include <thread>
#include <vector>
#include <mutex>
#include <cstring>
#include <cstdlib>
#include <limits>
#include <new>
#include <array>
#include <sys/mman.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include "MVKMetal4PreparedResource.h"
'''
cmd_header = (BASE / 'Commands/MVKCmdPipeline.h').read_text()
cmd_source = (BASE / 'Commands/MVKCmdPipeline.mm').read_text()
class_start = cmd_header.index('class MVKCmdPushDescriptorSetWithTemplate :')
class_end = cmd_header.index('\n};', class_start) + len('\n};')
capture_class = cmd_header[class_start:class_end]
assert 'getMetal4RecordPolicy' not in capture_class
capture_start = cmd_source.index('#if MVK_BUILD_METAL4_FOUNDATION\nVkResult MVKCmdPushDescriptorSetWithTemplate::captureMetal4Uniforms(')
capture_end = cmd_source.index('\n\n#pragma mark -\n#pragma mark MVKCmdSetEvent', capture_start)
capture_methods = cmd_source[capture_start:capture_end]
vulkan_source = (BASE / 'Vulkan/vulkan.mm').read_text()
api_helper_start = vulkan_source.index('static void mvkCmdPushDescriptorSetWithTemplate(')
api_helper_end = vulkan_source.index('\n\nMVK_PUBLIC_VULKAN_SYMBOL void vkCmdPushDescriptorSetWithTemplate2(', api_helper_start)
capture_api_helper = vulkan_source[api_helper_start:api_helper_end]
capture_api_entries = []
for name in ['vkCmdPushDescriptorSetWithTemplate', 'vkCmdPushDescriptorSetWithTemplate2']:
    entry_start = vulkan_source.index('MVK_PUBLIC_VULKAN_SYMBOL void ' + name + '(')
    entry_end = vulkan_source.index('\n}\n', entry_start) + len('\n}\n')
    entry = vulkan_source[entry_start:entry_end]
    assert 'mvkCmdPushDescriptorSetWithTemplate(' in entry and 'MVKAddCmd(' not in entry
    assert 'MVKTraceVulkanCallStart();' in entry and 'MVKTraceVulkanCallEnd();' in entry
    assert 'MVK_PUBLIC_VULKAN_CORE_ALIAS(' + name + ', KHR);' in vulkan_source
    capture_api_entries.append(entry)
capture = r'''
// Execute the actual command class and capture/reuse/replay methods. Native
// state/layout objects are bounded stubs; GPU conversion is a separate gate.
static void require(bool, const char*);
class MVKCommandEncoder;
class MVKCommandPool;
template<class T> class MVKCommandTypePool {};
struct MVKMetal4DrawPlanState {};
class MVKCommand {
public:
    virtual ~MVKCommand() = default;
    virtual void encode(MVKCommandEncoder*) = 0;
    virtual bool planMetal4Draws(MVKMetal4DrawPlanState&) const { return false; }
protected:
    virtual MVKCommandTypePool<MVKCommand>* getTypePool(MVKCommandPool*) = 0;
};
struct MVKCommandBuffer {
    MVKCommandPool* pool = nullptr;
    std::vector<MVKCommand*> commands;
    VkResult configuration = VK_SUCCESS;
    unsigned added = 0, errors = 0;
    static MVKCommandBuffer* getMVKCommandBuffer(VkCommandBuffer handle) {
        return reinterpret_cast<MVKCommandBuffer*>(handle);
    }
    MVKCommandPool* getCommandPool() { return pool; }
    void addCommand(MVKCommand* cmd) { ++added; commands.push_back(cmd); }
    void setConfigurationResult(VkResult result) { ++errors; configuration = result; }
    void reset();
};
struct CaptureBinding { VkDescriptorType descriptorType; uint32_t descriptorCount; };
struct MVKDescriptorSetLayout {
    std::unordered_map<uint32_t, CaptureBinding> bindings;
    const CaptureBinding* getBinding(uint32_t n) const { return &bindings.at(n); }
};
struct MVKPipelineLayout {
    unsigned refs = 1; bool push = true; uint32_t set = 0;
    MVKDescriptorSetLayout descriptors;
    void retain() { ++refs; }
    void release() { require(refs > 1, "layout ownership must remain balanced"); --refs; }
    bool hasPushDescriptor() const { return push; }
    uint32_t pushDescriptor() const { return set; }
    MVKDescriptorSetLayout* getDescriptorSetLayout(uint32_t n) {
        require(n == set, "retained compatible push set selected"); return &descriptors;
    }
};
struct MVKDescriptorUpdateTemplate {
    std::vector<VkDescriptorUpdateTemplateEntry> entries;
    VkPipelineBindPoint bindPoint = VK_PIPELINE_BIND_POINT_COMPUTE;
    VkDescriptorUpdateTemplateType type = VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
    size_t legacySize = 0; // Declared stub extent, not a replacement sizing implementation.
    uint32_t getNumberOfEntries() const { return uint32_t(entries.size()); }
    const VkDescriptorUpdateTemplateEntry* getEntry(uint32_t i) const { return &entries.at(i); }
    VkPipelineBindPoint getBindPoint() const { return bindPoint; }
    VkDescriptorUpdateTemplateType getType() const { return type; }
    size_t getSize() const { return legacySize; }
};
struct CaptureState {
    std::vector<VkDescriptorBufferInfo> ordered;
    std::unordered_map<uint64_t, VkDescriptorBufferInfo> slots;
    VkPipelineBindPoint point{}; unsigned direct = 0, legacy = 0;
    void pushDescriptorSet(VkPipelineBindPoint p, MVKPipelineLayout*, uint32_t, uint32_t n, const VkWriteDescriptorSet* w) {
        point = p; ++direct;
        for (uint32_t i = 0; i < n; ++i) {
            require(w[i].descriptorCount == 1 && w[i].descriptorType == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    "compact writes keep singleton uniform metadata");
            require(w[i].sType == VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET && !w[i].pNext &&
                    !w[i].pImageInfo && !w[i].pTexelBufferView, "owned write metadata is initialized");
            require(reinterpret_cast<uintptr_t>(w[i].pBufferInfo) % alignof(VkDescriptorBufferInfo) == 0,
                    "owned descriptor info is aligned");
            ordered.push_back(*w[i].pBufferInfo);
            slots[(uint64_t(w[i].dstBinding) << 32) | w[i].dstArrayElement] = *w[i].pBufferInfo;
        }
    }
    void pushDescriptorSet(MVKDescriptorUpdateTemplate*, MVKPipelineLayout*, uint32_t, const void*) { ++legacy; }
};
class MVKCommandEncoder { public: CaptureState state; CaptureState& getState() { return state; } };
static bool selectedMetal4 = true, failCaptureAllocation = false;
static size_t lastCaptureAllocation = 0;
static size_t captureAllocationCalls = 0, captureFreeCalls = 0;
static bool mvkUseMetal4() { return selectedMetal4; }
static void* captureMalloc(size_t n) {
    ++captureAllocationCalls;
    lastCaptureAllocation = n;
    if (failCaptureAllocation) return nullptr;
    return std::malloc(n);
}
static void captureFree(void* p) { if (p) ++captureFreeCalls; std::free(p); }
static void mvkCopy(void* dst, const void* src, size_t n) { std::memcpy(dst, src, n); }
''' + capture_class + r'''
MVKCommandTypePool<MVKCommand>* MVKCmdPushDescriptorSetWithTemplate::getTypePool(MVKCommandPool*) { return nullptr; }
#define malloc captureMalloc
#define free captureFree
''' + capture_methods + r'''
#undef malloc
#undef free
struct CaptureProbe : MVKCmdPushDescriptorSetWithTemplate {
#if MVK_BUILD_METAL4_FOUNDATION
    uint32_t compact() const { return _compactUniformWriteCount; }
    bool compactPointersOwned() const {
        auto* infos = static_cast<const VkDescriptorBufferInfo*>(_pData);
        auto* writes = reinterpret_cast<const VkWriteDescriptorSet*>(infos + _compactUniformWriteCount);
        for (uint32_t i = 0; i < _compactUniformWriteCount; ++i) {
            if (writes[i].pBufferInfo != infos + i) return false;
        }
        return true;
    }
#else
    uint32_t compact() const { return 0; }
#endif
    size_t bytes() const { return _dataSize; }
    size_t capacity() const { return _dataCapacity; }
    const void* data() const { return _pData; }
    bool ownsMetadata() const { return _descUpdateTemplate == nullptr; }
};
static VkDescriptorUpdateTemplateEntry captureEntry(uint32_t binding, uint32_t array, size_t offset, size_t stride) {
    return {binding, array, 1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, offset, stride};
}
static VkDescriptorBufferInfo captureInfo(uintptr_t handle, uint64_t offset, uint64_t range) {
    return {reinterpret_cast<VkBuffer>(handle), offset, range};
}
// Bounded pool/command-buffer doubles expose the actual API helper's ownership
// transitions. They do not replace capture or Vulkan entrypoint implementations.
struct CaptureTypePool {
    bool pooling; MVKCmdPushDescriptorSetWithTemplate* resident = nullptr;
    unsigned acquired = 0, returned = 0, created = 0, destroyed = 0;
    explicit CaptureTypePool(bool enabled) : pooling(enabled) {}
    MVKCmdPushDescriptorSetWithTemplate* acquireObject() {
        ++acquired;
        if (resident) { auto* cmd=resident; resident=nullptr; return cmd; }
        ++created; return new CaptureProbe();
    }
    void returnObject(MVKCmdPushDescriptorSetWithTemplate* cmd) {
        ++returned;
        if (pooling) { require(!resident, "failed or reset node returns once to its own pool"); resident=cmd; }
        else { ++destroyed; delete cmd; }
    }
    void clear() { if (resident) { ++destroyed; delete resident; resident=nullptr; } }
    ~CaptureTypePool() { clear(); }
};
class MVKCommandPool {
public:
    CaptureTypePool _cmdPushDescriptorSetWithTemplatePool;
    explicit MVKCommandPool(bool enabled=true) : _cmdPushDescriptorSetWithTemplatePool(enabled) {}
};
void MVKCommandBuffer::reset() {
    for (auto* cmd : commands) pool->_cmdPushDescriptorSetWithTemplatePool.returnObject(
        static_cast<MVKCmdPushDescriptorSetWithTemplate*>(cmd));
    commands.clear(); configuration=VK_SUCCESS;
}
static unsigned apiTraceStarts = 0, apiTraceEnds = 0;
#define MVK_PUBLIC_VULKAN_SYMBOL
#define MVKTraceVulkanCallStart() ++apiTraceStarts
#define MVKTraceVulkanCallEnd() ++apiTraceEnds
''' + capture_api_helper + '\n' + '\n'.join(capture_api_entries) + r'''
#undef MVK_PUBLIC_VULKAN_SYMBOL
#undef MVKTraceVulkanCallStart
#undef MVKTraceVulkanCallEnd
static void captureTests() {
    MVKPipelineLayout layout;
    layout.descriptors.bindings = {{0,{VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,1}},
        {3,{VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,3}}, {4,{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,1}}};
    MVKCommandBuffer cb;
    auto record = [&](CaptureProbe& c, MVKDescriptorUpdateTemplate& t, const void* data) {
        return c.setContent(&cb, reinterpret_cast<VkDescriptorUpdateTemplate>(&t),
                            reinterpret_cast<VkPipelineLayout>(&layout), 0, data);
    };
#if MVK_BUILD_METAL4_FOUNDATION
    for (auto point : {VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_BIND_POINT_COMPUTE}) {
        for (size_t stride : {size_t(0),size_t(8),sizeof(VkDescriptorBufferInfo),size_t(4096)}) {
            CaptureProbe c; MVKDescriptorUpdateTemplate t;
            t.bindPoint = point; t.entries = {captureEntry(0,0,0,stride)};
            t.legacySize = sizeof(VkDescriptorBufferInfo);
            auto data = captureInfo(0x100,16,64), original = data;
            require(record(c,t,&data) == VK_SUCCESS && c.compact() == 1, "all singleton stride values compact");
            require(c.ownsMetadata() && c.bytes() == sizeof(VkDescriptorBufferInfo)+sizeof(VkWriteDescriptorSet),
                    "compact payload owns exact info plus metadata");
            data = captureInfo(0x200,32,128); t.entries[0].dstBinding = 3; t.bindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
            MVKCommandEncoder encoder; c.encode(&encoder);
            require(encoder.state.point == point && encoder.state.direct == 1 && !encoder.state.legacy,
                    "replay owns original bind point and uses existing direct-write overload");
            const auto& got = encoder.state.slots.at(0);
            require(got.buffer == original.buffer && got.offset == original.offset && got.range == original.range,
                    "caller payload and template metadata mutations do not change internal snapshot");
        }
    }
    require(layout.refs == 1, "destroyed command nodes release retained layout");
    // Protect prefix and tail pages: the production capture may read only the info.
    const size_t page = size_t(sysconf(_SC_PAGESIZE));
    auto* pages = static_cast<char*>(mmap(nullptr,page*3,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0));
    require(pages != MAP_FAILED, "guarded source allocation");
    auto info = captureInfo(0x300,48,256);
    const size_t offset = page*2-sizeof(info);
    memcpy(pages+offset,&info,sizeof(info));
    require(mprotect(pages,page,PROT_NONE)==0 && mprotect(pages+page*2,page,PROT_NONE)==0, "protect unrelated prefix and tail");
    {
        CaptureProbe c; MVKDescriptorUpdateTemplate t;
        t.entries={captureEntry(0,0,offset,page*4)}; t.legacySize=offset+page*4;
        require(record(c,t,pages)==VK_SUCCESS && c.compact()==1, "large offset reads no protected prefix or stride tail");
        MVKCommandEncoder encoder; c.encode(&encoder);
        require(encoder.state.slots.at(0).buffer==info.buffer, "guarded source selects expected buffer");
    }
    require(munmap(pages,page*3)==0, "release source guard pages");
    {
        CaptureProbe c; MVKDescriptorUpdateTemplate t;
        std::array<unsigned char,4096> raw{};
        auto first=captureInfo(0x400,64,32),last=captureInfo(0x500,80,48),array=captureInfo(0x600,96,80);
        memcpy(raw.data()+7,&first,sizeof(first)); memcpy(raw.data()+509,&last,sizeof(last));
        memcpy(raw.data()+2049,&array,sizeof(array));
        t.entries={captureEntry(0,0,7,0),captureEntry(0,0,509,4096),captureEntry(3,1,2049,8)};
        t.legacySize=raw.size();
        require(record(c,t,raw.data())==VK_SUCCESS && c.compact()==3 && c.bytes()<t.legacySize,
                "sparse unaligned input becomes one compact ordered payload");
        std::memset(raw.data(),0,raw.size());
        MVKCommandEncoder encoder; auto sentinel=captureInfo(0x700,112,96);
        encoder.state.slots[(uint64_t(3)<<32)|0]=sentinel; encoder.state.slots[(uint64_t(3)<<32)|2]=sentinel;
        c.encode(&encoder);
        require(encoder.state.ordered.size()==3 && encoder.state.ordered[0].buffer==first.buffer &&
                encoder.state.ordered[1].buffer==last.buffer && encoder.state.slots.at(0).buffer==last.buffer,
                "duplicate destinations keep original update order");
        require(encoder.state.slots.at((uint64_t(3)<<32)|1).buffer==array.buffer &&
                encoder.state.slots.at((uint64_t(3)<<32)|0).buffer==sentinel.buffer &&
                encoder.state.slots.at((uint64_t(3)<<32)|2).buffer==sentinel.buffer,
                "in-binding array update preserves untouched elements");
        // All these rejected shapes preserve the legacy path and clear old compact state.
        auto baseline=t.entries;
        for (unsigned variant=0;variant<8;++variant) {
            t.entries=baseline; t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
            t.bindPoint=VK_PIPELINE_BIND_POINT_COMPUTE; selectedMetal4=true;
            if(variant==0) t.entries.back().descriptorType=VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT;
            if(variant==1) t.entries.back().descriptorCount=2;
            if(variant==2) t.entries.back().dstArrayElement=3;
            if(variant==3) t.entries.back().dstBinding=4;
            if(variant==4) t.entries.clear();
            if(variant==5) t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET;
            if(variant==6) t.bindPoint=VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR;
            if(variant==7) selectedMetal4=false;
            require(record(c,t,raw.data())==VK_SUCCESS && !c.compact(), "non-admitted template/backend clears compact mode");
            MVKCommandEncoder legacy; c.encode(&legacy);
            require(legacy.state.legacy==1 && legacy.state.direct==0, "fallback dispatch remains the original template overload");
        }
        selectedMetal4=true; t.entries=baseline; t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
        t.bindPoint=VK_PIPELINE_BIND_POINT_COMPUTE; memcpy(raw.data()+7,&first,sizeof(first));
        require(record(c,t,raw.data())==VK_SUCCESS && c.compact()==3, "compact-fallback-compact pooled node reuse");
    }
    {
        CaptureProbe c; MVKDescriptorUpdateTemplate t;
        t.entries={captureEntry(0,0,std::numeric_limits<size_t>::max()-7,0)};
        require(record(c,t,&info)==VK_ERROR_OUT_OF_HOST_MEMORY && !c.compact(), "offset overflow fails before reading input");
        t.entries[0].offset=0;
        require(record(c,t,reinterpret_cast<void*>(std::numeric_limits<uintptr_t>::max()-8))==VK_ERROR_OUT_OF_HOST_MEMORY && !c.compact(),
                "source address overflow fails before reading input");
        failCaptureAllocation=true;
        require(record(c,t,&info)==VK_ERROR_OUT_OF_HOST_MEMORY && !c.compact() && !c.data(),
                "allocation failure publishes no partial compact snapshot");
        require(!c.bytes() && !c.capacity(), "initial compact failure publishes no logical size or capacity");
        failCaptureAllocation=false;
        require(record(c,t,&info)==VK_SUCCESS && c.compact()==1, "failed node can be safely reused");
        t.entries.push_back(captureEntry(3,1,0,0));
        const void* saved=c.data(); const size_t savedSize=c.bytes(), savedCapacity=c.capacity();
        std::vector<unsigned char> savedPayload(static_cast<const unsigned char*>(saved),
                                              static_cast<const unsigned char*>(saved)+savedSize);
        const size_t frees=captureFreeCalls; failCaptureAllocation=true;
        require(record(c,t,&info)==VK_ERROR_OUT_OF_HOST_MEMORY && !c.compact() && c.data()==saved,
                "growth failure retains owned storage without publishing stale compact metadata");
        require(c.capacity()==savedCapacity && c.bytes()==savedSize && captureFreeCalls==frees &&
                std::memcmp(c.data(),savedPayload.data(),savedSize)==0,
                "compact failed growth preserves actual capacity and complete owned payload");
        failCaptureAllocation=false;
        require(record(c,t,&info)==VK_SUCCESS && c.compact()==2 && c.compactPointersOwned(),
                "growth retry rebuilds all owned pointers");
    }
    {
        CaptureProbe c; MVKDescriptorUpdateTemplate t;
        std::array<VkDescriptorBufferInfo,4> values{};
        const size_t allocations=captureAllocationCalls, frees=captureFreeCalls;
        const size_t maximum=values.size()*(sizeof(VkDescriptorBufferInfo)+sizeof(VkWriteDescriptorSet));
        const void* storage=nullptr;
        unsigned round=0;
        for (uint32_t count : {4u,1u,3u,4u}) {
            t.entries.clear(); t.bindPoint=(round%2 ? VK_PIPELINE_BIND_POINT_GRAPHICS : VK_PIPELINE_BIND_POINT_COMPUTE);
            for (uint32_t i=0;i<count;++i) {
                values[i]=captureInfo(0x800+round*0x100+i*16,round*64+i*8,32+round*16+i);
                t.entries.push_back(captureEntry(i?3:0,i?i-1:0,i*sizeof(VkDescriptorBufferInfo),0));
            }
            t.legacySize=count*sizeof(VkDescriptorBufferInfo);
            require(record(c,t,values.data())==VK_SUCCESS && c.compact()==count && c.compactPointersOwned(),
                    "compact count changes rebuild pointers for the current payload");
            if (!storage) storage=c.data();
            require(c.data()==storage && c.capacity()==maximum &&
                    c.bytes()==count*(sizeof(VkDescriptorBufferInfo)+sizeof(VkWriteDescriptorSet)) &&
                    captureAllocationCalls==allocations+1 && captureFreeCalls==frees,
                    "compact large-small-medium-large reuses physical capacity and exact logical extent");
            MVKCommandEncoder encoder; c.encode(&encoder);
            require(encoder.state.ordered.size()==count && encoder.state.point==t.bindPoint,
                    "compact reuse replays only current count and bind point");
            for (uint32_t i=0;i<count;++i) {
                const auto& got=encoder.state.ordered[i];
                require(got.buffer==values[i].buffer && got.offset==values[i].offset && got.range==values[i].range,
                        "compact reuse copies current values rather than an old snapshot");
            }
            ++round;
        }
    }
    {
        CaptureProbe c; MVKDescriptorUpdateTemplate t;
        std::array<unsigned char,1024> raw{};
        const auto infoA=captureInfo(0xc00,24,72), infoB=captureInfo(0xd00,48,144);
        t.entries={captureEntry(0,0,0,0),captureEntry(3,1,sizeof(VkDescriptorBufferInfo),0)};
        t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET; t.legacySize=512;
        selectedMetal4=false; raw.fill(0x6a);
        require(record(c,t,raw.data())==VK_SUCCESS && !c.compact() && c.capacity()==512,
                "Metal3 generic capture establishes reusable storage");
        const void* storage=c.data(); const size_t allocations=captureAllocationCalls;
        selectedMetal4=true; t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
        std::memcpy(raw.data(),&infoA,sizeof(infoA)); std::memcpy(raw.data()+sizeof(infoA),&infoB,sizeof(infoB));
        require(record(c,t,raw.data())==VK_SUCCESS && c.compact()==2 && c.compactPointersOwned() &&
                c.data()==storage && c.capacity()==512 && captureAllocationCalls==allocations,
                "generic-to-compact mode switch rebuilds metadata within retained storage");
        t.entries.resize(1);
        require(record(c,t,raw.data())==VK_SUCCESS && c.compact()==1 && c.compactPointersOwned() &&
                c.data()==storage && captureAllocationCalls==allocations,
                "smaller compact capture rebases write array in the same storage");
        MVKCommandEncoder compact; c.encode(&compact);
        require(compact.state.ordered.size()==1 && compact.state.ordered[0].buffer==infoA.buffer,
                "smaller mode-switch payload has no stale second descriptor");
        t.entries.push_back(captureEntry(3,1,sizeof(VkDescriptorBufferInfo),0));
        require(record(c,t,raw.data())==VK_SUCCESS && c.compact()==2 && c.compactPointersOwned() &&
                c.data()==storage && captureAllocationCalls==allocations,
                "regrown compact payload uses generic allocation capacity");
        selectedMetal4=false; t.legacySize=256; raw.fill(0x3b);
        require(record(c,t,raw.data())==VK_SUCCESS && !c.compact() && c.bytes()==256 && c.capacity()==512 &&
                c.data()==storage && captureAllocationCalls==allocations && std::memcmp(c.data(),raw.data(),256)==0,
                "compact-to-Metal3 switch copies the current generic payload without reallocating");
        MVKCommandEncoder generic; c.encode(&generic);
        require(generic.state.legacy==1 && !generic.state.direct, "mode switch uses the original generic replay overload");
        selectedMetal4=true; t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
        std::memcpy(raw.data(),&infoB,sizeof(infoB)); std::memcpy(raw.data()+sizeof(infoB),&infoA,sizeof(infoA));
        require(record(c,t,raw.data())==VK_SUCCESS && c.compact()==2 && c.compactPointersOwned(),
                "re-entering compact mode rebuilds current values and all pointers");
        MVKCommandEncoder current; c.encode(&current);
        require(current.state.ordered[0].buffer==infoB.buffer && current.state.ordered[1].buffer==infoA.buffer,
                "final compact replay follows current mode-switch values");
    }
#endif
#if MVK_BUILD_METAL4_FOUNDATION
    const std::array<bool,2> genericBackends{{false,true}};
#else
    const std::array<bool,1> genericBackends{{false}};
#endif
    for (bool backend : genericBackends) {
        selectedMetal4=backend;
        CaptureProbe c; MVKDescriptorUpdateTemplate t;
        t.entries={captureEntry(0,0,0,0)}; t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET;
        std::array<unsigned char,1024> raw{};
        const size_t allocations=captureAllocationCalls, frees=captureFreeCalls;
        require(record(c,t,nullptr)==VK_SUCCESS && !c.data() && !c.bytes() && !c.capacity() &&
                captureAllocationCalls==allocations, "empty generic capture does not allocate storage");
        size_t capacity=0, grows=0; unsigned round=0;
        const void* storage=nullptr;
        for (size_t bytes : {size_t(512),size_t(64),size_t(256),size_t(512),size_t(768),size_t(0),size_t(128)}) {
            for (size_t i=0;i<raw.size();++i) raw[i]=static_cast<unsigned char>((round*37+i)%256);
            const auto expected=raw; t.legacySize=bytes;
            const bool growth=bytes>capacity;
            if (growth) { capacity=bytes; ++grows; }
            require(record(c,t,raw.data())==VK_SUCCESS && !c.compact() && c.bytes()==bytes && c.capacity()==capacity,
                    "generic pooled capture separates logical size from physical capacity");
            if (!growth) require(c.data()==storage, "generic size changes within capacity keep the owned block");
            storage=c.data();
            require(captureAllocationCalls==allocations+grows && captureFreeCalls==frees+grows-1,
                    "generic large-small-medium-large and zero-size reuse allocate only on actual growth");
            raw.fill(0xa5);
            require(std::memcmp(c.data(),expected.data(),bytes)==0, "generic reuse owns exactly the current logical payload");
            MVKCommandEncoder encoder; c.encode(&encoder);
            require(encoder.state.legacy==1 && !encoder.state.direct, "generic reuse preserves template replay routing");
            ++round;
        }
    }
    for (bool backend : genericBackends) {
        selectedMetal4=backend;
        CaptureProbe c; MVKDescriptorUpdateTemplate t;
        t.entries={captureEntry(0,0,0,0)}; t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET;
        std::array<unsigned char,1024> raw{}; raw.fill(0x41); t.legacySize=128;
        failCaptureAllocation=true;
        require(record(c,t,raw.data())==VK_ERROR_OUT_OF_HOST_MEMORY && !c.compact() && !c.data() &&
                !c.bytes() && !c.capacity(), "initial generic OOM reports failure without invented storage capacity");
        failCaptureAllocation=false;
        require(record(c,t,raw.data())==VK_SUCCESS && c.bytes()==128 && c.capacity()==128,
                "generic node rebuilds its payload after an initial allocation failure");
        const void* storage=c.data(); const size_t frees=captureFreeCalls;
        std::array<unsigned char,128> saved{}; std::memcpy(saved.data(),storage,saved.size());
        t.legacySize=512; raw.fill(0x52); failCaptureAllocation=true;
        require(record(c,t,raw.data())==VK_ERROR_OUT_OF_HOST_MEMORY && !c.compact() && c.data()==storage &&
                c.bytes()==128 && c.capacity()==128 && captureFreeCalls==frees &&
                std::memcmp(c.data(),saved.data(),saved.size())==0,
                "generic failed growth retains owned capacity and payload without reporting success");
        failCaptureAllocation=false;
#if MVK_BUILD_METAL4_FOUNDATION
        if (backend) {
            const auto info=captureInfo(0xe00,96,192);
            t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR;
            std::memcpy(raw.data(),&info,sizeof(info));
            require(record(c,t,raw.data())==VK_SUCCESS && c.compact()==1 && c.compactPointersOwned() &&
                    c.data()==storage && c.capacity()==128, "failed generic growth can be followed by compact capture in retained storage");
            MVKCommandEncoder encoder; c.encode(&encoder);
            require(encoder.state.ordered[0].buffer==info.buffer, "compact retry owns current values after generic OOM");
            t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET;
        }
#endif
        raw.fill(0x63);
        require(record(c,t,raw.data())==VK_SUCCESS && !c.compact() && c.bytes()==512 && c.capacity()==512 &&
                std::memcmp(c.data(),raw.data(),512)==0, "generic growth retry rebuilds requested payload and capacity");
    }
#if MVK_BUILD_METAL4_FOUNDATION
    {
        selectedMetal4=true; CaptureProbe c; MVKDescriptorUpdateTemplate t;
        auto info=captureInfo(0xf00,128,256); t.entries={captureEntry(0,0,0,0)};
        require(record(c,t,&info)==VK_SUCCESS && c.compact()==1, "compact failure-switch setup");
        const void* storage=c.data(); const size_t capacity=c.capacity(), frees=captureFreeCalls;
        t.entries.push_back(captureEntry(3,1,0,0)); failCaptureAllocation=true;
        require(record(c,t,&info)==VK_ERROR_OUT_OF_HOST_MEMORY && !c.compact() && c.data()==storage &&
                c.capacity()==capacity && captureFreeCalls==frees, "compact failed growth keeps capacity for a later generic capture");
        failCaptureAllocation=false;
        std::array<unsigned char,32> raw{}; raw.fill(0x74);
        selectedMetal4=false; t.legacySize=raw.size();
        require(record(c,t,raw.data())==VK_SUCCESS && !c.compact() && c.data()==storage && c.bytes()==raw.size() &&
                c.capacity()==capacity && std::memcmp(c.data(),raw.data(),raw.size())==0,
                "failed compact growth can be followed by Metal3 generic capture without stale metadata");
        MVKCommandEncoder encoder; c.encode(&encoder);
        require(encoder.state.legacy==1 && !encoder.state.direct, "generic retry after compact OOM preserves replay route");
    }
#endif
    selectedMetal4=true;
    require(layout.refs==1, "layout ownership remains balanced after errors and reuse");
}
static void captureLifecycleTests() {
#if MVK_BUILD_METAL4_FOUNDATION
    const std::array<bool,2> backends{{false,true}};
#else
    const std::array<bool,1> backends{{false}};
#endif
    for (bool secondApi : {false,true}) {
        for (bool pooling : {false,true}) {
            for (bool backend : backends) {
                selectedMetal4=backend;
                MVKPipelineLayout layout; layout.descriptors.bindings={{0,{VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,1}}};
                MVKCommandPool commandPool(pooling); auto& pool=commandPool._cmdPushDescriptorSetWithTemplatePool;
                MVKCommandBuffer cb; cb.pool=&commandPool;
                MVKDescriptorUpdateTemplate t; t.entries={captureEntry(0,0,0,0)};
                t.type=VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_DESCRIPTOR_SET; t.legacySize=128;
                std::array<unsigned char,1024> raw{}; raw.fill(0x85);
                const unsigned starts=apiTraceStarts, ends=apiTraceEnds;
                auto call = [&] {
                    if (secondApi) {
                        VkPushDescriptorSetWithTemplateInfo info{};
                        info.sType=VK_STRUCTURE_TYPE_PUSH_DESCRIPTOR_SET_WITH_TEMPLATE_INFO;
                        info.descriptorUpdateTemplate=reinterpret_cast<VkDescriptorUpdateTemplate>(&t);
                        info.layout=reinterpret_cast<VkPipelineLayout>(&layout); info.set=0; info.pData=raw.data();
                        vkCmdPushDescriptorSetWithTemplate2(reinterpret_cast<VkCommandBuffer>(&cb),&info);
                    } else {
                        vkCmdPushDescriptorSetWithTemplate(reinterpret_cast<VkCommandBuffer>(&cb),
                            reinterpret_cast<VkDescriptorUpdateTemplate>(&t),reinterpret_cast<VkPipelineLayout>(&layout),0,raw.data());
                    }
                };
                failCaptureAllocation=true; call(); failCaptureAllocation=false;
                require(cb.configuration==VK_ERROR_OUT_OF_HOST_MEMORY && cb.commands.empty() && cb.errors==1 &&
                        cb.added==0 && pool.returned==1 && pool.acquired==1,
                        "both actual generic Vulkan APIs record OOM and return the unadded command exactly once");
                require((pooling && pool.resident && layout.refs==2) || (!pooling && pool.destroyed==1 && layout.refs==1),
                        "actual helper retains pooled ownership or destroys an unpooled failed node");
                cb.reset(); call();
                require(cb.commands.size()==1 && cb.added==1 && pool.returned==1,
                        "successful generic API command remains owned by the command buffer until reset");
                auto* recorded=static_cast<CaptureProbe*>(cb.commands.at(0)); const void* storage=recorded->data();
                require(!recorded->compact() && recorded->bytes()==128 && recorded->capacity()==128 &&
                        std::memcmp(recorded->data(),raw.data(),128)==0,
                        "actual generic API retry captures current payload after initial OOM");
                cb.reset(); t.legacySize=512; raw.fill(0x96);
                failCaptureAllocation=true; call(); failCaptureAllocation=false;
                require(cb.commands.empty() && cb.configuration==VK_ERROR_OUT_OF_HOST_MEMORY && cb.errors==2 &&
                        cb.added==1 && pool.returned==3,
                        "generic growth failure is returned after the successful prior node was reset");
                if (pooling) {
                    auto* retained=static_cast<CaptureProbe*>(pool.resident);
                    require(retained && retained->data()==storage && retained->capacity()==128 && retained->bytes()==128 &&
                            static_cast<const unsigned char*>(retained->data())[0]==0x85 && !retained->compact(),
                            "actual failed pooled API growth preserves allocation and clears published compact mode");
                } else {
                    require(pool.destroyed==3 && layout.refs==1,
                            "unpooled API OOM destroys failed node and retires layout ownership");
                }
                cb.reset(); raw.fill(0xa7); call();
                require(cb.commands.size()==1 && cb.added==2 && cb.configuration==VK_SUCCESS,
                        "returned generic node can be retried through the real API helper");
                recorded=static_cast<CaptureProbe*>(cb.commands.at(0));
                require(recorded->bytes()==512 && recorded->capacity()==512 &&
                        std::memcmp(recorded->data(),raw.data(),512)==0,
                        "real helper retry rebuilds all requested generic bytes");
                require(apiTraceStarts-starts==4 && apiTraceEnds-ends==4,
                        "both actual API versions preserve trace brackets on success and failure");
                cb.reset(); pool.clear();
                require(layout.refs==1 && pool.returned==pool.acquired && pool.destroyed==pool.created,
                        "API generic lifecycle retires every acquired node and its retained layout");
            }
#if MVK_BUILD_METAL4_FOUNDATION
            {
                selectedMetal4=true;
                MVKPipelineLayout layout; layout.descriptors.bindings={{0,{VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,1}}};
                MVKCommandPool commandPool(pooling); auto& pool=commandPool._cmdPushDescriptorSetWithTemplatePool;
                MVKCommandBuffer cb; cb.pool=&commandPool;
                MVKDescriptorUpdateTemplate t; t.entries={captureEntry(0,0,0,0)};
                auto payload=captureInfo(0x1200,160,320);
                const unsigned starts=apiTraceStarts, ends=apiTraceEnds;
                auto call = [&](const void* data) {
                    if (secondApi) {
                        VkPushDescriptorSetWithTemplateInfo info{};
                        info.sType=VK_STRUCTURE_TYPE_PUSH_DESCRIPTOR_SET_WITH_TEMPLATE_INFO;
                        info.descriptorUpdateTemplate=reinterpret_cast<VkDescriptorUpdateTemplate>(&t);
                        info.layout=reinterpret_cast<VkPipelineLayout>(&layout); info.set=0; info.pData=data;
                        vkCmdPushDescriptorSetWithTemplate2(reinterpret_cast<VkCommandBuffer>(&cb),&info);
                    } else {
                        vkCmdPushDescriptorSetWithTemplate(reinterpret_cast<VkCommandBuffer>(&cb),
                            reinterpret_cast<VkDescriptorUpdateTemplate>(&t),reinterpret_cast<VkPipelineLayout>(&layout),0,data);
                    }
                };
                failCaptureAllocation=true; call(&payload); failCaptureAllocation=false;
                require(cb.configuration==VK_ERROR_OUT_OF_HOST_MEMORY && cb.commands.empty() && pool.returned==1,
                        "compact OOM through each actual Vulkan API returns the unadded node");
                cb.reset(); t.entries[0].offset=std::numeric_limits<size_t>::max()-7;
                const size_t allocations=captureAllocationCalls; call(&payload);
                require(cb.configuration==VK_ERROR_OUT_OF_HOST_MEMORY && cb.commands.empty() && pool.returned==2 &&
                        captureAllocationCalls==allocations,
                        "compact overflow error returns its API node before reading or allocating caller data");
                cb.reset(); t.entries[0].offset=0; call(&payload);
                auto* recorded=static_cast<CaptureProbe*>(cb.commands.at(0)); const void* storage=recorded->data();
                const size_t capacity=recorded->capacity();
                require(recorded->compact()==1 && recorded->compactPointersOwned(),
                        "actual compact API retry builds current owned pointers");
                cb.reset(); t.entries.push_back(captureEntry(0,0,0,0));
                failCaptureAllocation=true; call(&payload); failCaptureAllocation=false;
                require(cb.commands.empty() && cb.configuration==VK_ERROR_OUT_OF_HOST_MEMORY && pool.returned==4,
                        "compact growth OOM returns its API node instead of recording stale state");
                if (pooling) {
                    auto* retained=static_cast<CaptureProbe*>(pool.resident);
                    require(retained && !retained->compact() && retained->data()==storage && retained->capacity()==capacity,
                            "actual helper returns compact failed growth with retained storage and unpublished metadata");
                } else {
                    require(pool.destroyed==4 && layout.refs==1,
                            "actual helper destroys every unpooled compact error node");
                }
                cb.reset(); selectedMetal4=false; std::array<unsigned char,32> generic{}; generic.fill(0xb8);
                t.legacySize=generic.size(); call(generic.data());
                recorded=static_cast<CaptureProbe*>(cb.commands.at(0));
                require(!recorded->compact() && recorded->bytes()==generic.size() &&
                        std::memcmp(recorded->data(),generic.data(),generic.size())==0 &&
                        (!pooling || (recorded->data()==storage && recorded->capacity()==capacity)),
                        "actual helper switches returned compact failure node to a current Metal3 payload");
                require(apiTraceStarts-starts==5 && apiTraceEnds-ends==5,
                        "compact error and retry keep both actual API trace brackets");
                cb.reset(); pool.clear();
                require(layout.refs==1 && pool.returned==pool.acquired && pool.destroyed==pool.created,
                        "API compact lifecycle retires every acquired node and retained layout");
            }
#endif
        }
    }
    failCaptureAllocation=false; selectedMetal4=true;
}
'''
main = r'''
#if MVK_BUILD_METAL4_FOUNDATION
class FixturePreparationCache : public MVKMetal4DescriptorPreparationCache {
public:
    bool matches(const MVKMetal4DescriptorPreparationStamp& stamp, uint32_t binding, uint64_t generation) {
        return MVKMetal4DescriptorPreparationCache::matches(stamp,binding,generation,[&]{return generation;});
    }
};
#endif
static unsigned assertions = 0;
static void require(bool value, const char* message) {
    if (!value) { throw std::runtime_error(message); }
    ++assertions;
}
int main() {
    try {
        captureTests();
        captureLifecycleTests();
#if MVK_BUILD_METAL4_FOUNDATION
        using Stamp = MVKMetal4DescriptorPreparationStamp;
        using Cache = FixturePreparationCache;
        static_assert(std::is_trivial<Stamp>::value, "pool storage remains trivial");
        Cache cache;
        Stamp set{};
        require(!cache.matches(set, 0, 1), "zero/push-descriptor stamp never hits");
        set.initialize(true);
        require(set.incarnation && set.revision == 1 && !cache.matches(set, 0, 1), "fresh set has no proof");
        cache.remember(set, 0, 1);
        require(cache.matches(set, 0, 1), "unchanged retained binding hits");
        require(!cache.matches(set, 1, 1), "new shader-used binding still requires preparation");
        set.updated();
        require(!cache.matches(set, 0, 1), "write/copy/template revision invalidates proof");
        cache.remember(set, 0, 1);
        require(cache.matches(set, 0, 1), "updated payload can be reproved");
        require(!cache.matches(set, 0, 2), "live-resource membership transition invalidates proof");
        cache.remember(set, 0, 2);
        auto oldIncarnation = set.incarnation;
        set.initialize(true); // Same host storage after pool free/reset/reallocation.
        require(set.incarnation != oldIncarnation && !cache.matches(set, 0, 2), "pool reuse cannot alias old identity");
        cache.remember(set, 0, 2);
        cache.clear(); // The production weak Recording token mismatch calls this.
        require(!cache.matches(set, 0, 2), "new submission cannot inherit preparation");
        set.initialize(false);
        set.updated(); cache.remember(set, 0, 2);
        require(!set.incarnation && !set.revision && !cache.matches(set, 0, 2), "excluded set stays disabled through updates");
        require(Stamp::allowsBindingFlags(0) && Stamp::allowsBindingFlags(8) &&
                !Stamp::allowsBindingFlags(1) && !Stamp::allowsBindingFlags(2) &&
                !Stamp::allowsBindingFlags(4) && !Stamp::allowsBindingFlags(15), "mutable and partially-bound exclusions are exact");
        set = {17, UINT64_MAX}; set.updated(); cache.remember(set, 0, 2);
        require(set.revision == 0 && !cache.matches(set, 0, 2), "revision overflow disables rather than wraps");
        std::atomic<uint64_t> exhausted{UINT64_MAX - 1};
        require(Stamp::allocateIncarnation(exhausted) == UINT64_MAX &&
                Stamp::allocateIncarnation(exhausted) == 0 && exhausted == UINT64_MAX,
                "incarnation exhaustion cannot wrap or repeat");
        set.initialize(true); cache.remember(set, 0, UINT64_MAX);
        require(!cache.matches(set, 0, UINT64_MAX), "saturated live generation disables caching");
        cache.clear();
        for (uint32_t i = 0; i < 256; ++i) { cache.remember(set, i, 7); }
        cache.remember(set, 256, 7);
        require(cache.matches(set, 255, 7) && !cache.matches(set, 256, 7), "bounded overflow conservatively misses");
        set.updated(); cache.remember(set, 255, 7);
        require(cache.matches(set, 255, 7), "full cache still refreshes existing binding");
        cache.clear(); unsigned preparations = 0;
        for (unsigned draw = 0; draw < 32; ++draw) {
            if (!cache.matches(set, 0, 9)) { ++preparations; cache.remember(set, 0, 9); }
        }
        require(preparations == 1, "32 unchanged preparations reduce to one proof");
        set.updated();
        if (!cache.matches(set, 0, 9)) { ++preparations; cache.remember(set, 0, 9); }
        require(preparations == 2, "changed payload always prepares again");
        TestSet payload{set, 16, "payload"};
        TestLiveResources lives{{true, 9}}; TestSink sink{0, true};
        cache.clear();
        require(!proveBinding(cache, &payload, lives, sink, (void*)1, 8, 16) &&
                lives.buffers.checks == 0 && !cache.matches(set, 0, 9), "truncated payload fails before any registration or admission");
        cache.clear(); payload.cpuBuffer = nullptr;
        require(!proveBinding(cache, &payload, lives, sink, (void*)1, 0, 16) &&
                !cache.matches(set, 0, 9), "missing CPU payload is never admitted");
        payload.cpuBuffer = "payload"; lives.buffers.live = false;
        require(proveBinding(cache, &payload, lives, sink, (void*)1, 0, 16) &&
                sink.registrations == 0 && !cache.matches(set, 0, 9), "dead payload remains on original live-check path");
        lives.buffers.live = true;
        require(proveBinding(cache, &payload, lives, sink, nullptr, 0, 16) &&
                !cache.matches(set, 0, 9), "nil descriptor cannot enter cache even if a live-list double accepts nil");
        cache.clear(); sink.succeeds = false;
        require(!proveBinding(cache, &payload, lives, sink, (void*)1, 0, 16) &&
                !cache.matches(set, 0, 9), "registration failure never publishes proof");
        cache.clear(); sink.succeeds = true; lives.buffers.currentGeneration = 10;
        require(proveBinding(cache, &payload, lives, sink, (void*)1, 0, 16) &&
                !cache.matches(set, 0, 10), "membership transition during scan prevents admission");
        cache.clear(); lives.buffers.currentGeneration = 9;
        require(proveBinding(cache, &payload, lives, sink, (void*)1, 0, 16) &&
                cache.matches(set, 0, 9), "complete valid registration admits exact binding");
        FixtureLiveList membershipList;
        membershipList.add((void*)16);
        require(membershipList.generation() == 2, "first live membership publishes generation");
        membershipList.add((void*)16); membershipList.remove((void*)16);
        require(membershipList.generation() == 2, "retained alias refcounts preserve live identity");
        membershipList.remove((void*)16); membershipList.remove((void*)16);
        require(membershipList.generation() == 3, "final removal advances once; absent removal is inert");
        FixtureLiveList concurrent;
        std::vector<std::thread> threads;
        for (unsigned thread = 0; thread < 4; ++thread) {
            threads.emplace_back([&, thread] {
                for (unsigned i = 0; i < 2000; ++i) {
                    id token = reinterpret_cast<id>(uintptr_t((thread + 1) * 16));
                    concurrent.add(token); concurrent.remove(token);
                }
            });
        }
        for (auto& thread : threads) { thread.join(); }
        require(concurrent.generation() == 16001, "concurrent group transitions cannot lose generation increments");
        concurrent._generation.store(UINT64_MAX - 1);
        concurrent.advanceGeneration(); concurrent.advanceGeneration();
        require(concurrent.generation() == UINT64_MAX, "live generation saturates without wrapped reuse");
#endif
        std::printf("{\"suite\":\"descriptor_preparation_cpu\",\"passed\":%u,\"gpuExecuted\":false,\"gameExecuted\":false}\n", assertions);
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what()); return 1;
    }
}
'''
OUT.mkdir(parents=True, exist_ok=True)
cpp = OUT / 'exact-production-helpers.cpp'
cpp.write_text(preamble + '\n#if MVK_BUILD_METAL4_FOUNDATION\n' + flags + '\n' + helpers + '\n' + branches + '\n' + live_helpers + '\n#endif\n' + capture + '\n' + main)
binary = OUT / 'descriptor-preparation-cpu'
command = ['xcrun', 'clang++', '-std=c++17', '-O1', '-g', '-fsanitize=address,undefined',
           '-fno-omit-frame-pointer', '-DMVK_BUILD_METAL4_FOUNDATION=1',
           '-I'+str(ROOT/'build/run66-vulkan-headers-src-20260903/include'), '-I'+str(BASE/'GPUObjects'),
           str(cpp), '-o', str(binary)]
compiled = subprocess.run(command, text=True, capture_output=True)
(OUT / 'compile.log').write_text(compiled.stdout + compiled.stderr)
if compiled.returncode: sys.exit(compiled.returncode)
result = subprocess.run([str(binary)], text=True, capture_output=True)
(OUT / 'execution.log').write_text(result.stdout + result.stderr)
# Compile and execute the same extracted capture class, generic methods, API
# helper, and lifecycle assertions with Metal4 foundation absent. The guarded
# descriptor-cache assertions above remain specific to the foundation-on build.
foundation_off_binary = OUT / 'descriptor-preparation-cpu-foundation-off'
foundation_off_command = [arg.replace('-DMVK_BUILD_METAL4_FOUNDATION=1', '-DMVK_BUILD_METAL4_FOUNDATION=0') for arg in command]
foundation_off_command[-1] = str(foundation_off_binary)
foundation_off_compiled = subprocess.run(foundation_off_command, text=True, capture_output=True)
(OUT / 'compile-foundation-off.log').write_text(foundation_off_compiled.stdout + foundation_off_compiled.stderr)
if foundation_off_compiled.returncode: sys.exit(foundation_off_compiled.returncode)
foundation_off_result = subprocess.run([str(foundation_off_binary)], text=True, capture_output=True)
(OUT / 'execution-foundation-off.log').write_text(foundation_off_result.stdout + foundation_off_result.stderr)
unchanged = all(sha((BASE / name).read_bytes()) == pin for name, pin in pins.items())
receipt = {'schema': 'metal4-r41-descriptor-preparation-cpu-v1', 'inputs': pins,
           'exactProductionHelpersSHA256': sha(helpers.encode()), 'flagsSHA256': sha(flags.encode()), 'exactProductionBranchesSHA256': sha((bounds_branch + live_branch + admit_branch).encode()),
           'compileCommand': command, 'exitCode': result.returncode, 'inputsUnchanged': unchanged,
           'gpuExecuted': False, 'gameExecuted': False,
           'sourceWiringChecksPassed': True, 'exactLiveMembershipMethodsSHA256': sha(membership.encode()),
           'exactCaptureClassSHA256': sha(capture_class.encode()), 'exactCaptureMethodsSHA256': sha(capture_methods.encode()),
           'exactCaptureAPIHelperSHA256': sha(capture_api_helper.encode()),
           'exactCaptureAPIEntrypointsSHA256': sha('\n'.join(capture_api_entries).encode()),
           'foundationDisabled': {'compileCommand': foundation_off_command, 'exitCode': foundation_off_result.returncode},
           'compactUniformRecordPolicy': 'Deferred unchanged; no override added',
           'limits': ['Actual capture/eligibility/replay methods use bounded layout/state/allocator stubs; GPU conversion and native lifetimes require existing native validation.',
                      'Actual Vulkan capture helper and both core entrypoints use bounded command-buffer/pool doubles; full production pool integration is separate from CPU lifecycle assertions.',
                      'Command-local high-water storage persists until pool/object destruction. Growth temporarily overlaps old and new allocations; BAR frequency and retained-memory effect are unmeasured.',
                      'Legacy template size is a declared stub; rejected-path stride defect is not fixed or claimed covered.',
                      'Operation reduction is helper behavior, not measured BAR timing.']}
if result.returncode == 0: receipt['result'] = json.loads(result.stdout)
if foundation_off_result.returncode == 0: receipt['foundationDisabled']['result'] = json.loads(foundation_off_result.stdout)
(OUT / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
sys.exit((result.returncode or foundation_off_result.returncode) if unchanged else 2)
