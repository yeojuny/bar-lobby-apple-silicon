
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>
static int checks = 0;
static void check(bool ok) { ++checks; if (!ok) { std::fprintf(stderr,"failed check %d\n",checks); std::abort(); } }

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
    bool metal4EarlyRecordEligible() const { return _metal4EarlyRecordEligible; }
};
struct Set { Layout* layout; };
struct Command {
    void* _pipelineLayout=nullptr; std::vector<Set*> _descriptorSets;
    MVKMetal4RecordPolicy before() const {
	if (!_pipelineLayout) { return MVKMetal4RecordPolicy::Deferred; }
	for (size_t i = 0; i < _descriptorSets.size(); ++i) {
		auto* set = _descriptorSets[i];
		if (!set || !set->layout) { return MVKMetal4RecordPolicy::Deferred; }
		for (const auto& binding : set->layout->bindings()) {
			// Optional/mutable bindings require a separate host-use contract.
			if (binding.flags & MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS) {
				return MVKMetal4RecordPolicy::Deferred;
			}
			switch (binding.descriptorType) {
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
				case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
				case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: break;
				default: return MVKMetal4RecordPolicy::Deferred;
			}
		}
	}
	return MVKMetal4RecordPolicy::State;
}
    MVKMetal4RecordPolicy after() const {
	if (!_pipelineLayout) { return MVKMetal4RecordPolicy::Deferred; }
	for (size_t i = 0; i < _descriptorSets.size(); ++i) {
		auto* set = _descriptorSets[i];
		if (!set || !set->layout) { return MVKMetal4RecordPolicy::Deferred; }
		if (!set->layout->metal4EarlyRecordEligible()) { return MVKMetal4RecordPolicy::Deferred; }
	}
	return MVKMetal4RecordPolicy::State;
}
};
static Layout create(std::vector<VkDescriptorSetLayoutBinding> bindings,
                     std::vector<VkDescriptorBindingFlags> flags, bool withFlags=true) {
    Layout result; result._bindings.resize(bindings.size());
    Layout* ret=&result;
    VkDescriptorSetLayoutCreateInfo info{}; info.pBindings=bindings.data(); info.bindingCount=bindings.size();
    auto* pCreateInfo=&info; auto* flagList=withFlags ? flags.data() : nullptr;
    uint32_t numBindings=bindings.size();
	for (uint32_t i = 0; i < numBindings; i++) {
		ret->_bindings[i].populate(pCreateInfo->pBindings[i]);
		if (flagList)
			ret->_bindings[i].flags |= flagList[i] & MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS;
#if MVK_BUILD_METAL4_FOUNDATION
		const auto& binding = ret->_bindings[i];
		if (binding.flags & MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS) {
			ret->_metal4EarlyRecordEligible = false;
		}
		switch (binding.descriptorType) {
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: break;
			default: ret->_metal4EarlyRecordEligible = false;
		}
#endif
	}

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
