/*
 * MVKCmdPipeline.mm
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "MVKCmdPipeline.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"
#include <limits>
#include <new>


#pragma mark -
#pragma mark MVKCmdExecuteCommands

template <size_t N>
VkResult MVKCmdExecuteCommands<N>::setContent(MVKCommandBuffer* cmdBuff,
											  uint32_t commandBuffersCount,
											  const VkCommandBuffer* pCommandBuffers) {
	// Add clear values
	_secondaryCommandBuffers.clear();	// Clear for reuse
	_secondaryCommandBuffers.reserve(commandBuffersCount);
	for (uint32_t cbIdx = 0; cbIdx < commandBuffersCount; cbIdx++) {
		_secondaryCommandBuffers.push_back(MVKCommandBuffer::getMVKCommandBuffer(pCommandBuffers[cbIdx]));
	}
	cmdBuff->recordExecuteCommands(_secondaryCommandBuffers.contents());

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdExecuteCommands<N>::encode(MVKCommandEncoder* cmdEncoder) {
    for (auto& cb : _secondaryCommandBuffers) { cmdEncoder->encodeSecondary(cb); }
}

template class MVKCmdExecuteCommands<1>;
template class MVKCmdExecuteCommands<16>;


#pragma mark -
#pragma mark MVKCmdPipelineBarrier

template <size_t N>
VkResult MVKCmdPipelineBarrier<N>::setContent(MVKCommandBuffer* cmdBuff,
											  const VkDependencyInfo* pDependencyInfo) {
	_dependencyFlags = pDependencyInfo->dependencyFlags;

	_barriers.clear();	// Clear for reuse
	_barriers.reserve(pDependencyInfo->memoryBarrierCount + 
					  pDependencyInfo->bufferMemoryBarrierCount +
					  pDependencyInfo->imageMemoryBarrierCount);

	for (uint32_t i = 0; i < pDependencyInfo->memoryBarrierCount; i++) {
		_barriers.emplace_back(pDependencyInfo->pMemoryBarriers[i]);
	}
	for (uint32_t i = 0; i < pDependencyInfo->bufferMemoryBarrierCount; i++) {
		_barriers.emplace_back(pDependencyInfo->pBufferMemoryBarriers[i]);
	}
	for (uint32_t i = 0; i < pDependencyInfo->imageMemoryBarrierCount; i++) {
		_barriers.emplace_back(pDependencyInfo->pImageMemoryBarriers[i]);
	}

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdPipelineBarrier<N>::setContent(MVKCommandBuffer* cmdBuff,
											  VkPipelineStageFlags srcStageMask,
											  VkPipelineStageFlags dstStageMask,
											  VkDependencyFlags dependencyFlags,
											  uint32_t memoryBarrierCount,
											  const VkMemoryBarrier* pMemoryBarriers,
											  uint32_t bufferMemoryBarrierCount,
											  const VkBufferMemoryBarrier* pBufferMemoryBarriers,
											  uint32_t imageMemoryBarrierCount,
											  const VkImageMemoryBarrier* pImageMemoryBarriers) {
	_dependencyFlags = dependencyFlags;

	_barriers.clear();	// Clear for reuse
	_barriers.reserve(memoryBarrierCount + bufferMemoryBarrierCount + imageMemoryBarrierCount);

	for (uint32_t i = 0; i < memoryBarrierCount; i++) {
		_barriers.emplace_back(pMemoryBarriers[i], srcStageMask, dstStageMask);
	}
	for (uint32_t i = 0; i < bufferMemoryBarrierCount; i++) {
		_barriers.emplace_back(pBufferMemoryBarriers[i], srcStageMask, dstStageMask);
	}
	for (uint32_t i = 0; i < imageMemoryBarrierCount; i++) {
		_barriers.emplace_back(pImageMemoryBarriers[i], srcStageMask, dstStageMask);
	}
	if (_barriers.empty()) {
		_barriers.emplace_back(srcStageMask, dstStageMask);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdPipelineBarrier<N>::encode(MVKCommandEncoder* cmdEncoder) {
	// Native barriers cannot be skipped by legacy argument-buffer/residency
	// policy. Resource layout/host-memory bookkeeping below still runs.
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) {
		for (auto& b : _barriers) {
			cmdEncoder->setMetal4Barrier(b.srcStageMask, b.dstStageMask,
				b.srcAccessMask || b.dstAccessMask || b.isImageBarrier(), b.isImageBarrier());
		}
	}
#endif
	
	auto& mtlFeats = cmdEncoder->getMetalFeatures();

#if MVK_MACOS
	// Calls below invoke MTLBlitCommandEncoder so must apply this first.
	// Check if pipeline barriers are available and we are in a renderpass.
	if (mtlFeats.memoryBarriers && cmdEncoder->_mtlRenderEncoder) {
		for (auto& b : _barriers) {
			MTLRenderStages srcStages = mvkMTLRenderStagesFromVkPipelineStageFlags(b.srcStageMask, false);
			MTLRenderStages dstStages = mvkMTLRenderStagesFromVkPipelineStageFlags(b.dstStageMask, true);
			switch (b.type) {
				case MVKPipelineBarrier::Memory: {
					MTLBarrierScope scope = (mvkMTLBarrierScopeFromVkAccessFlags(b.srcAccessMask) |
											 mvkMTLBarrierScopeFromVkAccessFlags(b.dstAccessMask));
					[cmdEncoder->_mtlRenderEncoder memoryBarrierWithScope: scope
															  afterStages: srcStages
															 beforeStages: dstStages];
					break;
				}

				case MVKPipelineBarrier::Buffer: {
					id<MTLResource> mtlRez = b.mvkBuffer->getMTLBuffer();
					[cmdEncoder->_mtlRenderEncoder memoryBarrierWithResources: &mtlRez
																		count: 1
																  afterStages: srcStages
																 beforeStages: dstStages];
					break;
				}
				case MVKPipelineBarrier::Image: {
					uint32_t plnCnt = b.mvkImage->getPlaneCount();
					id<MTLResource> mtlRezs[plnCnt];
					for (uint8_t plnIdx = 0; plnIdx < plnCnt; plnIdx++) {
						mtlRezs[plnIdx] = b.mvkImage->getMTLTexture(plnIdx);
					}
					[cmdEncoder->_mtlRenderEncoder memoryBarrierWithResources: mtlRezs
																		count: plnCnt
																  afterStages: srcStages
																 beforeStages: dstStages];
					break;
				}
				default:
					break;
			}
		}
	}
#endif

	if (!cmdEncoder->isUsingMetal4() && !cmdEncoder->_mtlRenderEncoder && cmdEncoder->isUsingMetalArgumentBuffers() && cmdEncoder->getDevice()->hasResidencySet()) {
		cmdEncoder->endCurrentMetalEncoding();

		for (auto& b : _barriers) {
			uint64_t sourceStageMask = mvkBarrierStagesFromPipelineStageFlags(b.srcStageMask), destStageMask = mvkBarrierStagesFromPipelineStageFlags(b.dstStageMask);
			cmdEncoder->setBarrier(sourceStageMask, destStageMask);
		}
	}

	// Apple GPUs do not support renderpass barriers, and do not support rendering/writing
	// to an attachment and then reading from that attachment within a single renderpass.
	// So, in the case where we are inside a Metal renderpass, we need to split those activities
	// into separate Metal renderpasses. Since this is a potentially expensive operation,
	// verify that at least one attachment is being used both as an input and render attachment
	// by checking for a VK_IMAGE_LAYOUT_GENERAL layout.
	// During subpass changes, or with dynamic rendering, if an input attachment is being used,
	// both VK_DEPENDENCY_BY_REGION_BIT and VK_ACCESS_INPUT_ATTACHMENT_READ_BIT will be set.
	if (cmdEncoder->_mtlRenderEncoder && mtlFeats.tileBasedDeferredRendering) {
		bool needsRenderpassRestart = false;
		for (auto& b : _barriers) {
			if (b.type == MVKPipelineBarrier::Image && b.newLayout == VK_IMAGE_LAYOUT_GENERAL) {
				needsRenderpassRestart = true;
				break;
			}
			if (mvkIsAnyFlagEnabled(_dependencyFlags, VK_DEPENDENCY_BY_REGION_BIT) &&
				mvkIsAnyFlagEnabled(b.dstAccessMask, VK_ACCESS_INPUT_ATTACHMENT_READ_BIT)) {

				needsRenderpassRestart = true;
				break;
			}
		}
		if (needsRenderpassRestart) {
			cmdEncoder->encodeStoreActions(true);
			cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
		}
	}

	MVKDevice* mvkDvc = cmdEncoder->getDevice();
	MVKCommandUse cmdUse = kMVKCommandUsePipelineBarrier;

	for (auto& b : _barriers) {
		switch (b.type) {
			case MVKPipelineBarrier::Memory:
				mvkDvc->applyMemoryBarrier(b, cmdEncoder, cmdUse);
				break;

			case MVKPipelineBarrier::Buffer:
				b.mvkBuffer->applyBufferMemoryBarrier(b, cmdEncoder, cmdUse);
				break;

			case MVKPipelineBarrier::Image:
				b.mvkImage->applyImageMemoryBarrier(b, cmdEncoder, cmdUse);
				break;

			default:
				break;
		}
	}
}

#if MVK_BUILD_METAL4_FOUNDATION
template <size_t N>
MVKMetal4RecordPolicy MVKCmdPipelineBarrier<N>::getMetal4RecordPolicy() const {
	for (const auto& b : _barriers) {
		// Host visibility and ownership transitions keep submission-time semantics.
		if (((b.srcStageMask | b.dstStageMask) & VK_PIPELINE_STAGE_2_HOST_BIT) ||
			((b.srcAccessMask | b.dstAccessMask) & (VK_ACCESS_2_HOST_READ_BIT | VK_ACCESS_2_HOST_WRITE_BIT)) ||
			b.srcQueueFamilyIndex != b.dstQueueFamilyIndex) { return MVKMetal4RecordPolicy::Deferred; }
		if (b.type == MVKPipelineBarrier::Image) {
			if (!b.mvkImage || !b.mvkImage->isMetal4PreparedRecordingSafe() ||
				b.newLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
				return MVKMetal4RecordPolicy::Deferred;
			}
		} else if (b.type == MVKPipelineBarrier::Buffer) {
			auto* memory = b.mvkBuffer ? b.mvkBuffer->getDeviceMemory() : nullptr;
			if (!memory || !memory->isMetal4KnownInternalAllocation()) { return MVKMetal4RecordPolicy::Deferred; }
		} else if (b.type != MVKPipelineBarrier::Memory && b.type != MVKPipelineBarrier::Execution) {
			return MVKMetal4RecordPolicy::Deferred;
		}
	}
	return MVKMetal4RecordPolicy::Immediate;
}
#endif

template <size_t N>
bool MVKCmdPipelineBarrier<N>::coversTextures() {
	for (auto& b : _barriers) {
		switch (b.type) {
			case MVKPipelineBarrier::Memory:	return true;
			case MVKPipelineBarrier::Image: 	return true;
			default: 							break;
		}
	}
	return false;
}

template class MVKCmdPipelineBarrier<1>;
template class MVKCmdPipelineBarrier<4>;
template class MVKCmdPipelineBarrier<32>;


#pragma mark -
#pragma mark MVKCmdBindPipeline

VkResult MVKCmdBindPipeline::setContent(MVKCommandBuffer* cmdBuff, VkPipeline pipeline) {
	_pipeline = (MVKPipeline*)pipeline;

	cmdBuff->recordBindPipeline(this);

	return VK_SUCCESS;
}


#pragma mark -
#pragma mark MVKCmdBindGraphicsPipeline

void MVKCmdBindGraphicsPipeline::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->bindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, _pipeline);
}

bool MVKCmdBindGraphicsPipeline::isTessellationPipeline() {
	return ((MVKGraphicsPipeline*)_pipeline)->isTessellationPipeline();
}

#if MVK_BUILD_METAL4_FOUNDATION
MVKMetal4RecordPolicy MVKCmdBindGraphicsPipeline::getMetal4RecordPolicy() const {
	auto* pipeline = static_cast<MVKGraphicsPipeline*>(_pipeline);
	return pipeline && !pipeline->isTessellationPipeline()
		? MVKMetal4RecordPolicy::State : MVKMetal4RecordPolicy::Deferred;
}
#endif


#pragma mark -
#pragma mark MVKCmdBindComputePipeline

void MVKCmdBindComputePipeline::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->bindPipeline(VK_PIPELINE_BIND_POINT_COMPUTE, _pipeline);
}


#pragma mark -
#pragma mark MVKCmdBindDescriptorSetsStatic

template <size_t N>
VkResult MVKCmdBindDescriptorSetsStatic<N>::setContent(MVKCommandBuffer* cmdBuff,
													   VkPipelineBindPoint pipelineBindPoint,
													   VkPipelineLayout layout,
													   uint32_t firstSet,
													   uint32_t setCount,
													   const VkDescriptorSet* pDescriptorSets) {
	if (_pipelineLayout) { _pipelineLayout->release(); }

	_pipelineBindPoint = pipelineBindPoint;
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_firstSet = firstSet;

	_pipelineLayout->retain();

	// Add the descriptor sets
	_descriptorSets.clear();	// Clear for reuse
	_descriptorSets.reserve(setCount);
	for (uint32_t dsIdx = 0; dsIdx < setCount; dsIdx++) {
		_descriptorSets.push_back((MVKDescriptorSet*)pDescriptorSets[dsIdx]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdBindDescriptorSetsStatic<N>::encode(MVKCommandEncoder* cmdEncoder) {
	encode(cmdEncoder, MVKArrayRef<uint32_t>());
}

template <size_t N>
void MVKCmdBindDescriptorSetsStatic<N>::encode(MVKCommandEncoder* cmdEncoder, MVKArrayRef<uint32_t> dynamicOffsets) {
#if MVK_BUILD_METAL4_FOUNDATION
	// The pooled node may be reused immediately after early encoding. Preserve
	// its layout independently while the encoder carries Vulkan state to suffix.
	if (cmdEncoder->isUsingMetal4()) { cmdEncoder->retainMetal4VulkanState(_pipelineLayout); }
#endif
	cmdEncoder->getState().bindDescriptorSets(_pipelineBindPoint, _pipelineLayout, _firstSet, static_cast<uint32_t>(_descriptorSets.size()), _descriptorSets.data(), static_cast<uint32_t>(dynamicOffsets.size()), dynamicOffsets.data());
}

#if MVK_BUILD_METAL4_FOUNDATION
template <size_t N>
MVKMetal4RecordPolicy MVKCmdBindDescriptorSetsStatic<N>::getMetal4RecordPolicy() const {
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
#endif

template <size_t N>
MVKCmdBindDescriptorSetsStatic<N>::~MVKCmdBindDescriptorSetsStatic() {
	if (_pipelineLayout) { _pipelineLayout->release(); }
}

template class MVKCmdBindDescriptorSetsStatic<1>;
template class MVKCmdBindDescriptorSetsStatic<4>;
template class MVKCmdBindDescriptorSetsStatic<8>;


#pragma mark -
#pragma mark MVKCmdBindDescriptorSetsDynamic

template <size_t N>
VkResult MVKCmdBindDescriptorSetsDynamic<N>::setContent(MVKCommandBuffer* cmdBuff,
														VkPipelineBindPoint pipelineBindPoint,
														VkPipelineLayout layout,
														uint32_t firstSet,
														uint32_t setCount,
														const VkDescriptorSet* pDescriptorSets,
														uint32_t dynamicOffsetCount,
														const uint32_t* pDynamicOffsets) {

	MVKCmdBindDescriptorSetsStatic<N>::setContent(cmdBuff, pipelineBindPoint, layout,
												  firstSet, setCount, pDescriptorSets);

	// Add the dynamic offsets
	_dynamicOffsets.clear();	// Clear for reuse
	_dynamicOffsets.reserve(dynamicOffsetCount);
	for (uint32_t doIdx = 0; doIdx < dynamicOffsetCount; doIdx++) {
		_dynamicOffsets.push_back(pDynamicOffsets[doIdx]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdBindDescriptorSetsDynamic<N>::encode(MVKCommandEncoder* cmdEncoder) {
	MVKCmdBindDescriptorSetsStatic<N>::encode(cmdEncoder, _dynamicOffsets.contents());
}

template class MVKCmdBindDescriptorSetsDynamic<4>;
template class MVKCmdBindDescriptorSetsDynamic<8>;


#pragma mark -
#pragma mark MVKCmdPushConstants

template <size_t N>
VkResult MVKCmdPushConstants<N>::setContent(MVKCommandBuffer* cmdBuff,
											VkPipelineLayout layout,
											VkShaderStageFlags stageFlags,
											uint32_t offset,
											uint32_t size,
											const void* pValues) {
	_stageFlags = stageFlags;
	_offset = offset;

	_pushConstants.resize(size);
	std::copy_n((char*)pValues, size, _pushConstants.begin());

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdPushConstants<N>::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().pushConstants(_offset, static_cast<uint32_t>(_pushConstants.byteSize()), _pushConstants.data());
}

template class MVKCmdPushConstants<64>;
template class MVKCmdPushConstants<128>;
template class MVKCmdPushConstants<512>;


#pragma mark -
#pragma mark MVKCmdPushDescriptorSet

VkResult MVKCmdPushDescriptorSet::setContent(MVKCommandBuffer* cmdBuff,
											 VkPipelineBindPoint pipelineBindPoint,
											 VkPipelineLayout layout,
											 uint32_t set,
											 uint32_t descriptorWriteCount,
											 const VkWriteDescriptorSet* pDescriptorWrites) {
	if (_pipelineLayout) { _pipelineLayout->release(); }

	_pipelineBindPoint = pipelineBindPoint;
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_set = set;

	_pipelineLayout->retain();

	// Add the descriptor writes
	clearDescriptorWrites();	// Clear for reuse
	_descriptorWrites.reserve(descriptorWriteCount);
	for (uint32_t dwIdx = 0; dwIdx < descriptorWriteCount; dwIdx++) {
		_descriptorWrites.push_back(pDescriptorWrites[dwIdx]);
		VkWriteDescriptorSet& descWrite = _descriptorWrites.back();
		// Make a copy of the associated data.
		if (descWrite.pImageInfo) {
			auto* pNewImageInfo = new VkDescriptorImageInfo[descWrite.descriptorCount];
			std::copy_n(descWrite.pImageInfo, descWrite.descriptorCount, pNewImageInfo);
			descWrite.pImageInfo = pNewImageInfo;
		}
		if (descWrite.pBufferInfo) {
			auto* pNewBufferInfo = new VkDescriptorBufferInfo[descWrite.descriptorCount];
			std::copy_n(descWrite.pBufferInfo, descWrite.descriptorCount, pNewBufferInfo);
			descWrite.pBufferInfo = pNewBufferInfo;
		}
		if (descWrite.pTexelBufferView) {
			auto* pNewTexelBufferView = new VkBufferView[descWrite.descriptorCount];
			std::copy_n(descWrite.pTexelBufferView, descWrite.descriptorCount, pNewTexelBufferView);
			descWrite.pTexelBufferView = pNewTexelBufferView;
		}
		const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)descWrite.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
			}
		}
		if (pInlineUniformBlock) {
			auto *pNewInlineUniformBlock = new VkWriteDescriptorSetInlineUniformBlock(*pInlineUniformBlock);
			pNewInlineUniformBlock->pNext = nullptr; // clear pNext just in case, no other extensions are supported at this time
			descWrite.pNext = pNewInlineUniformBlock;
		}
	}

	return VK_SUCCESS;
}

void MVKCmdPushDescriptorSet::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().pushDescriptorSet(_pipelineBindPoint, _pipelineLayout, _set, static_cast<uint32_t>(_descriptorWrites.size()), _descriptorWrites.data());
}

MVKCmdPushDescriptorSet::~MVKCmdPushDescriptorSet() {
	clearDescriptorWrites();
	if (_pipelineLayout) { _pipelineLayout->release(); }
}

void MVKCmdPushDescriptorSet::clearDescriptorWrites() {
	for (VkWriteDescriptorSet &descWrite : _descriptorWrites) {
		if (descWrite.pImageInfo) { delete[] descWrite.pImageInfo; }
		if (descWrite.pBufferInfo) { delete[] descWrite.pBufferInfo; }
		if (descWrite.pTexelBufferView) { delete[] descWrite.pTexelBufferView; }

		const VkWriteDescriptorSetInlineUniformBlock* pInlineUniformBlock = nullptr;
		for (const auto* next = (VkBaseInStructure*)descWrite.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK: {
					pInlineUniformBlock = (VkWriteDescriptorSetInlineUniformBlock*)next;
					break;
				}
				default:
					break;
			}
		}
		if (pInlineUniformBlock) { delete pInlineUniformBlock; }
	}
	_descriptorWrites.clear();
}


#pragma mark -
#pragma mark MVKCmdPushDescriptorSetWithTemplate

#if MVK_BUILD_METAL4_FOUNDATION
VkResult MVKCmdPushDescriptorSetWithTemplate::captureMetal4Uniforms(const void* pData) {
	const size_t count = _descUpdateTemplate->getNumberOfEntries();
	const auto bindPoint = _descUpdateTemplate->getBindPoint();
	if (!pData || !count ||
		_descUpdateTemplate->getType() != VK_DESCRIPTOR_UPDATE_TEMPLATE_TYPE_PUSH_DESCRIPTORS_KHR ||
		(bindPoint != VK_PIPELINE_BIND_POINT_GRAPHICS && bindPoint != VK_PIPELINE_BIND_POINT_COMPUTE) ||
		!_pipelineLayout->hasPushDescriptor() || _pipelineLayout->pushDescriptor() != _set) {
		return VK_SUCCESS;
	}
	auto* layout = _pipelineLayout->getDescriptorSetLayout(_set);
	// Preflight the complete template before reading any caller data. Mixed
	// templates (including fbfetch) and array/spill updates keep the old path.
	for (uint32_t i = 0; i < count; ++i) {
		const auto& entry = *_descUpdateTemplate->getEntry(i);
		if (entry.descriptorType != VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER || entry.descriptorCount != 1) {
			return VK_SUCCESS;
		}
		const auto& binding = *layout->getBinding(entry.dstBinding);
		if (binding.descriptorType != VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER ||
			entry.dstArrayElement >= binding.descriptorCount) { return VK_SUCCESS; }
	}
	constexpr size_t infoSize = sizeof(VkDescriptorBufferInfo);
	constexpr size_t writeSize = sizeof(VkWriteDescriptorSet);
	static_assert(infoSize % alignof(VkWriteDescriptorSet) == 0, "aligned compact write array");
	if (count > std::numeric_limits<size_t>::max() / (infoSize + writeSize)) {
		return VK_ERROR_OUT_OF_HOST_MEMORY;
	}
	const auto source = reinterpret_cast<uintptr_t>(pData);
	for (uint32_t i = 0; i < count; ++i) {
		const auto offset = _descUpdateTemplate->getEntry(i)->offset;
		if (offset > std::numeric_limits<size_t>::max() - infoSize ||
			source > std::numeric_limits<uintptr_t>::max() - (offset + infoSize)) {
			return VK_ERROR_OUT_OF_HOST_MEMORY;
		}
	}
	const size_t bytes = size_t(count) * (infoSize + writeSize);
	if (!_pData || bytes > _dataCapacity) {
		void* storage = malloc(bytes);
		if (!storage) { return VK_ERROR_OUT_OF_HOST_MEMORY; }
		free(_pData);
		_pData = storage;
		_dataCapacity = bytes;
	}
	_dataSize = bytes;
	auto* infos = static_cast<VkDescriptorBufferInfo*>(_pData);
	auto* writes = reinterpret_cast<VkWriteDescriptorSet*>(infos + count);
	for (uint32_t i = 0; i < count; ++i) {
		const auto& entry = *_descUpdateTemplate->getEntry(i);
		new (infos + i) VkDescriptorBufferInfo{};
		// Stride is irrelevant for a singleton. Read no prefix, gap, or padding,
		// and do not require an aligned typed pointer into caller storage.
		memcpy(infos + i, static_cast<const char*>(pData) + entry.offset, infoSize);
		new (writes + i) VkWriteDescriptorSet{};
		writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
		writes[i].dstBinding = entry.dstBinding;
		writes[i].dstArrayElement = entry.dstArrayElement;
		writes[i].descriptorCount = 1;
		writes[i].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
		writes[i].pBufferInfo = infos + i;
	}
	_compactUniformBindPoint = bindPoint;
	_compactUniformWriteCount = count;
	// Replay owns all interpretation metadata and still resolves native buffers
	// at the original encode point. No query or record-policy state changes.
	_descUpdateTemplate = nullptr;
	return VK_SUCCESS;
}
#endif

VkResult MVKCmdPushDescriptorSetWithTemplate::setContent(MVKCommandBuffer* cmdBuff,
														 VkDescriptorUpdateTemplate descUpdateTemplate,
														 VkPipelineLayout layout,
														 uint32_t set,
														 const void* pData) {
	if (_pipelineLayout) { _pipelineLayout->release(); }
	_pipelineLayout = (MVKPipelineLayout*)layout;
	_pipelineLayout->retain();
	_set = set;
	_descUpdateTemplate = (MVKDescriptorUpdateTemplate*)descUpdateTemplate;

#if MVK_BUILD_METAL4_FOUNDATION
	_compactUniformWriteCount = 0;
	_compactUniformBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
	if (mvkUseMetal4()) {
		VkResult result = captureMetal4Uniforms(pData);
		if (result != VK_SUCCESS) { return result; }
		if (_compactUniformWriteCount) { return VK_SUCCESS; }
	}
#endif

	const size_t bytes = _descUpdateTemplate->getSize();
	if (bytes > _dataCapacity) {
		void* storage = malloc(bytes);
		if (!storage) { return VK_ERROR_OUT_OF_HOST_MEMORY; }
		free(_pData);
		_pData = storage;
		_dataCapacity = bytes;
	}
	_dataSize = bytes;
	if (_pData && pData) {
		mvkCopy(_pData, pData, _dataSize);
	}

	return VK_SUCCESS;
}

void MVKCmdPushDescriptorSetWithTemplate::encode(MVKCommandEncoder* cmdEncoder) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (_compactUniformWriteCount) {
		auto* infos = static_cast<VkDescriptorBufferInfo*>(_pData);
		auto* writes = reinterpret_cast<VkWriteDescriptorSet*>(infos + _compactUniformWriteCount);
		cmdEncoder->getState().pushDescriptorSet(_compactUniformBindPoint, _pipelineLayout, _set,
			_compactUniformWriteCount, writes);
		return;
	}
#endif
	cmdEncoder->getState().pushDescriptorSet(_descUpdateTemplate, _pipelineLayout, _set, _pData);
}

MVKCmdPushDescriptorSetWithTemplate::~MVKCmdPushDescriptorSetWithTemplate() {
	if (_pipelineLayout) { _pipelineLayout->release(); }
	free(_pData);
}


#pragma mark -
#pragma mark MVKCmdSetEvent

VkResult MVKCmdSetEvent::setContent(MVKCommandBuffer* cmdBuff,
									VkEvent event,
									VkPipelineStageFlags stageMask) {
	_mvkEvent = (MVKEvent*)event;

	return VK_SUCCESS;
}

VkResult MVKCmdSetEvent::setContent(MVKCommandBuffer* cmdBuff,
									VkEvent event,
									const VkDependencyInfo* pDependencyInfo) {
	_mvkEvent = (MVKEvent*)event;

	return VK_SUCCESS;
}

void MVKCmdSetEvent::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->signalEvent(_mvkEvent, true);
}


#pragma mark -
#pragma mark MVKCmdResetEvent

VkResult MVKCmdResetEvent::setContent(MVKCommandBuffer* cmdBuff,
									  VkEvent event,
									  VkPipelineStageFlags2 stageMask) {
	_mvkEvent = (MVKEvent*)event;

	return VK_SUCCESS;
}

void MVKCmdResetEvent::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->signalEvent(_mvkEvent, false);
}


#pragma mark -
#pragma mark MVKCmdWaitEvents

template <size_t N>
VkResult MVKCmdWaitEvents<N>::setContent(MVKCommandBuffer* cmdBuff,
										 uint32_t eventCount,
										 const VkEvent* pEvents,
										 const VkDependencyInfo* pDependencyInfos) {
	_mvkEvents.clear();	// Clear for reuse
	_mvkEvents.reserve(eventCount);
	for (uint32_t i = 0; i < eventCount; i++) {
		_mvkEvents.push_back((MVKEvent*)pEvents[i]);
	}

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdWaitEvents<N>::setContent(MVKCommandBuffer* cmdBuff,
										 uint32_t eventCount,
										 const VkEvent* pEvents,
										 VkPipelineStageFlags srcStageMask,
										 VkPipelineStageFlags dstStageMask,
										 uint32_t memoryBarrierCount,
										 const VkMemoryBarrier* pMemoryBarriers,
										 uint32_t bufferMemoryBarrierCount,
										 const VkBufferMemoryBarrier* pBufferMemoryBarriers,
										 uint32_t imageMemoryBarrierCount,
										 const VkImageMemoryBarrier* pImageMemoryBarriers) {
	_mvkEvents.clear();	// Clear for reuse
	_mvkEvents.reserve(eventCount);
	for (uint32_t i = 0; i < eventCount; i++) {
		_mvkEvents.push_back((MVKEvent*)pEvents[i]);
	}

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdWaitEvents<N>::encode(MVKCommandEncoder* cmdEncoder) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) { cmdEncoder->failMetal4Encoding("Native Vulkan event wait encoding pending"); return; }
#endif
	cmdEncoder->endCurrentMetalEncoding();
	for (MVKEvent* mvkEvt : _mvkEvents) {
		mvkEvt->encodeWait(cmdEncoder->_mtlCmdBuffer);
	}
}

template class MVKCmdWaitEvents<1>;
template class MVKCmdWaitEvents<8>;

#if MVK_BUILD_METAL4_FOUNDATION
bool MVKCmdBindGraphicsPipeline::planMetal4Draws(MVKMetal4DrawPlanState& state) const {
    state.pipeline = static_cast<MVKGraphicsPipeline*>(_pipeline);
    return state.pipeline != nullptr;
}
#endif
