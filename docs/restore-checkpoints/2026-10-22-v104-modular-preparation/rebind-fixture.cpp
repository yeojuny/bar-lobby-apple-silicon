// Stage/layout/Metal surfaces are mocks; production bodies are extracted intact.
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using VkShaderStageFlags = uint32_t;
using VkDescriptorType = int;
enum MVKShaderStage { kMVKShaderStageVertex, kMVKShaderStageTessCtl,
    kMVKShaderStageTessEval, kMVKShaderStageGeometry, kMVKShaderStageFragment,
    kMVKShaderStageCompute, kMVKShaderStageCount };
enum VkPipelineBindPoint { VK_PIPELINE_BIND_POINT_GRAPHICS, VK_PIPELINE_BIND_POINT_COMPUTE,
    VK_PIPELINE_BIND_POINT_ALL };
enum { VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
    VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
    VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC };
enum class MVKArgumentBufferMode { Off, On };
enum class MVKNonVolatileImplicitBuffer { BufferSize, DynamicOffset, Swizzle, PushConstant };
template<typename T, int N> struct MVKSmallVector : std::vector<T> {
    using std::vector<T>::vector;
};
template<typename T> struct MVKArrayRef {
    T* data;
    size_t count;
    MVKArrayRef(T* p, size_t n): data(p), count(n) {}
    size_t size() const { return count; }
};
template<typename T> MVKArrayRef(T*, size_t)->MVKArrayRef<T>;
template<typename V> void mvkEnsureSize(V& v, size_t n) { if (v.size() < n) v.resize(n); }
template<typename T> void mvkCopy(T* d, const T* s, size_t n) { if (n) std::memcpy(d, s, n * sizeof(T)); }
template<typename T> void mvkClear(T* d, size_t n) { if (n) std::memset(d, 0, n * sizeof(T)); }
bool mvkIsAnyFlagEnabled(uint32_t a, uint32_t b) { return (a & b) != 0; }
VkShaderStageFlags mvkVkShaderStageFlagBitsFromMVKShaderStage(MVKShaderStage s) { return 1u << s; }
struct MVKDescriptorMetaBuffer { uint32_t size; };
struct MVKDescriptorMetaTexelBuffer { uint32_t size; };
struct MVKDescriptorMetaImage { uint32_t size, swizzle; };
struct MetaRecord { uint32_t unused = 0, size = 64, swizzle = 0x1234, padding = 0; };
size_t descriptorCPUSize(int) { return sizeof(MetaRecord); }
size_t getCPUMetaOffset(int) { return sizeof(uint32_t); }
struct ResourceCount { uint32_t buffer = 0, texture = 0, dynamicOffset = 0; };
struct Binding {
    VkDescriptorType descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
    uint32_t descriptorCount = 1;
    VkShaderStageFlags stageFlags = 0;
    ResourceCount perDescriptorResourceCount;
    int cpuLayout = 0;
    uint32_t cpuOffset = 0;
    bool variable = false;
    bool isVariable() const { return variable; }
};
struct MVKShaderStageResourceBinding {
    uint32_t bufferIndex = 0, textureIndex = 0, dynamicOffsetBufferIndex = 0;
};
struct ResourceCounts { std::array<MVKShaderStageResourceBinding, kMVKShaderStageCount> stages{}; };
struct MVKDescriptorSetLayout {
    std::vector<Binding> data;
    MVKArgumentBufferMode mode = MVKArgumentBufferMode::On;
    ResourceCounts total;
    const std::vector<Binding>& bindings() const { return data; }
    const ResourceCounts& totalResourceCount() const { return total; }
    MVKArgumentBufferMode argBufMode() const { return mode; }
    uint32_t dynamicOffsetCount(uint32_t variableCount) const {
        uint32_t n = 0;
        for (const auto& b: data) if (b.perDescriptorResourceCount.dynamicOffset)
            n += b.variable ? variableCount : b.descriptorCount;
        return n;
    }
    void finish() {
        total = {};
        for (auto& b: data) for (int s = 0; s < kMVKShaderStageCount; ++s) {
            if (!(b.stageFlags & (1u << s))) continue;
            total.stages[s].dynamicOffsetBufferIndex += b.perDescriptorResourceCount.dynamicOffset * b.descriptorCount;
            total.stages[s].bufferIndex += b.perDescriptorResourceCount.buffer * b.descriptorCount;
            total.stages[s].textureIndex += b.perDescriptorResourceCount.texture * b.descriptorCount;
        }
    }
};
struct MVKDescriptorSet {
    uint32_t variableDescriptorCount = 0;
    std::array<MetaRecord, 8> records{};
    void* cpuBuffer = records.data();
};
struct MVKPipelineLayout {
    struct Features { bool nativeTextureSwizzle = false; } features;
    std::vector<MVKDescriptorSetLayout*> sets;
    std::vector<ResourceCounts> offsets;
    ResourceCounts totals;
    uint32_t pushLength = 0;
    MVKPipelineLayout(std::initializer_list<MVKDescriptorSetLayout*> s): sets(s) {
        totals = {};
        for (auto* l: sets) {
            offsets.push_back(totals);
            for (int i = 0; i < kMVKShaderStageCount; ++i) {
                totals.stages[i].bufferIndex += l->total.stages[i].bufferIndex;
                totals.stages[i].textureIndex += l->total.stages[i].textureIndex;
                totals.stages[i].dynamicOffsetBufferIndex += l->total.stages[i].dynamicOffsetBufferIndex;
            }
        }
    }
    MVKDescriptorSetLayout* getDescriptorSetLayout(uint32_t n) const { return sets.at(n); }
    const ResourceCounts& getResourceBindingOffsets(uint32_t n) const { return offsets.at(n); }
    const Features& getMetalFeatures() const { return features; }
    uint32_t getPushConstantsLength() const { return pushLength; }
};
struct MVKGraphicsPipeline {
    MVKPipelineLayout* layout;
    MVKPipelineLayout* getLayout() const { return layout; }
};
struct MVKComputePipeline {
    MVKPipelineLayout* layout;
    MVKPipelineLayout* getLayout() const { return layout; }
};
struct MVKImplicitBufferData {
    MVKSmallVector<uint32_t, 8> textureSwizzles, bufferSizes, dynamicOffsets;
};
constexpr uint32_t kMVKMaxDescriptorSetCount = 8;
template<uint32_t N> struct MVKStaticBitSet {
    uint32_t mask = 0;
    static MVKStaticBitSet range(uint32_t first, uint32_t end) {
        MVKStaticBitSet v;
        for (auto i = first; i < end; ++i) v.mask |= 1u << i;
        return v;
    }
};
struct SetBits {
    uint32_t mask = 0xff, clearCalls = 0;
    template<typename T> void clearAllIn(T affected) { mask &= ~affected.mask; ++clearCalls; }
    void reset() { mask = 0; }
};
struct MVKStageResourceBits {
    SetBits descriptorSetData;
    MVKStageResourceBits* begin() { return this; }
    MVKStageResourceBits* end() { return this + 1; }
};
struct MVKVulkanCommonEncoderState {
    MVKPipelineLayout* _layout = nullptr;
    MVKDescriptorSet* _descriptorSets[kMVKMaxDescriptorSetCount]{};
    void setLayout(MVKPipelineLayout* l) { _layout = l; }
};
struct MVKVulkanGraphicsCommandEncoderState: MVKVulkanCommonEncoderState {
    MVKGraphicsPipeline* _pipeline = nullptr;
    MVKImplicitBufferData _implicitBufferData[kMVKShaderStageFragment + 1];
    bool bindDescriptorSets(MVKPipelineLayout*, uint32_t, uint32_t, MVKDescriptorSet*const*, uint32_t, const uint32_t*);
};
struct MVKVulkanComputeCommandEncoderState: MVKVulkanCommonEncoderState {
    MVKComputePipeline* _pipeline = nullptr;
    MVKImplicitBufferData _implicitBufferData;
    bool bindDescriptorSets(MVKPipelineLayout*, uint32_t, uint32_t, MVKDescriptorSet*const*, uint32_t, const uint32_t*);
};
struct MockMetalGraphics {
    uint32_t invalidations = 0;
    bool dirty = false;
    std::array<MVKStageResourceBits, 2> bits{};
    auto& exists() { return bits; }
    void changePipeline(MVKGraphicsPipeline*, MVKGraphicsPipeline*) {}
};
struct MockMetalCompute {
    uint32_t invalidations = 0;
    bool dirty = false;
    MVKShaderStage _vkStage = kMVKShaderStageCompute;
    MVKStageResourceBits _exists;
    auto& exists() { return _exists; }
    void transitionCompute();
    void transitionRender(MVKShaderStage);
};
template<typename T> void invalidateDescriptorSetImplicitBuffers(T& s) { ++s.invalidations; s.dirty = true; }
enum class CommandEncoderClass { None, Graphics, Compute };
bool isGraphicsStage(MVKShaderStage stage) { return stage < kMVKShaderStageCompute; }
struct MVKCommandEncoderState {
    MVKVulkanGraphicsCommandEncoderState _vkGraphics;
    MVKVulkanComputeCommandEncoderState _vkCompute;
    struct Shared { std::vector<uint8_t> _pushConstants; } _vkShared;
    MockMetalGraphics _mtlGraphics;
    MockMetalCompute _mtlCompute;
    CommandEncoderClass _mtlActiveEncoder = CommandEncoderClass::Compute;
    uint32_t metal4Invalidations = 0, pushInvalidations = 0;
    template<typename Fn> void applyToActiveMTLState(VkPipelineBindPoint, Fn&&);
    void invalidateMetal4ImplicitBuffer(VkPipelineBindPoint, MVKNonVolatileImplicitBuffer) { ++metal4Invalidations; }
    void bindGraphicsPipeline(MVKGraphicsPipeline*);
    void bindComputePipeline(MVKComputePipeline*);
    void bindDescriptorSets(VkPipelineBindPoint, MVKPipelineLayout*, uint32_t, uint32_t, MVKDescriptorSet*const*, uint32_t, const uint32_t*);
};
void invalidateImplicitBuffer(MVKCommandEncoderState& s, VkPipelineBindPoint, MVKNonVolatileImplicitBuffer) { ++s.pushInvalidations; }

