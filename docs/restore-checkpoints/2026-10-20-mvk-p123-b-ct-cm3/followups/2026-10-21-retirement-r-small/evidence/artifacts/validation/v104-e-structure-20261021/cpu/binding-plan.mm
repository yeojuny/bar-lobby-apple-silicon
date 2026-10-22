
#include "MVKDescriptorSet.h"
struct MVKMetal4ResourceBindingPlan {
	const MVKDescriptorSetLayout* layout = nullptr;
	uint32_t descriptorCount = 0, cpuOffset = 0, cpuStride = 0, immSamplerIndex = 0;
	MVKDescriptorResourceCount perDescriptorResourceCount = {};
	MVKDescriptorCPULayout cpuLayout = MVKDescriptorCPULayout::None;
	bool variable = false, immutable = false;
	MVKMetal4ResourceBindingPlan() = default;
	MVKMetal4ResourceBindingPlan(const MVKDescriptorSetLayout* owner, const MVKDescriptorBinding& binding)
		: layout(owner), descriptorCount(binding.getDescriptorCount(binding.descriptorCount)),
		  cpuOffset(binding.cpuOffset), cpuStride(descriptorCPUSize(binding.cpuLayout)),
		  immSamplerIndex(binding.hasImmutableSamplers() ? binding.immSamplerIndex : 0),
		  perDescriptorResourceCount(binding.perDescriptorResourceCount), cpuLayout(binding.cpuLayout),
		  variable(binding.descriptorType != VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK && binding.isVariable()),
		  immutable(binding.hasImmutableSamplers()) {}
	uint32_t getDescriptorCount(uint32_t variableCount) const { return variable ? variableCount : descriptorCount; }
	bool hasImmutableSamplers() const { return immutable; }
};

struct MVKMetal4ResourceBinding {
	uint32_t set;
	uint32_t bindingIdx;
	MVKMetal4ResourceBindingPlan preparation;
};
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