#include "production.inc"

static uint32_t checks = 0, scenarios = 0;
static void expect(bool value, const char* description) {
    ++checks;
    if (!value) throw std::runtime_error(description);
}
static void equalData(const MVKImplicitBufferData& a, const MVKImplicitBufferData& b) {
    expect(a.dynamicOffsets == b.dynamicOffsets, "dynamic output parity");
    expect(a.bufferSizes == b.bufferSizes, "buffer metadata parity");
    expect(a.textureSwizzles == b.textureSwizzles, "swizzle metadata parity");
}
static MVKDescriptorSetLayout dynamicLayout(uint32_t count, uint32_t stages) {
    MVKDescriptorSetLayout l;
    Binding b;
    b.descriptorCount = count; b.stageFlags = stages; b.perDescriptorResourceCount.dynamicOffset = 1;
    l.data.push_back(b); l.finish();
    return l;
}
static void clean(MockMetalCompute& m) {
    m.invalidations = 0; m.dirty = false; m._exists.descriptorSetData.mask = 0xff;
    m._exists.descriptorSetData.clearCalls = 0;
}
static void clean(MockMetalGraphics& m) {
    m.invalidations = 0; m.dirty = false;
    for (auto& b: m.bits) { b.descriptorSetData.mask = 0xff; b.descriptorSetData.clearCalls = 0; }
}
static void foundationCount(uint32_t actual, uint32_t binds) {
    expect(actual == binds * (MVK_BUILD_METAL4_FOUNDATION ? 3u : 0u), "M4 separate invalidations preserved");
}

int main() {
    try {
        const auto both = (1u << kMVKShaderStageVertex) | (1u << kMVKShaderStageCompute);
        auto a = dynamicLayout(1, both), b = dynamicLayout(2, both), s = dynamicLayout(1, both);
        MVKPipelineLayout l1{&a, &s}, l2{&b, &s}, equivalent{&a, &s};
        MVKDescriptorSet sa, sb, ss;
        MVKDescriptorSet* sets1[] = {&sa, &ss};
        MVKDescriptorSet* sets2[] = {&sb, &ss};
        uint32_t zero[] = {0, 0, 0}, nonzero[] = {3, 5, 7};

        // Before/after bodies see exactly the same starting vectors and data.
        ++scenarios;
        for (int st = 0; st < kMVKShaderStageCount; ++st) for (uint32_t seed = 0; seed < 32; ++seed) {
            MVKImplicitBufferData post;
            if (seed & 1) post.dynamicOffsets.assign(8, seed % 3);
            auto old = post;
            uint32_t offsets[] = {seed % 5, seed % 7, seed % 11};
            auto* layout = (seed & 2) ? &l1 : &l2;
            auto** sets = (seed & 2) ? sets1 : sets2;
            uint32_t count = (seed & 2) ? 2 : 3;
            ::bindDescriptorSets(post, static_cast<MVKShaderStage>(st), layout, 0, 2, sets, count, offsets);
            reference_before::bindDescriptorSets(old, static_cast<MVKShaderStage>(st), layout, 0, 2, sets, count, offsets);
            equalData(post, old);
        }

        ++scenarios; // New meaningful zeros are dirty; repeats are clean.
        MVKImplicitBufferData data;
        expect(::bindDescriptorSets(data, kMVKShaderStageCompute, &l2, 0, 2, sets2, 3, zero), "zero growth must be dirty");
        expect(data.dynamicOffsets.size() == 3, "three words prepared");
        expect(!::bindDescriptorSets(data, kMVKShaderStageCompute, &l2, 0, 2, sets2, 3, zero), "same offsets clean");
        expect(::bindDescriptorSets(data, kMVKShaderStageCompute, &l2, 0, 2, sets2, 3, nonzero), "changed offsets dirty");

        ++scenarios; // Partial set bind retains prefix values, with actual old-body parity.
        auto old = data;
        uint32_t partial[] = {19};
        ::bindDescriptorSets(data, kMVKShaderStageCompute, &l2, 1, 1, &sets2[1], 1, partial);
        reference_before::bindDescriptorSets(old, kMVKShaderStageCompute, &l2, 1, 1, &sets2[1], 1, partial);
        equalData(data, old);
        expect(data.dynamicOffsets[0] == 3 && data.dynamicOffsets[1] == 5 && data.dynamicOffsets[2] == 19, "partial offsets remain packed");
        MVKImplicitBufferData skipped;
        expect(!::bindDescriptorSets(skipped, kMVKShaderStageFragment, &l2, 0, 2, sets2, 3, nonzero), "stage omission consumes without writing");
        expect(skipped.dynamicOffsets.empty(), "unused stage vector untouched");

        ++scenarios; // Actual metadata production function; even equal non-argument metadata stays dirty.
        MVKDescriptorSetLayout metadata;
        metadata.mode = MVKArgumentBufferMode::Off;
        Binding buf; buf.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        buf.stageFlags = both; buf.perDescriptorResourceCount.buffer = 1;
        Binding image; image.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
        image.stageFlags = both; image.perDescriptorResourceCount.texture = 1; image.cpuOffset = sizeof(MetaRecord);
        metadata.data = {buf, image}; metadata.finish();
        MVKPipelineLayout lm{&metadata}; MVKDescriptorSet sm; MVKDescriptorSet* metas[] = {&sm};
        MVKImplicitBufferData md, mr;
        expect(::bindDescriptorSets(md, kMVKShaderStageCompute, &lm, 0, 1, metas, 0, zero), "metadata conservative");
        reference_before::bindDescriptorSets(mr, kMVKShaderStageCompute, &lm, 0, 1, metas, 0, zero);
        equalData(md, mr);
        expect(md.bufferSizes.at(0) == 64 && md.textureSwizzles.at(0) == 0x1234, "actual metadata bytes");
        expect(::bindDescriptorSets(md, kMVKShaderStageCompute, &lm, 0, 1, metas, 0, zero), "equal metadata still dirty");

        ++scenarios; // Root same-layout repeated bind: dirty skip but residency clear stays.
        MVKCommandEncoderState state; MVKComputePipeline p1{&l1}, p2{&l2}, p1Other{&l1};
        state.bindComputePipeline(&p1);
        state.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &l1, 0, 2, sets1, 2, zero);
        clean(state._mtlCompute); state.metal4Invalidations = 0;
        state.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &l1, 0, 2, sets1, 2, zero);
        expect(state._mtlCompute.invalidations == 0 && !state._mtlCompute.dirty, "same pipeline/layout offsets skip dirty");
        expect(state._mtlCompute._exists.descriptorSetData.clearCalls == 1, "resource clear runs despite unchanged bytes");
        expect(state._mtlCompute._exists.descriptorSetData.mask == 0xfc, "affected mask only");
        foundationCount(state.metal4Invalidations, 1);
        state.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &l1, 0, 2, sets1, 2, nonzero);
        expect(state._mtlCompute.invalidations == 1, "changed values invalidate root");

        ++scenarios; // Layout growth then shrink: actual limit clamp is extracted too.
        clean(state._mtlCompute); state.bindComputePipeline(&p2);
        expect(state._mtlCompute.dirty, "pipeline/layout transition invalidates before bind");
        state.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &l2, 0, 2, sets2, 3, zero);
        expect(state._vkCompute._implicitBufferData.dynamicOffsets.size() == 3, "all-zero packing growth");
        clean(state._mtlCompute); state.bindComputePipeline(&p1);
        expect(state._mtlCompute.dirty, "shrink transition dirty even when old values are zero");
        state.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &l1, 0, 2, sets1, 2, zero);
        expect(getImplicitBindingData(state._vkCompute._implicitBufferData.dynamicOffsets, 2).size() == 2, "current layout clamps retained capacity");
        clean(state._mtlCompute); state.bindComputePipeline(&p1Other);
        expect(state._mtlCompute.invalidations == 1, "different pipeline same layout remains conservative");
        clean(state._mtlCompute); state.bindComputePipeline(&p1Other);
        expect(state._mtlCompute.invalidations == 0, "same pipeline call need not dirty");

        ++scenarios; // Distinct equivalent layout or unknown pipeline keeps old invalidation.
        clean(state._mtlCompute);
        state.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &equivalent, 0, 2, sets1, 2, zero);
        expect(state._mtlCompute.dirty, "different layout object conservatively dirty");
        clean(state._mtlCompute); state._vkCompute._pipeline = nullptr;
        state.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &l1, 0, 2, sets1, 2, zero);
        expect(state._mtlCompute.dirty, "unknown pipeline conservatively dirty");

        ++scenarios; // Graphics aggregation and no-dynamic argument-buffer fast path.
        MVKCommandEncoderState graphics; graphics._mtlActiveEncoder = CommandEncoderClass::Graphics;
        MVKGraphicsPipeline gp{&l1}; graphics.bindGraphicsPipeline(&gp);
        graphics.bindDescriptorSets(VK_PIPELINE_BIND_POINT_GRAPHICS, &l1, 0, 2, sets1, 2, zero);
        clean(graphics._mtlGraphics); graphics.metal4Invalidations = 0;
        graphics.bindDescriptorSets(VK_PIPELINE_BIND_POINT_GRAPHICS, &l1, 1, 1, &sets1[1], 1, zero);
        expect(graphics._mtlGraphics.invalidations == 0, "partial graphics unchanged skip");
        for (const auto& bits: graphics._mtlGraphics.bits)
            expect(bits.descriptorSetData.mask == 0xfd && bits.descriptorSetData.clearCalls == 1, "all graphics resource-use masks cleared");
        foundationCount(graphics.metal4Invalidations, 1);
        MVKDescriptorSetLayout empty; empty.finish(); MVKPipelineLayout le{&empty};
        MVKGraphicsPipeline ge{&le}; graphics.bindGraphicsPipeline(&ge); clean(graphics._mtlGraphics);
        MVKDescriptorSet* emptySets[] = {&sa};
        graphics.bindDescriptorSets(VK_PIPELINE_BIND_POINT_GRAPHICS, &le, 0, 1, emptySets, 0, zero);
        expect(graphics._mtlGraphics.invalidations == 0, "no-dynamic argument-buffer fast path retained");

        ++scenarios; // Production helper transition blocks plus production active-stage filter.
        MVKCommandEncoderState helper; helper._mtlCompute._vkStage = kMVKShaderStageVertex;
        helper.bindComputePipeline(&p1); // inactive compute bindpoint is filtered out
        expect(helper._mtlCompute.invalidations == 0, "inactive bindpoint filter");
        helper._mtlCompute.transitionCompute();
        expect(helper._mtlCompute.dirty && helper._mtlCompute._exists.descriptorSetData.mask == 0, "helper to compute resets implicit and resources");
        clean(helper._mtlCompute); helper._mtlCompute.transitionRender(kMVKShaderStageVertex);
        expect(helper._mtlCompute.dirty && helper._mtlCompute._exists.descriptorSetData.mask == 0, "compute to helper resets implicit and resources");
        clean(helper._mtlCompute);
        helper.bindGraphicsPipeline(&gp);
        expect(helper._mtlCompute.dirty, "graphics pipeline transition targets active helper");
        clean(helper._mtlCompute); helper._mtlActiveEncoder = CommandEncoderClass::None;
        helper.bindComputePipeline(&p2);
        expect(helper._mtlCompute.invalidations == 0, "no active Metal encoder is untouched");

        ++scenarios; // Model a new encoder's empty existence state, not actual GPU lifetime.
        MVKCommandEncoderState fresh; fresh.bindComputePipeline(&p1);
        fresh._mtlCompute._exists.descriptorSetData.reset();
        fresh.bindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE, &l1, 0, 2, sets1, 2, zero);
        expect(fresh._mtlCompute.dirty && fresh._vkCompute._implicitBufferData.dynamicOffsets.size() == 2,
               "fresh empty CPU/Metal surfaces require preparation");

        std::cout << "{\"status\":\"passed\",\"foundation\":" << MVK_BUILD_METAL4_FOUNDATION
                  << ",\"scenarios\":" << scenarios << ",\"checks\":" << checks
                  << ",\"productionBodiesExtracted\":true,\"actualGPU\":false}" << std::endl;
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "CPU contract failure: " << e.what() << std::endl;
        return 1;
    }
}
