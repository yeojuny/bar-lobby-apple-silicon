/*
 * MVKCommandEncoderState.mm
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

#include "MVKCommandEncoderState.h"
#include "MVKCommandEncodingPool.h"
#include "MVKCommandBuffer.h"
#include "MVKImage.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"
#include "mvk_datatypes.hpp"
#if MVK_BUILD_METAL4_FOUNDATION
#include "MVKMetal4ArgumentTable.h"
#include "MVKMetal4Submission.h"
#include <limits>
#endif

using namespace std;

#if MVK_BUILD_METAL4_FOUNDATION && MVK_USE_METAL_PRIVATE_API
// This is the native protocol itself, never a legacy render-encoder adapter.
@protocol MVKMTL4WideLineEncoder <MTL4RenderCommandEncoder>
- (void)setLineWidth:(float)width;
@end
#endif

#if MVK_BUILD_METAL4_FOUNDATION
namespace {
using Metal4Stage = MVKMetal4ArgumentTables::Stage;

static bool metal4Failure(MVKCommandEncoder& encoder, const char* message) {
	encoder.failMetal4Encoding(message);
	return false;
}

// This sink owns no GPU storage and never impersonates a legacy Metal encoder.
// Submission retention occurs before releasing any live-resource lookup lock.
struct Metal4BindingSink {
	MVKCommandEncoder& encoder;
	Metal4Stage stage;
	bool check(bool result, NSError* error) {
		return result || metal4Failure(encoder, error ? error.localizedDescription.UTF8String : "Native Metal 4 binding failed.");
	}
	bool resource(id<MTLTexture> value) {
		return encoder.getState().registerMetal4Texture(encoder, value);
	}
	bool object(id value) {
		return encoder.getState().retainMetal4Object(encoder, value);
	}
	bool bufferResource(id<MTLBuffer> value) {
		return encoder.getState().registerMetal4Buffer(encoder, value);
	}
	bool buffer(id<MTLBuffer> value, uint64_t offset, uint32_t index) {
		if (!bufferResource(value)) { return false; }
		NSError* error = nil;
		bool ok = encoder.getMetal4ArgumentTables()->setBuffer(stage, value, value ? offset : 0, index, &error);
		return check(ok, error);
	}
	bool texture(id<MTLTexture> value, uint32_t index) {
		if (!resource(value)) { return false; }
		NSError* error = nil;
		bool ok = encoder.getMetal4ArgumentTables()->setTexture(stage, value, index, &error);
		return check(ok, error);
	}
	bool sampler(id<MTLSamplerState> value, uint32_t index) {
		if (!object(value)) { return false; }
		NSError* error = nil;
		bool ok = encoder.getMetal4ArgumentTables()->setSampler(stage, value, index, &error);
		return check(ok, error);
	}
	bool bytes(const void* data, size_t size, uint32_t index) {
		NSError* error = nil;
		bool ok = encoder.getMetal4ArgumentTables()->setBytes(stage, data, size, index, *encoder.getMetal4Submission(), &error);
		return check(ok, error);
	}
};

static MVKMetal4PreparedBindingSnapshots::Result replayMetal4Resource(
        Metal4BindingSink& sink, const MVKMetal4PreparedBindingSnapshots::Resource& resource) {
	using Snapshots = MVKMetal4PreparedBindingSnapshots;
	auto& liveResources = sink.encoder.getDevice()->getLiveResources();
	id value = (id)resource.identity;
	// Keep the same live guard through identity validation and submission retain.
	// Comparing weak owners under that guard also rejects native-address reuse.
	if (resource.kind == Snapshots::Kind::Buffer) {
		auto live = liveResources.buffers.isLive(value);
		if (!live || !resource.proof.matches(liveResources.buffers.membershipProof(value, live))) { return Snapshots::Result::Miss; }
		return sink.bufferResource(value) ? Snapshots::Result::Hit : Snapshots::Result::Failed;
	}
	if (resource.kind == Snapshots::Kind::Texture) {
		auto live = liveResources.textures.isLive(value);
		if (!live || !resource.proof.matches(liveResources.textures.preparationProof(value, live))) { return Snapshots::Result::Miss; }
		return sink.resource(value) ? Snapshots::Result::Hit : Snapshots::Result::Failed;
	}
	auto live = liveResources.samplers.isLive(value);
	if (!live || !resource.proof.matches(liveResources.samplers.preparationProof(value, live))) { return Snapshots::Result::Miss; }
	return sink.object(value) ? Snapshots::Result::Hit : Snapshots::Result::Failed;
}

static bool bindMetal4Resources(Metal4BindingSink& sink,
                               const MVKVulkanCommonEncoderState& common,
                               const MVKPipelineStageResourceInfo& resources,
                               const MVKImplicitBufferData& implicit,
                               const MVKVulkanSharedCommandEncoderState& shared,
                               MVKShaderStage vkStage) {
	if (!common._layout) { return metal4Failure(sink.encoder, "Native binding requires a pipeline layout."); }
    if (resources.usesPhysicalStorageBufferAddresses) {
		return metal4Failure(sink.encoder, "Native Metal 4 physical-storage-buffer residency is not integrated.");
	}
	auto* stats = sink.encoder.getMetal4EncodingStats();
	auto* tables = sink.encoder.getMetal4ArgumentTables();
	auto& prepared = sink.encoder.getState().metal4StagePreparation(vkStage);
	// A root can skip preparation only after registration in this recording and
	// while its exact table slot is unchanged. Slot revisions preserve #2822 when
	// helpers or another binding overwrite a root, including identical addresses
	// installed with a different stride mode.
	for (size_t idx : resources.resources.descriptorSetData) {
		if (idx >= common._layout->getDescriptorSetCount() || idx >= kMVKMaxDescriptorSetCount || !common._descriptorSets[idx]) {
			return metal4Failure(sink.encoder, "Missing native argument-buffer descriptor set.");
		}
		auto* set = common._descriptorSets[idx];
		auto& root = prepared.roots[idx];
		uint32_t index = static_cast<uint32_t>(idx);
		if (root.buffer == set->gpuBufferObject && root.offset == set->gpuBufferOffset &&
		    root.matches(tables, index, tables->bufferBindingRevision(sink.stage, index))) { continue; }
		if (!sink.buffer(set->gpuBufferObject, set->gpuBufferOffset, index)) { return false; }
		root.buffer = set->gpuBufferObject; root.offset = set->gpuBufferOffset;
		root.remember(tables, index, tables->bufferBindingRevision(sink.stage, index));
	}
	if (!resources.bindScript.metal4ResourceBindings.empty()) {
		auto& liveResources = sink.encoder.getDevice()->getLiveResources();
		bool snapshotSetsEligible = true;
		auto groupStamp = [&] {
			MVKMetal4PreparedGroupStamp result;
			result.script = resources.bindScript.metal4PreparationIdentity;
			result.stage = static_cast<uint32_t>(vkStage);
			result.setMask = resources.bindScript.metal4PreparationSetMask;
			for (uint32_t idx = 0; idx < MVKMetal4PreparedGroupStamp::kMaxSets; ++idx) {
				if (!(result.setMask & (1u << idx))) { continue; }
				if (idx >= common._layout->getDescriptorSetCount() || idx >= kMVKMaxDescriptorSetCount ||
				    !resources.resources.descriptorSetData.get(idx) || !common._descriptorSets[idx]) { result.script = 0; break; }
				auto* set = common._descriptorSets[idx];
				if (set->layout != common._layout->getDescriptorSetLayout(idx)) { result.script = 0; break; }
				if (!set->metal4Preparation.snapshots) { snapshotSetsEligible = false; }
				result.sets[idx] = {set->metal4Preparation.incarnation, set->metal4Preparation.revision};
			}
			result.epochs = {liveResources.buffers.generation(), liveResources.textures.generation(),
			                 liveResources.samplers.generation(), MVKMetal4PreparationEpoch::current(),
			                 MVKMetal4Submission::drawableRegistryEpoch()};
			return result;
		};
		auto before = groupStamp();
		auto bindingRevisionAt = [&](uint32_t setIndex, uint32_t binding) -> uint64_t {
			if (setIndex >= common._layout->getDescriptorSetCount() || setIndex >= kMVKMaxDescriptorSetCount ||
			    !common._descriptorSets[setIndex]) { return 0; }
			auto* set = common._descriptorSets[setIndex];
			return set->layout == common._layout->getDescriptorSetLayout(setIndex) ?
			    set->metal4Preparation.bindingRevision(binding) : 0;
		};
		auto& groupPreparation = sink.encoder.getMetal4Submission()->preparedGroupCache();
		auto lookup = groupPreparation.lookup(before, bindingRevisionAt, groupStamp);
		bool groupHit = lookup.complete;
		using Group = MVKMetal4PreparedGroupSnapshot;
		auto retained = std::move(lookup.partial);
		if (stats && before.setMask) {
			++stats->indirectGroupChecks;
			if (groupHit) { ++stats->indirectGroupHits; }
			else { ++stats->indirectGroupPreparations; }
		}
		using Snapshots = MVKMetal4PreparedBindingSnapshots;
		auto* groupSnapshot = resources.bindScript.metal4GroupSnapshot.get();
		bool captureGroup = false;
		std::vector<Snapshots::Resource> groupResources;
		std::vector<Group::BindingVersion> coveredBindings;
		std::vector<uint32_t> residualBindings;
		const auto& resourceBindings = resources.bindScript.metal4ResourceBindings;
		if (!groupHit && !retained && groupSnapshot && snapshotSetsEligible) {
			auto result = groupSnapshot->replay(before, bindingRevisionAt, [&](const Snapshots::Resource& resource) {
				return replayMetal4Resource(sink, resource);
			}, captureGroup, &retained);
			if (result == Snapshots::Result::Failed) { return false; }
			if (result == Snapshots::Result::Hit && retained->residual.empty()) {
				groupPreparation.remember(before, groupStamp(), std::move(retained));
				groupHit = true;
			}
		}
		// The bound is checked before admission, not on every binding during a hit.
		captureGroup = captureGroup && resourceBindings.size() <= Group::kMaxBindings;
		// A group hit skips even the immutable binding-list walk. It is valid only
		// after retention in this recording: unchanged epochs, the same resource
		// proofs across a stable epoch change, or fresh snapshot validation/retention.
		// Roots above independently check their actual slots, while direct
		// and dynamic bindings below retain their original preparation semantics.
		if (!groupHit) {
			// Discover shader-used indirect payloads once, regardless of root count.
			// Mutable/unproved resources keep their original live guards. Unchanged,
			// recording-retained bindings can reuse their exact allocation/view proofs.
			auto prepareBinding = [&](size_t ordinal) {
				const auto& used = resourceBindings[ordinal];
				const size_t groupStart = groupResources.size();
				bool captureBinding = captureGroup;
				uint64_t capturedRevision = 0;
				auto appendGroupBinding = [&](const MVKMetal4DescriptorPreparationStamp& stamp, uint32_t binding, uint64_t revision) {
					if (captureBinding && (!stamp.snapshots || !stamp.snapshots->append(binding, revision,
						groupResources, Group::kMaxResources))) { captureBinding = false; }
				};
				auto prepareCurrentPayload = [&]() -> bool {
					if (used.set >= common._layout->getDescriptorSetCount() || used.set >= kMVKMaxDescriptorSetCount ||
					    !resources.resources.descriptorSetData.get(used.set) || !common._descriptorSets[used.set]) {
						return metal4Failure(sink.encoder, "Native indirect binding has no argument-buffer root.");
					}
					auto* set = common._descriptorSets[used.set];
					auto* layout = common._layout->getDescriptorSetLayout(used.set);
					if (used.bindingIdx >= layout->bindings().size()) { return metal4Failure(sink.encoder, "Native indirect binding is outside its layout."); }
					const auto& binding = layout->bindings()[used.bindingIdx];
					uint32_t count = binding.getDescriptorCount(set->variableDescriptorCount);
					const auto& counts = binding.perDescriptorResourceCount;
					if (stats && count && (counts.texture || counts.sampler)) { ++stats->textureBindingVisits; }
					auto& preparation = sink.encoder.getState().metal4DescriptorPreparationCache();
					uint64_t bindingRevision = set->metal4Preparation.bindingRevision(used.bindingIdx);
					capturedRevision = bindingRevision;
					// Layout identity is only an eligibility check; cache identity is a fresh
					// pool incarnation + binding + revision, never a descriptor-set pointer.
					bool cacheEligible = set->layout == layout && set->metal4Preparation.incarnation &&
					                     bindingRevision && count && counts.buffer == 1 &&
					                     !counts.texture && !counts.sampler && !binding.hasImmutableSamplers();
					uint64_t generation = cacheEligible ? liveResources.buffers.generation() : UINT64_MAX;
					if (cacheEligible && preparation.matches(set->metal4Preparation, used.bindingIdx, generation,
						[&] { return liveResources.buffers.generation(); })) {
						appendGroupBinding(set->metal4Preparation, used.bindingIdx, bindingRevision);
						return true;
					}
					bool allBuffersLive = cacheEligible;
					bool allBuffersProven = cacheEligible && count <= Snapshots::kMaxResources;
					std::vector<MVKMetal4PreparedResourceProof> bufferProofs;
					auto& texturePreparation = sink.encoder.getState().metal4TexturePreparationCache();
					bool textureCacheEligible = set->layout == layout && set->metal4Preparation.incarnation &&
					                            bindingRevision && count && !counts.buffer &&
					                            (counts.texture || counts.sampler) && !binding.hasImmutableSamplers() &&
					                            uint64_t(count) * (counts.texture + counts.sampler) <= MVKMetal4PreparedTextureBindingCache::kMaxResources;
					if (textureCacheEligible) {
						if (stats) { ++stats->textureCacheEligible; }
						auto textureLookup = texturePreparation.lookup(set->metal4Preparation.incarnation,
							bindingRevision, used.bindingIdx);
						if (textureLookup == MVKMetal4PreparedTextureBindingCache::Result::Hit) {
							if (stats) {
								++stats->textureCacheHits;
								stats->textureHitResourceSlots += uint64_t(count) * (counts.texture + counts.sampler);
							}
							appendGroupBinding(set->metal4Preparation, used.bindingIdx, bindingRevision);
							return true;
						}
						if (stats) { ++stats->textureCacheMisses; }
						textureCacheEligible = textureLookup == MVKMetal4PreparedTextureBindingCache::Result::Attempt;
						if (stats) {
							if (textureCacheEligible) { ++stats->textureProofAttempts; }
							else { ++stats->textureNegativeMemoSkips; }
						}
					}
					std::vector<MVKMetal4PreparedResourceProof> textureProofs;
					bool allTexturesProven = textureCacheEligible;
					uint64_t resourceCount = uint64_t(count) * (counts.buffer + counts.texture + counts.sampler);
					bool snapshotEligible = bindingRevision && set->metal4Preparation.snapshots &&
					                        set->layout == layout && resourceCount && resourceCount <= Snapshots::kMaxResources &&
					                        binding.cpuLayout != MVKDescriptorCPULayout::InlineData && !binding.hasImmutableSamplers();
					uint64_t snapshotGeneration = liveResources.buffers.generation();
					if (snapshotEligible) {
						auto result = set->metal4Preparation.snapshots->replay(used.bindingIdx, bindingRevision,
							[&](const Snapshots::Resource& resource) {
								auto result = replayMetal4Resource(sink, resource);
								if (result == Snapshots::Result::Hit && allTexturesProven) { textureProofs.push_back(resource.proof); }
								if (result == Snapshots::Result::Hit && allBuffersProven &&
								    resource.kind == Snapshots::Kind::Buffer) { bufferProofs.push_back(resource.proof); }
								if (result == Snapshots::Result::Hit && captureBinding) {
									if (groupResources.size() < Group::kMaxResources) { groupResources.push_back(resource); }
									else { captureBinding = false; }
								}
								return result;
							});
						if (result == Snapshots::Result::Failed) { return false; }
						if (result == Snapshots::Result::Hit) {
							if (cacheEligible && snapshotGeneration == liveResources.buffers.generation()) {
								if (!allBuffersProven || bufferProofs.size() != count) { bufferProofs.clear(); }
								preparation.remember(set->metal4Preparation, used.bindingIdx, snapshotGeneration, std::move(bufferProofs));
							}
							if (allTexturesProven) { texturePreparation.remember(set->metal4Preparation.incarnation,
								bindingRevision, used.bindingIdx, std::move(textureProofs)); }
							return true;
						}
						groupResources.resize(groupStart);
						textureProofs.clear();
						bufferProofs.clear();
					}
					if (!snapshotEligible) { captureBinding = false; }
					std::vector<Snapshots::Resource> snapshotResources;
					auto captureSnapshot = [&](id value, Snapshots::Kind kind, const MVKMetal4PreparedResourceProof& proof) {
						if (!snapshotEligible) { return; }
						if (!value || !proof.valid()) { snapshotEligible = false; return; }
						bool ordinary = kind == Snapshots::Kind::Texture &&
						    MVKMetal4Submission::drawableRegistrationGeneration((id<MTLTexture>)value) == 0;
						snapshotResources.push_back({(const void*)value, kind, proof, ordinary});
				};
				if (binding.hasImmutableSamplers()) {
					const auto& samplers = layout->immutableSamplers();
					if (binding.immSamplerIndex > samplers.size() || count > samplers.size() - binding.immSamplerIndex) {
						return metal4Failure(sink.encoder, "Native indirect immutable sampler range is invalid.");
					}
					for (uint32_t i = 0; i < count; ++i) {
						if (!sink.object(samplers[binding.immSamplerIndex + i]->getMTLSamplerState())) { return false; }
					}
				}
				if (binding.cpuLayout == MVKDescriptorCPULayout::InlineData || !count) { return true; }
				size_t stride = descriptorCPUSize(binding.cpuLayout);
				if (!stride) { captureBinding = false; return true; }
				uint64_t span = uint64_t(stride) * count;
				if (binding.cpuOffset > set->cpuBufferSize || span > set->cpuBufferSize - binding.cpuOffset || !set->cpuBuffer) {
					return metal4Failure(sink.encoder, "Native indirect descriptor range exceeds CPU payload.");
				}
				for (uint32_t i = 0; i < count; ++i) {
					const char* data = set->cpuBuffer + binding.cpuOffset + size_t(i) * stride;
					for (uint32_t t = 0; t < counts.texture; ++t) {
						id<MTLTexture> value = nil;
						if ((t + 1) * sizeof(id) > stride) { return metal4Failure(sink.encoder, "Native indirect texture layout is invalid."); }
						memcpy(&value, data + t * sizeof(id), sizeof(value));
						auto live = liveResources.textures.isLive(value);
						if (live && !sink.resource(value)) { return false; }
						if (snapshotEligible || allTexturesProven) {
							auto proof = liveResources.textures.preparationProof(value, live);
							if (snapshotEligible) { captureSnapshot(live ? value : nil, Snapshots::Kind::Texture, proof); }
							if (allTexturesProven) {
								if (proof.valid()) { textureProofs.push_back(std::move(proof)); }
								else { allTexturesProven = false; }
							}
						}
					}
					if (counts.buffer || (counts.sampler && !binding.hasImmutableSamplers())) {
						if ((counts.texture + 1) * sizeof(id) > stride) { return metal4Failure(sink.encoder, "Native indirect descriptor layout is invalid."); }
						id value = nil;
						memcpy(&value, data + counts.texture * sizeof(id), sizeof(value));
						if (counts.buffer) {
							auto live = liveResources.buffers.isLive(value);
							if (live && !sink.bufferResource(value)) { return false; }
							if (snapshotEligible || allBuffersProven) {
								auto proof = liveResources.buffers.membershipProof(value, live);
								captureSnapshot(live ? value : nil, Snapshots::Kind::Buffer, proof);
								if (allBuffersProven) {
									if (proof.valid()) { bufferProofs.push_back(std::move(proof)); }
									else { allBuffersProven = false; }
								}
							}
							if (!value || !live) { allBuffersLive = false; }
						} else {
							auto live = liveResources.isLive(static_cast<id<MTLSamplerState>>(value));
							if (live && !sink.object(value)) { return false; }
							if (snapshotEligible || allTexturesProven) {
								auto proof = liveResources.samplers.preparationProof(value, live);
								if (snapshotEligible) { captureSnapshot(live ? value : nil, Snapshots::Kind::Sampler, proof); }
								if (allTexturesProven) {
									if (proof.valid()) { textureProofs.push_back(std::move(proof)); }
									else { allTexturesProven = false; }
								}
							}
						}
					}
				}
				// Each initial live guard pinned the exact object in this submission.
				// Weak exact membership proofs reject removal/address reuse at replay.
				// Unrelated buffer membership changes do not discard prepared payloads.
				if (snapshotEligible && snapshotResources.size() == resourceCount) {
					if (captureBinding) {
						if (snapshotResources.size() <= Group::kMaxResources - groupResources.size()) {
							groupResources.insert(groupResources.end(), snapshotResources.begin(), snapshotResources.end());
						} else { captureBinding = false; }
					}
					set->metal4Preparation.snapshots->remember(used.bindingIdx, bindingRevision,
						std::move(snapshotResources));
				} else { captureBinding = false; }
				if (allBuffersLive && generation == liveResources.buffers.generation()) {
					if (!allBuffersProven || bufferProofs.size() != count) { bufferProofs.clear(); }
					preparation.remember(set->metal4Preparation, used.bindingIdx, generation, std::move(bufferProofs));
				}
				if (allTexturesProven && textureProofs.size() == uint64_t(count) * (counts.texture + counts.sampler)) {
					if (stats) { ++stats->textureProofReady; }
					texturePreparation.remember(set->metal4Preparation.incarnation, bindingRevision,
					                            used.bindingIdx, std::move(textureProofs));
		        } else if (textureCacheEligible) {
					if (stats) { ++stats->textureProofRejected; }
		            texturePreparation.reject(set->metal4Preparation.incarnation, bindingRevision, used.bindingIdx);
				}
				return true;
				};
				if (!prepareCurrentPayload()) { return false; }
				if (captureGroup) {
					if (captureBinding && capturedRevision && groupResources.size() > groupStart) {
						coveredBindings.push_back({static_cast<uint32_t>(ordinal), used.set, used.bindingIdx,
						                          static_cast<uint32_t>(groupResources.size() - groupStart), capturedRevision});
					} else {
						groupResources.resize(groupStart);
						residualBindings.push_back(static_cast<uint32_t>(ordinal));
					}
				}
				return true;
			};
			if (retained) {
				// A partial plan skips only its proven bindings; residual payloads are
				// read in the original immutable script order, with no per-draw copy.
				for (uint32_t ordinal : retained->residual) { if (!prepareBinding(ordinal)) { return false; } }
			} else {
				for (size_t ordinal = 0; ordinal < resourceBindings.size(); ++ordinal) {
					if (!prepareBinding(ordinal)) { return false; }
				}
			}
			auto after = groupStamp();
			if (captureGroup) {
				retained = groupSnapshot->remember(before, after, std::move(groupResources), std::move(coveredBindings),
				                                  std::move(residualBindings), resourceBindings.size());
				if (!retained) { groupSnapshot->reject(before); }
			}
			groupPreparation.remember(before, after, std::move(retained));
		}
	}
	for (const MVKDescriptorBindOperation& op : resources.bindScript.ops.contents()) {
		if (op.set >= common._layout->getDescriptorSetCount() || op.set >= kMVKMaxDescriptorSetCount || !common._descriptorSets[op.set]) {
			return metal4Failure(sink.encoder, "Missing native descriptor set.");
		}
		auto* set = common._descriptorSets[op.set];
		auto* layout = common._layout->getDescriptorSetLayout(op.set);
		if (op.bindingIdx >= layout->bindings().size()) { return metal4Failure(sink.encoder, "Native descriptor binding is outside its layout."); }
		const auto& binding = layout->bindings()[op.bindingIdx];
		uint32_t count = binding.isVariable() ? set->variableDescriptorCount : binding.descriptorCount;
		if (op.opcode == MVKDescriptorBindOperationCode::BindImmutableSampler) {
			const auto& samplers = layout->immutableSamplers();
			if (binding.immSamplerIndex > samplers.size() || count > samplers.size() - binding.immSamplerIndex) {
				return metal4Failure(sink.encoder, "Native immutable sampler range is outside its layout.");
			}
			for (uint32_t i = 0; i < count; ++i) {
				if (i > UINT32_MAX - op.target || !sink.sampler(samplers[binding.immSamplerIndex + i]->getMTLSamplerState(), op.target + i)) { return false; }
			}
			continue;
		}
		size_t stride = descriptorCPUSize(binding.cpuLayout);
		size_t start = size_t(binding.cpuOffset) + op.offset();
		bool bindBytes = op.opcode == MVKDescriptorBindOperationCode::BindBytes;
		bool bindBuffer = op.opcode == MVKDescriptorBindOperationCode::BindBuffer || op.opcode == MVKDescriptorBindOperationCode::BindBufferDynamic ||
		                  op.opcode == MVKDescriptorBindOperationCode::BindBufferWithLiveCheck || op.opcode == MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck;
		size_t elementSize = bindBuffer ? sizeof(id) + sizeof(uint64_t) : sizeof(id);
		uint64_t span = bindBytes ? count : (count ? uint64_t(count - 1) * stride + elementSize : 0);
		if (start > set->cpuBufferSize || span > set->cpuBufferSize - start || (span && !set->cpuBuffer)) {
			return metal4Failure(sink.encoder, "Native descriptor operation exceeds CPU payload bounds.");
		}
		if (!count) { continue; }
		const char* src = set->cpuBuffer + start;
		if (bindBytes) {
			if (!sink.bytes(src, count, op.target)) { return false; }
			continue;
		}
		bool dynamic = op.opcode == MVKDescriptorBindOperationCode::BindBufferDynamic || op.opcode == MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck;
		if (dynamic && (op.target2 > implicit.dynamicOffsets.size() || count > implicit.dynamicOffsets.size() - op.target2)) {
			return metal4Failure(sink.encoder, "Native dynamic descriptor offsets exceed metadata bounds.");
		}
		for (uint32_t i = 0; i < count; ++i, src += stride) {
			id value = nil;
			memcpy(&value, src, sizeof(value));
			if (i > UINT32_MAX - op.target) { return metal4Failure(sink.encoder, "Native descriptor target overflow."); }
			uint32_t target = op.target + i;
			uint64_t offset = 0;
			if (bindBuffer) {
				memcpy(&offset, src + sizeof(id), sizeof(offset));
				if (dynamic) {
					uint32_t delta = implicit.dynamicOffsets[op.target2 + i];
					if (offset > UINT64_MAX - delta) { return metal4Failure(sink.encoder, "Native dynamic buffer offset overflow."); }
					offset += delta;
				}
			}
			auto& liveResources = sink.encoder.getDevice()->getLiveResources();
			switch (op.opcode) {
				case MVKDescriptorBindOperationCode::BindBuffer:
				case MVKDescriptorBindOperationCode::BindBufferDynamic:
					if (!sink.buffer(value, offset, target)) { return false; }
					break;
				case MVKDescriptorBindOperationCode::BindBufferWithLiveCheck:
				case MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck: {
					auto live = liveResources.buffers.isLive(value);
					if (!sink.buffer(live ? value : nil, offset, target)) { return false; }
					break;
				}
				case MVKDescriptorBindOperationCode::BindTexture:
					if (stats) { ++stats->directTextureBindings; }
					if (!sink.texture(value, target)) { return false; }
					break;
				case MVKDescriptorBindOperationCode::BindTextureWithLiveCheck: {
					if (stats) { ++stats->directTextureBindings; }
					auto live = liveResources.textures.isLive(value);
					if (!sink.texture(live ? value : nil, target)) { return false; }
					break;
				}
				case MVKDescriptorBindOperationCode::BindSampler:
					if (!sink.sampler(value, target)) { return false; }
					break;
				case MVKDescriptorBindOperationCode::BindSamplerWithLiveCheck: {
					auto live = liveResources.isLive(static_cast<id<MTLSamplerState>>(value));
					if (!sink.sampler(live ? value : nil, target)) { return false; }
					break;
				}
				case MVKDescriptorBindOperationCode::UseResource:
					if (!sink.resource(value)) { return false; }
					break;
				case MVKDescriptorBindOperationCode::UseBufferWithLiveCheck: {
					auto live = liveResources.buffers.isLive(value);
					if (live && !sink.bufferResource(value)) { return false; }
					break;
				}
				case MVKDescriptorBindOperationCode::UseTextureWithLiveCheck: {
					auto live = liveResources.textures.isLive(value);
					if (live && !sink.resource(value)) { return false; }
					break;
				}
				default: return metal4Failure(sink.encoder, "Unsupported native descriptor operation.");
			}
		}
	}
	const auto& counts = common._layout->getResourceCounts().stages[vkStage];
	for (MVKImplicitBuffer buffer : resources.implicitBuffers.needed & MVKNonVolatileImplicitBuffers) {
		uint32_t index = resources.implicitBuffers.ids[buffer];
		auto implicitID = static_cast<MVKNonVolatileImplicitBuffer>(buffer);
		const void* data = nullptr;
		size_t length = 0;
		uint32_t range[2] = {};
		uint64_t value = 0;
		switch (implicitID) {
			case MVKNonVolatileImplicitBuffer::PushConstant:
				if (common._layout->getPushConstantsLength() > shared._pushConstants.size()) { return metal4Failure(sink.encoder, "Native push constants exceed host storage."); }
				data = shared._pushConstants.data(); length = common._layout->getPushConstantsLength(); break;
			case MVKNonVolatileImplicitBuffer::Swizzle:
				data = implicit.textureSwizzles.data(); length = std::min(implicit.textureSwizzles.size(), size_t(counts.textureIndex)) * sizeof(uint32_t); break;
			case MVKNonVolatileImplicitBuffer::BufferSize:
				data = implicit.bufferSizes.data(); length = std::min(implicit.bufferSizes.size(), size_t(counts.bufferIndex)) * sizeof(uint32_t); break;
			case MVKNonVolatileImplicitBuffer::DynamicOffset:
				data = implicit.dynamicOffsets.data(); length = std::min(implicit.dynamicOffsets.size(), size_t(counts.dynamicOffsetBufferIndex)) * sizeof(uint32_t); break;
			case MVKNonVolatileImplicitBuffer::ViewRange: {
				auto* subpass = sink.encoder.getSubpass();
				if (!subpass) { return metal4Failure(sink.encoder, "Native view range requires a render pass."); }
				range[0] = subpass->getFirstViewIndexInMetalPass(sink.encoder.getMultiviewPassIndex());
				range[1] = subpass->getViewCountInMetalPass(sink.encoder.getMultiviewPassIndex());
				value = uint64_t(range[0]) | (uint64_t(range[1]) << 32);
				data = range; length = sizeof(range); break;
			}
			case MVKNonVolatileImplicitBuffer::EmulatedReversedDepthViewport:
				value = implicit.emulatedReversedDepthViewportMask;
				data = &implicit.emulatedReversedDepthViewportMask; length = sizeof(implicit.emulatedReversedDepthViewportMask); break;
			default: return metal4Failure(sink.encoder, "Unsupported native implicit buffer.");
		}
		auto& cached = prepared.implicit[implicitID];
		// Logical updates invalidate this memo even when another encoder is active.
		// Layout/length/slot checks handle pipeline ABI changes; the slot revision
		// catches direct, vertex and helper writes without rescanning immutable bytes.
		if (cached.layout == common._layout && cached.length == length && cached.value == value &&
		    cached.matches(tables, index, tables->bufferBindingRevision(sink.stage, index))) { continue; }
		if (!sink.bytes(data, length, index)) { return false; }
		cached.layout = common._layout; cached.length = length; cached.value = value;
		cached.remember(tables, index, tables->bufferBindingRevision(sink.stage, index));
	}
	return true;
}
} // namespace

bool MVKCommandEncoderState::offsetMetal4ZeroDivisorVertexBuffers(MVKCommandEncoder& mvkEncoder, MVKGraphicsPipeline* pipeline, uint32_t firstInstance) {
	Metal4BindingSink sink { mvkEncoder, Metal4Stage::Vertex };
	for (const auto& binding : pipeline->getZeroDivisorVertexBindings()) {
		const auto& buffer = _vkGraphics._vertexBuffers[binding.first];
		uint64_t delta = uint64_t(firstInstance) * binding.second;
		if (delta > UINT64_MAX - buffer.offset) { return metal4Failure(mvkEncoder, "Native zero-divisor vertex offset overflow."); }
		uint32_t index = pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first);
		if (!sink.bufferResource(buffer.mtlBuffer)) { return false; }
		NSError* error = nil;
		bool dynamic = pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride);
		bool ok = dynamic
			? mvkEncoder.getMetal4ArgumentTables()->setBufferWithStride(Metal4Stage::Vertex, buffer.mtlBuffer, buffer.offset + delta, buffer.stride, index, &error)
			: mvkEncoder.getMetal4ArgumentTables()->setBuffer(Metal4Stage::Vertex, buffer.mtlBuffer, buffer.offset + delta, index, &error);
		if (!sink.check(ok, error)) { return false; }
	}
	return true;
}

bool MVKCommandEncoderState::prepareMetal4ResourceRegistration(MVKCommandEncoder& encoder) {
	auto* submission = encoder.getMetal4Submission();
	if (!submission || !submission->commandBuffer()) {
		return metal4Failure(encoder, "Native resource binding requires a recording submission.");
	}
	if (!submission->matchesRecordingToken(_metal4BindingRecordingToken)) {
		_metal4OwnedBuffers.clear(); _metal4OwnedObjects.clear();
		_metal4OwnedTextures.clear();
		_metal4PreparedDescriptorBindings.clear(); _metal4PreparedTextureBindings.clear();
		for (auto& stage : _metal4StagePreparation) { stage = {}; }
		_metal4BindingRecordingToken = submission->recordingToken();
	}
	return true;
}

bool MVKCommandEncoderState::registerMetal4Buffer(MVKCommandEncoder& encoder, id<MTLBuffer> buffer) {
	if (!buffer) { return true; }
	const void* identity = (const void*)buffer;
	if (_metal4OwnedBuffers.count(identity)) { return true; }
	NSError* error = nil;
	if (!encoder.getMetal4Submission()->addResource(buffer, &error)) {
		return metal4Failure(encoder, error ? error.localizedDescription.UTF8String : "Native buffer registration failed.");
	}
	// The successful registration pins this exact buffer through retirement.
	// Bound CPU storage is bounded by entry count; overflow uses the old path.
	if (_metal4OwnedBuffers.size() < 256) { _metal4OwnedBuffers.insert(identity); }
	return true;
}

bool MVKCommandEncoderState::registerMetal4Texture(MVKCommandEncoder& encoder, id<MTLTexture> texture) {
	if (!texture) { return true; }
	const void* identity = (const void*)texture;
	if (_metal4OwnedTextures.matchesOrdinary(identity)) { return true; }
	// Sample before registration: a concurrent registry mutation during or after
	// addResource must leave this memo stale, never falsely current.
	uint64_t generation = MVKMetal4Submission::drawableRegistrationGeneration(texture);
	if (_metal4OwnedTextures.matches(identity, generation)) { return true; }
	NSError* error = nil;
	if (!encoder.getMetal4Submission()->addResource(texture, &error)) {
		return metal4Failure(encoder, error ? error.localizedDescription.UTF8String : "Native texture registration failed.");
	}
	if (!generation) { _metal4OwnedTextures.rememberOrdinary(identity); }
	else { _metal4OwnedTextures.remember(identity, generation); }
	return true;
}

bool MVKCommandEncoderState::retainMetal4Object(MVKCommandEncoder& encoder, id object) {
	if (!object) { return true; }
	const void* identity = (const void*)object;
	if (_metal4OwnedObjects.count(identity)) { return true; }
	NSError* error = nil;
	if (!encoder.getMetal4Submission()->retainObject(object, &error)) {
		return metal4Failure(encoder, error ? error.localizedDescription.UTF8String : "Native object retention failed.");
	}
	if (_metal4OwnedObjects.size() < 256) { _metal4OwnedObjects.insert(identity); }
	return true;
}

bool MVKCommandEncoderState::prepareMetal4Draw(id<MTL4RenderCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder, bool primitivesConverted) {
	auto* pipeline = _vkGraphics._pipeline;
	if (!encoder || !pipeline || !pipeline->getMainPipelineState() || !mvkEncoder.getSubpass()) { return metal4Failure(mvkEncoder, "Native graphics pipeline/encoder is unavailable."); }
	if (pipeline->isTessellationPipeline() || (!primitivesConverted && _vkGraphics.getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN)) {
		return metal4Failure(mvkEncoder, "Native Metal 4 tessellation/fan emulation is not integrated.");
	}
	VkPrimitiveTopology topology = _vkGraphics.getPrimitiveTopology();
	bool strip = topology == VK_PRIMITIVE_TOPOLOGY_LINE_STRIP || topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
	if (!primitivesConverted && mvkEncoder._isIndexedDraw && _vkGraphics.isPrimitiveRestartEnabled() != strip) {
		return metal4Failure(mvkEncoder, strip ? "Native Metal 4 disabled strip restart requires index conversion."
			: "Native Metal 4 list primitive restart requires index conversion.");
	}
	if (!primitivesConverted && _vkGraphics.getProvokingVertexMode() && pipeline->metal4UsesProvokingVertex() && topology != VK_PRIMITIVE_TOPOLOGY_POINT_LIST) {
		return metal4Failure(mvkEncoder, "Native Metal 4 flat last-provoking vertex requires index conversion.");
	}
	if (topology == VK_PRIMITIVE_TOPOLOGY_LINE_LIST || topology == VK_PRIMITIVE_TOPOLOGY_LINE_STRIP ||
	    _vkGraphics.pickRenderState(MVKRenderStateFlag::PolygonMode).polygonMode == MVKPolygonMode::Lines) {
		float width = _vkGraphics.pickRenderState(MVKRenderStateFlag::LineWidth).lineWidth;
		bool setWidth = false;
#if MVK_USE_METAL_PRIVATE_API
		if (mvkEncoder.getMVKConfig().useMetalPrivateAPI && [encoder respondsToSelector:@selector(setLineWidth:)]) {
			[static_cast<id<MVKMTL4WideLineEncoder>>(encoder) setLineWidth:width];
			setWidth = true;
		}
#endif
		if (!setWidth && width != 1.0f) { return metal4Failure(mvkEncoder, "Native Metal 4 wide-line selector is unavailable."); }
	}
	if (_vkGraphics.pickRenderState(MVKRenderStateFlag::PolygonMode).polygonMode == MVKPolygonMode::Point &&
	    pipeline->getPrimitiveTopologyClass() != MTLPrimitiveTopologyClassPoint &&
	    pipeline->getPrimitiveTopologyClass() != MTLPrimitiveTopologyClassUnspecified) {
		return metal4Failure(mvkEncoder, "Native Metal 4 dynamic point polygon mode is unavailable for this pipeline.");
	}
	if (!mvkEncoder.ensureMetal4ArgumentTables()) { return false; }
	if (!prepareMetal4ResourceRegistration(mvkEncoder)) { return false; }
	Metal4BindingSink vertex { mvkEncoder, Metal4Stage::Vertex };
	Metal4BindingSink fragment { mvkEncoder, Metal4Stage::Fragment };
	auto* subpass = mvkEncoder.getSubpass();
	id<MTLRenderPipelineState> state = subpass->isMultiview()
		? pipeline->getMultiviewPipelineState(subpass->getViewCountInMetalPass(mvkEncoder.getMultiviewPassIndex()))
		: pipeline->getMainPipelineState();
	if (!state) { return metal4Failure(mvkEncoder, "Native graphics pipeline state is unavailable."); }
	if (_metal4GraphicsPipeline != state) {
		if (!vertex.object(state)) { return false; }
		[encoder setRenderPipelineState:state];
		_metal4GraphicsPipeline = state;
	}
	if (!_mtlGraphics.bindMetal4State(encoder, mvkEncoder, _vkGraphics)) { return false; }
	if (!mvkEncoder._occlusionQueryState.encodeMetal4(encoder, &mvkEncoder)) { return false; }
	if (!bindMetal4Resources(vertex, _vkGraphics, pipeline->getStageResources(kMVKShaderStageVertex), _vkGraphics._implicitBufferData[kMVKShaderStageVertex], _vkShared, kMVKShaderStageVertex) ||
	    !bindMetal4Resources(fragment, _vkGraphics, pipeline->getStageResources(kMVKShaderStageFragment), _vkGraphics._implicitBufferData[kMVKShaderStageFragment], _vkShared, kMVKShaderStageFragment)) { return false; }
	bool dynamic = pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride);
	auto bindVertex = [&](uint32_t binding, uint32_t metalBinding, uint64_t extraOffset) {
		if (binding >= kMVKMaxBufferCount) { return metal4Failure(mvkEncoder, "Native vertex binding index is invalid."); }
		const auto& buffer = _vkGraphics._vertexBuffers[binding];
		if (extraOffset > UINT64_MAX - buffer.offset) { return metal4Failure(mvkEncoder, "Native translated vertex offset overflow."); }
		if (!vertex.bufferResource(buffer.mtlBuffer)) { return false; }
		NSError* error = nil;
		uint32_t index = pipeline->getMetalBufferIndexForVertexAttributeBinding(metalBinding);
		bool ok = dynamic
			? mvkEncoder.getMetal4ArgumentTables()->setBufferWithStride(Metal4Stage::Vertex, buffer.mtlBuffer, buffer.offset + extraOffset, buffer.stride, index, &error)
			: mvkEncoder.getMetal4ArgumentTables()->setBuffer(Metal4Stage::Vertex, buffer.mtlBuffer, buffer.offset + extraOffset, index, &error);
		return vertex.check(ok, error);
	};
	for (size_t index : pipeline->getVkVertexBuffers()) {
		if (!bindVertex(static_cast<uint32_t>(index), static_cast<uint32_t>(index), 0)) { return false; }
	}
	for (const auto& binding : pipeline->getTranslatedVertexBindings()) {
		if (!bindVertex(binding.binding, binding.translationBinding, binding.translationOffset)) { return false; }
	}
	auto* tables = mvkEncoder.getMetal4ArgumentTables();
	// The submission keeps its primary table lease alive through retirement. Table
	// contents snapshot at draw; modifying a slot does not require setArgumentTable.
	if (!_metal4GraphicsTablesBound) {
		NSError* error = nil;
		bool ok = tables->bindRender(encoder, MTLRenderStageVertex | MTLRenderStageFragment, &error);
		if (!vertex.check(ok, error)) { return false; }
		_metal4GraphicsTablesBound = true;
	}
	return true;
}

bool MVKCommandEncoderState::prepareMetal4ComputeDispatch(id<MTL4ComputeCommandEncoder> encoder, MVKCommandEncoder& mvkEncoder) {
	auto* pipeline = _vkCompute._pipeline;
	if (!encoder || !pipeline || !pipeline->getPipelineState()) { return metal4Failure(mvkEncoder, "Native compute pipeline/encoder is unavailable."); }
	if (pipeline->allowsDispatchBase()) { return metal4Failure(mvkEncoder, "Native Metal 4 dispatch-base shader ABI is not integrated."); }
	if (!mvkEncoder.ensureMetal4ArgumentTables()) { return false; }
	if (!prepareMetal4ResourceRegistration(mvkEncoder)) { return false; }
	Metal4BindingSink sink { mvkEncoder, Metal4Stage::Compute };
	if (!bindMetal4Resources(sink, _vkCompute, pipeline->getStageResources(), _vkCompute._implicitBufferData, _vkShared, kMVKShaderStageCompute)) { return false; }
	if (_metal4ComputePipeline != pipeline->getPipelineState()) {
		if (!sink.object(pipeline->getPipelineState())) { return false; }
		[encoder setComputePipelineState:pipeline->getPipelineState()];
		_metal4ComputePipeline = pipeline->getPipelineState();
	}
	auto* tables = mvkEncoder.getMetal4ArgumentTables();
	if (!_metal4ComputeTableBound) {
		NSError* error = nil;
		bool ok = tables->bindCompute(encoder, &error);
		if (!sink.check(ok, error)) { return false; }
		_metal4ComputeTableBound = true;
	}
	return true;
}

void MVKCommandEncoderState::invalidateMetal4GraphicsAfterHelper() {
	_metal4GraphicsPipeline = nil;
	_metal4GraphicsTablesBound = false;
	_mtlGraphics._stateReady = {};
	_mtlGraphics._metal4UnknownState = MVKRenderStateFlags::all();
}

void MVKCommandEncoderState::invalidateMetal4ComputeBindings() {
	_metal4ComputePipeline = nil;
	_metal4ComputeTableBound = false;
}

void MVKCommandEncoderState::invalidateMetal4ImplicitBuffer(VkPipelineBindPoint bindPoint, MVKNonVolatileImplicitBuffer buffer) {
	// Native argument tables survive encoder switches. A graphics update while
	// compute is active (or vice versa) must still invalidate the stored payload.
	for (uint32_t stage = 0; stage < kMVKShaderStageCount; ++stage) {
		if (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS && stage == kMVKShaderStageCompute) { continue; }
		if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE && stage != kMVKShaderStageCompute) { continue; }
		_metal4StagePreparation[stage].implicit[buffer].slotRevision = 0;
	}
}
#endif

#if MVK_USE_METAL_PRIVATE_API
// An extension of the MTLRenderCommandEncoder protocol to declare the setLineWidth: method.
@protocol MVKMTLRenderCommandEncoder <MTLRenderCommandEncoder>
- (void)setLineWidth:(float)width;
- (void)setPrimitiveRestartEnabled:(BOOL)enabled index:(NSUInteger)index;
- (void)setProvokingVertexMode:(NSUInteger)mode;
@end
#endif

#pragma mark - Resource Binder Structs

static MTLRenderStages getMTLStages(MVKResourceUsageStages stages) {
	switch (stages) {
		case MVKResourceUsageStages::Vertex:   return MTLRenderStageVertex;
		case MVKResourceUsageStages::Fragment: return MTLRenderStageFragment;
		case MVKResourceUsageStages::All:      return MTLRenderStageVertex | MTLRenderStageFragment;
		case MVKResourceUsageStages::Count:    break;
	}
	assert(0);
	return 0;
}

static void useResourceGraphics(id<MTLCommandEncoder> encoder, id<MTLResource> resource, MTLResourceUsage usage, MVKResourceUsageStages stages) {
	[static_cast<id<MTLRenderCommandEncoder>>(encoder) useResource:resource usage:usage stages:getMTLStages(stages)];
}

static void useResourceCompute(id<MTLCommandEncoder> encoder, id<MTLResource> resource, MTLResourceUsage usage, MVKResourceUsageStages stages) {
	[static_cast<id<MTLComputeCommandEncoder>>(encoder) useResource:resource usage:usage];
}

struct MVKFragmentBinder {
	static SEL selSetBytes()   { return @selector(setFragmentBytes:length:atIndex:); }
	static SEL selSetBuffer()  { return @selector(setFragmentBuffer:offset:atIndex:); }
	static SEL selSetOffset()  { return @selector(setFragmentBufferOffset:atIndex:); }
	static SEL selSetTexture() { return @selector(setFragmentTexture:atIndex:); }
	static SEL selSetSampler() { return @selector(setFragmentSamplerState:atIndex:); }
	static MVKResourceBinder::UseResource useResource() { return useResourceGraphics; }
	static void setBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) {
		[encoder setFragmentBuffer:buffer offset:offset atIndex:index];
	}
	static void setBufferOffset(id<MTLRenderCommandEncoder> encoder, NSUInteger offset, NSUInteger index) {
		[encoder setFragmentBufferOffset:offset atIndex:index];
	}
	static void setBytes(id<MTLRenderCommandEncoder> encoder, const void* bytes, NSUInteger length, NSUInteger index) {
		[encoder setFragmentBytes:bytes length:length atIndex:index];
	}
	static void setTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
		[encoder setFragmentTexture:texture atIndex:index];
	}
	static void setSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
		[encoder setFragmentSamplerState:sampler atIndex:index];
	}
};

struct MVKVertexBinder {
	static SEL selSetBytes()   { return @selector(setVertexBytes:length:atIndex:); }
	static SEL selSetBuffer()  { return @selector(setVertexBuffer:offset:atIndex:); }
	static SEL selSetOffset()  { return @selector(setVertexBufferOffset:atIndex:); }
	static SEL selSetTexture() { return @selector(setVertexTexture:atIndex:); }
	static SEL selSetSampler() { return @selector(setVertexSamplerState:atIndex:); }
	static MVKResourceBinder::UseResource useResource() { return useResourceGraphics; }
	static SEL selSetBufferDynamic() { return @selector(setVertexBuffer:offset:attributeStride:atIndex:); }
	static SEL selSetOffsetDynamic() { return @selector(setVertexBufferOffset:attributeStride:atIndex:); }
	static void setBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) {
		[encoder setVertexBuffer:buffer offset:offset atIndex:index];
	}
	static void setBufferOffset(id<MTLRenderCommandEncoder> encoder, NSUInteger offset, NSUInteger index) {
		[encoder setVertexBufferOffset:offset atIndex:index];
	}
	static void setBufferDynamic(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger stride, NSUInteger index) {
		[encoder setVertexBuffer:buffer offset:offset attributeStride:stride atIndex:index];
	}
	static void setBufferOffsetDynamic(id<MTLRenderCommandEncoder> encoder, NSUInteger offset, NSUInteger stride, NSUInteger index) {
		[encoder setVertexBufferOffset:offset attributeStride:stride atIndex:index];
	}
	static void setBytes(id<MTLRenderCommandEncoder> encoder, const void* bytes, NSUInteger length, NSUInteger index) {
		[encoder setVertexBytes:bytes length:length atIndex:index];
	}
	static void setTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
		[encoder setVertexTexture:texture atIndex:index];
	}
	static void setSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
		[encoder setVertexSamplerState:sampler atIndex:index];
	}
};

struct MVKComputeBinder {
	static SEL selSetBytes()   { return @selector(setBytes:length:atIndex:); }
	static SEL selSetBuffer()  { return @selector(setBuffer:offset:atIndex:); }
	static SEL selSetOffset()  { return @selector(setBufferOffset:atIndex:); }
	static SEL selSetTexture() { return @selector(setTexture:atIndex:); }
	static SEL selSetSampler() { return @selector(setSamplerState:atIndex:); }
	static MVKResourceBinder::UseResource useResource() { return useResourceCompute; }
	static SEL selSetBufferDynamic() { return @selector(setBuffer:offset:attributeStride:atIndex:); }
	static SEL selSetOffsetDynamic() { return @selector(setBufferOffset:attributeStride:atIndex:); }
	static void setBuffer(id<MTLComputeCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) {
		[encoder setBuffer:buffer offset:offset atIndex:index];
	}
	static void setBufferOffset(id<MTLComputeCommandEncoder> encoder, NSUInteger offset, NSUInteger index) {
		[encoder setBufferOffset:offset atIndex:index];
	}
	static void setBufferDynamic(id<MTLComputeCommandEncoder> encoder, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger stride, NSUInteger index) {
		[encoder setBuffer:buffer offset:offset attributeStride:stride atIndex:index];
	}
	static void setBufferOffsetDynamic(id<MTLComputeCommandEncoder> encoder, NSUInteger offset, NSUInteger stride, NSUInteger index) {
		[encoder setBufferOffset:offset attributeStride:stride atIndex:index];
	}
	static void setBytes(id<MTLComputeCommandEncoder> encoder, const void* bytes, NSUInteger length, NSUInteger index) {
		[encoder setBytes:bytes length:length atIndex:index];
	}
	static void setTexture(id<MTLComputeCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
		[encoder setTexture:texture atIndex:index];
	}
	static void setSampler(id<MTLComputeCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
		[encoder setSamplerState:sampler atIndex:index];
	}
};

template <typename T> struct ResourceBinderTable {
	T values[static_cast<uint32_t>(T::Stage::Count)];
	constexpr const T& operator[](typename T::Stage stage) const {
		assert(stage < T::Stage::Count);
		return values[static_cast<uint32_t>(stage)];
	}
	constexpr T& operator[](typename T::Stage stage) {
		assert(stage < T::Stage::Count);
		return values[static_cast<uint32_t>(stage)];
	}
};

static ResourceBinderTable<MVKResourceBinder> GenResourceBinders() {
	ResourceBinderTable<MVKResourceBinder> res = {};
	res[MVKResourceBinder::Stage::Vertex]   = MVKResourceBinder::Create<MVKVertexBinder>();
	res[MVKResourceBinder::Stage::Fragment] = MVKResourceBinder::Create<MVKFragmentBinder>();
	res[MVKResourceBinder::Stage::Compute]  = MVKResourceBinder::Create<MVKComputeBinder>();
	return res;
}

static ResourceBinderTable<MVKVertexBufferBinder> GenVertexBufferBinders() {
	ResourceBinderTable<MVKVertexBufferBinder> res = {};
	res[MVKVertexBufferBinder::Stage::Vertex]   = MVKVertexBufferBinder::Create<MVKVertexBinder>();
	res[MVKVertexBufferBinder::Stage::Compute]  = MVKVertexBufferBinder::Create<MVKComputeBinder>();
	return res;
}

const MVKResourceBinder& MVKResourceBinder::Get(Stage stage) {
	static const ResourceBinderTable<MVKResourceBinder> table = GenResourceBinders();
	return table[stage];
}

const MVKVertexBufferBinder& MVKVertexBufferBinder::Get(Stage stage) {
	static const ResourceBinderTable<MVKVertexBufferBinder> table = GenVertexBufferBinders();
	return table[stage];
}

#pragma mark - Resource Binding Functions

template <typename Binder, typename Encoder>
static void bindBuffer(Encoder encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index,
                       MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
	assert(index < kMVKMaxBufferCount);
	if (buffer) {
		if (!exists.buffers.get(index) || bindings.buffers[index].buffer != buffer) {
			exists.buffers.set(index);
			binder.setBuffer(encoder, buffer, offset, index);
			bindings.buffers[index] = { buffer, offset };
		} else if (bindings.buffers[index].offset != offset) {
			binder.setBufferOffset(encoder, offset, index);
			bindings.buffers[index].offset = offset;
		}
	} else if (exists.buffers.get(index)) {
		exists.buffers.clear(index);
		binder.setBuffer(encoder, nil, 0, index);
	}
}

template <typename Binder, typename Encoder>
static void bindBytes(Encoder encoder, const void* data, size_t size, NSUInteger index,
                      MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
	assert(index < kMVKMaxBufferCount);
	exists.buffers.set(index);
	bindings.buffers[index] = MVKStageResourceBindings::InvalidBuffer();
	binder.setBytes(encoder, data, size, index);
}

template <bool DynamicStride>
static void bindVertexBuffer(id<MTLCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, uint32_t stride, NSUInteger index,
                             MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const MVKVertexBufferBinder& binder) {
	assert(index < kMVKMaxBufferCount);
	VkDeviceSize offsetLookup = offset;
	if constexpr (DynamicStride)
		offsetLookup ^= static_cast<VkDeviceSize>(stride ^ (1u << 31)) << 32;
	if (!exists.buffers.get(index) || bindings.buffers[index].buffer != buffer) {
		exists.buffers.set(index);
		if constexpr (DynamicStride)
			binder.setBufferDynamic(encoder, buffer, offset, stride, index);
		else
			binder.setBuffer(encoder, buffer, offset, index);
		bindings.buffers[index] = { buffer, offsetLookup };
	} else if (bindings.buffers[index].offset != offsetLookup) {
		if constexpr (DynamicStride)
			binder.setBufferOffsetDynamic(encoder, offset, stride, index);
		else
			binder.setBufferOffset(encoder, offset, index);
		bindings.buffers[index].offset = offsetLookup;
	}
}

template <typename Binder, typename Encoder>
static void bindTexture(Encoder encoder, id<MTLTexture> texture, NSUInteger index,
                        MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
	assert(index < kMVKMaxTextureCount);
	if (!exists.textures.get(index) || bindings.textures[index] != texture) {
		exists.textures.set(index);
		binder.setTexture(encoder, texture, index);
		bindings.textures[index] = texture;
	}
}

template <typename Binder, typename Encoder>
static void bindSampler(Encoder encoder, id<MTLSamplerState> sampler, NSUInteger index,
                        MVKStageResourceBits& exists, MVKStageResourceBindings& bindings, const Binder& binder) {
	assert(index < kMVKMaxSamplerCount);
	if (!exists.samplers.get(index) || bindings.samplers[index] != sampler) {
		exists.samplers.set(index);
		binder.setSampler(encoder, sampler, index);
		bindings.samplers[index] = sampler;
	}
}

static uint32_t getCPUMetaOffset(MVKDescriptorCPULayout layout) {
	switch (layout) {
		case MVKDescriptorCPULayout::OneIDMeta:  return offsetof(MVKCPUDescriptorOneIDMeta,  meta);
		case MVKDescriptorCPULayout::OneID2Meta: return offsetof(MVKCPUDescriptorOneID2Meta, meta);
		case MVKDescriptorCPULayout::TwoIDMeta:  return offsetof(MVKCPUDescriptorTwoIDMeta,  meta);
		case MVKDescriptorCPULayout::TwoID2Meta: return offsetof(MVKCPUDescriptorTwoID2Meta, meta);
		case MVKDescriptorCPULayout::None:
		case MVKDescriptorCPULayout::OneID:
		case MVKDescriptorCPULayout::InlineData:
			return 0;
	}
}

enum class ImplicitBufferData {
	BufferSize,
	TextureSwizzle,
};

static bool isTexelBuffer(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER:
		case VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
			return true;
		default:
			return false;
	}
}
static bool isImage(VkDescriptorType type) {
	switch (type) {
		case VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE:
		case VK_DESCRIPTOR_TYPE_STORAGE_IMAGE:
		case VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
		case VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT:
			return true;
		default:
			return false;
	}
}

template <ImplicitBufferData DataType>
static void bindImplicitBufferData(uint32_t* target, MVKDescriptorSetLayout* layout, const void* descriptor, VkShaderStageFlags stage, uint32_t variableCount) {
	for (const auto& binding : layout->bindings()) {
		uint32_t count = binding.isVariable() ? variableCount : binding.descriptorCount;
		assert(count <= binding.descriptorCount);
		if (!count)
			continue;
		if (!mvkIsAnyFlagEnabled(binding.stageFlags, stage))
			continue;
		if (DataType == ImplicitBufferData::BufferSize && binding.descriptorType == VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK) {
			// Inline uniform blocks are bound as one buffer of size descriptorCount
			*target++ = count;
			continue;
		}
		uint32_t perDescCount;
		switch (DataType) {
			case ImplicitBufferData::BufferSize:     perDescCount = binding.perDescriptorResourceCount.buffer;  break;
			case ImplicitBufferData::TextureSwizzle: perDescCount = binding.perDescriptorResourceCount.texture; break;
		}
		if (perDescCount == 0)
			continue;
		size_t stride = descriptorCPUSize(binding.cpuLayout);
		size_t metaOff = getCPUMetaOffset(binding.cpuLayout);
		if (DataType == ImplicitBufferData::TextureSwizzle && isTexelBuffer(binding.descriptorType)) {
			mvkClear(target, count);
		} else if (metaOff == 0) {
			assert(DataType != ImplicitBufferData::BufferSize && "All buffers should have metadata");
			mvkClear(target, count);
		} else {
			const char* base = static_cast<const char*>(descriptor) + binding.cpuOffset + metaOff;
			for (uint32_t i = 0; i < count; i++, base += stride) {
				switch (DataType) {
					case ImplicitBufferData::BufferSize:
						// These are all at the same offset so the compiler should turn this into a single load
						if (isTexelBuffer(binding.descriptorType))
							target[i] = reinterpret_cast<const MVKDescriptorMetaTexelBuffer*>(base)->size;
						else if (isImage(binding.descriptorType))
							target[i] = reinterpret_cast<const MVKDescriptorMetaImage*>(base)->size;
						else
							target[i] = reinterpret_cast<const MVKDescriptorMetaBuffer*>(base)->size;
						break;
					case ImplicitBufferData::TextureSwizzle:
						target[i] = reinterpret_cast<const MVKDescriptorMetaImage*>(base)->swizzle;
						break;
				}
			}
		}
		target += perDescCount * count;
	}
}

static void bindDescriptorSets(MVKImplicitBufferData& target,
                               MVKShaderStage stage,
                               MVKPipelineLayout* layout,
                               uint32_t firstSet, uint32_t setCount, MVKDescriptorSet*const* sets,
                               uint32_t dynamicOffsetCount, const uint32_t* dynamicOffsets) {
	[[maybe_unused]] const uint32_t* dynamicOffsetsEnd = dynamicOffsets + dynamicOffsetCount;
	VkShaderStageFlags vkStage = mvkVkShaderStageFlagBitsFromMVKShaderStage(stage);
	for (uint32_t i = 0; i < setCount; i++) {
		MVKDescriptorSet* set = sets[i];
		if (!set)
			continue;
		MVKDescriptorSetLayout* setLayout = layout->getDescriptorSetLayout(firstSet + i);
		const MVKShaderStageResourceBinding& offsets = layout->getResourceBindingOffsets(firstSet + i).stages[stage];
		const MVKShaderStageResourceBinding& stride = setLayout->totalResourceCount().stages[stage];
		uint32_t varCount = set->variableDescriptorCount;
		if (uint32_t count = setLayout->dynamicOffsetCount(varCount)) {
			if (stride.dynamicOffsetBufferIndex) {
				mvkEnsureSize(target.dynamicOffsets, offsets.dynamicOffsetBufferIndex + stride.dynamicOffsetBufferIndex);
				uint32_t* write = &target.dynamicOffsets[offsets.dynamicOffsetBufferIndex];
				for (const auto& binding : setLayout->bindings()) {
					if (!binding.perDescriptorResourceCount.dynamicOffset)
						continue;
					if (binding.stageFlags & vkStage) {
						mvkCopy(write, dynamicOffsets, binding.descriptorCount);
						write += binding.descriptorCount;
					}
					dynamicOffsets += binding.descriptorCount;
				}
			} else {
				// None of the dynamic offsets are bound to this stage
				dynamicOffsets += count;
			}
		}
		if (setLayout->argBufMode() == MVKArgumentBufferMode::Off) {
			// If we grab these now, we can be guaranteed the sets are valid
			// If we wait until draw time, we can only be guaranteed statically used sets are valid
			if (!layout->getMetalFeatures().nativeTextureSwizzle && stride.textureIndex) {
				mvkEnsureSize(target.textureSwizzles, offsets.textureIndex + stride.textureIndex);
				bindImplicitBufferData<ImplicitBufferData::TextureSwizzle>(&target.textureSwizzles[offsets.textureIndex], setLayout, set->cpuBuffer, vkStage, varCount);
			}
			if (stride.bufferIndex) {
				mvkEnsureSize(target.bufferSizes, offsets.bufferIndex + stride.bufferIndex);
				bindImplicitBufferData<ImplicitBufferData::BufferSize>(&target.bufferSizes[offsets.bufferIndex], setLayout, set->cpuBuffer, vkStage, varCount);
			}
		}
	}
	assert(dynamicOffsets == dynamicOffsetsEnd && "All dynamic offsets should have been used, and no more than that");
}

static void bindImmediateData(id<MTLCommandEncoder> encoder,
                              MVKCommandEncoder& mvkEncoder,
                              const uint8_t* data, size_t size,
                              uint32_t idx,
                              const MVKResourceBinder& RESTRICT binder) {
	if (size < 4096) {
		binder.setBytes(encoder, data, size, idx);
	} else {
		const MVKMTLBufferAllocation* alloc = mvkEncoder.copyToTempMTLBufferAllocation(data, size);
		binder.setBuffer(encoder, alloc->_mtlBuffer, alloc->_offset, idx);
	}
}

static void bindImmediateData(id<MTLCommandEncoder> encoder,
                              MVKCommandEncoder& mvkEncoder,
                              MVKArrayRef<const uint32_t> data,
                              uint32_t idx,
                              const MVKResourceBinder& RESTRICT binder) {
	bindImmediateData(encoder, mvkEncoder, reinterpret_cast<const uint8_t*>(data.data()), data.byteSize(), idx, binder);
}

/** Updates a value at the given index in the given vector, resizing if needed. */
template<class V>
static void updateImplicitBuffer(V &contents, uint32_t index, uint32_t value) {
	if (index >= contents.size()) { contents.resize(index + 1); }
	contents[index] = value;
}

static constexpr bool isUseResource(MVKDescriptorBindOperationCode op) {
	switch (op) {
		case MVKDescriptorBindOperationCode::UseBufferWithLiveCheck:
		case MVKDescriptorBindOperationCode::UseTextureWithLiveCheck:
		case MVKDescriptorBindOperationCode::UseResource:
			return true;
		default:
			return false;
	}
}

template <MVKDescriptorBindOperationCode Op>
static void executeBindOp(id<MTLCommandEncoder> encoder,
                          MVKCommandEncoder& mvkEncoder,
                          const char* src, uint32_t count, size_t stride,
                          uint32_t target, const uint32_t* dynOffsets,
                          MVKResourceUsageStages useResourceStage,
                          MVKStageResourceBits& exists,
                          MVKStageResourceBindings& bindings,
                          const MVKResourceBinder& RESTRICT binder) {
	if (Op == MVKDescriptorBindOperationCode::BindBytes) {
		MVKStageResourceBindings::Buffer buffer = { reinterpret_cast<id<MTLBuffer>>(src), 0 };
		if (!exists.buffers.get(target) || bindings.buffers[target].buffer != buffer.buffer) {
			exists.buffers.set(target);
			bindings.buffers[target] = buffer;
			bindImmediateData(encoder, mvkEncoder, reinterpret_cast<const uint8_t*>(src), count, target, binder);
		}
		return;
	}
	MVKDevice* dev = mvkEncoder.getDevice();
	for (uint32_t i = 0; i < count; i++, src += stride) {
		id resource = *reinterpret_cast<const id*>(src);
		switch (Op) {
			case MVKDescriptorBindOperationCode::BindBytes:
				assert(0); // Handled above
				break;
			case MVKDescriptorBindOperationCode::BindBuffer:
			case MVKDescriptorBindOperationCode::BindBufferDynamic:
			case MVKDescriptorBindOperationCode::BindBufferWithLiveCheck:
			case MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck: {
				static_assert(offsetof(MVKCPUDescriptorOneID2Meta, offset) == offsetof(MVKCPUDescriptorOneID2Meta, a) + sizeof(id), "For the pointer arithmetic below");
				static_assert(offsetof(MVKCPUDescriptorTwoID2Meta, offset) == offsetof(MVKCPUDescriptorTwoID2Meta, b) + sizeof(id), "For the pointer arithmetic below");
				uint64_t offset = *reinterpret_cast<const uint64_t*>(src + sizeof(id));
				if (Op == MVKDescriptorBindOperationCode::BindBufferDynamic || Op == MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck)
					offset += dynOffsets[i];
				if ((Op == MVKDescriptorBindOperationCode::BindBufferWithLiveCheck || Op == MVKDescriptorBindOperationCode::BindBufferDynamicWithLiveCheck) && resource) {
					id<MTLBuffer> buffer = resource;
					if (exists.buffers.get(target + i) && bindings.buffers[target + i].buffer == buffer) {
						if (offset != bindings.buffers[target + i].offset) {
							bindings.buffers[target + i].offset = offset;
							binder.setBufferOffset(encoder, offset, target + i);
						}
					} else if (auto live = dev->getLiveResources().isLive(buffer)) {
						exists.buffers.set(target + i);
						bindings.buffers[target + i] = { buffer, offset };
						binder.setBuffer(encoder, buffer, offset, target + i);
					}
				} else {
					bindBuffer(encoder, static_cast<id<MTLBuffer>>(resource), offset, target + i, exists, bindings, binder);
				}
				break;
			}

			case MVKDescriptorBindOperationCode::BindTexture:
				bindTexture(encoder, static_cast<id<MTLTexture>>(resource), target + i, exists, bindings, binder);
				break;

			case MVKDescriptorBindOperationCode::BindTextureWithLiveCheck:
				if (id<MTLTexture> tex = resource) {
					if (exists.textures.get(target + i) && bindings.textures[target + i] == resource) {
						// Already bound
					} else if (auto live = dev->getLiveResources().isLive(tex)) {
						exists.textures.set(target + i);
						bindings.textures[target + i] = tex;
						binder.setTexture(encoder, tex, target + i);
					}
				} else {
					bindTexture(encoder, nullptr, target + i, exists, bindings, binder);
				}
				break;

			case MVKDescriptorBindOperationCode::BindSampler:
				bindSampler(encoder, static_cast<id<MTLSamplerState>>(resource), target + i, exists, bindings, binder);
				break;

			case MVKDescriptorBindOperationCode::BindSamplerWithLiveCheck:
				if (id<MTLSamplerState> samp = resource) {
					if (exists.samplers.get(target + i) && bindings.samplers[target + i] == resource) {
						// Already bound
					} else if (auto live = dev->getLiveResources().isLive(samp)) {
						exists.samplers.set(target + i);
						bindings.samplers[target + i] = samp;
						binder.setSampler(encoder, samp, target + i);
					}
				} else {
					bindSampler(encoder, nullptr, target + i, exists, bindings, binder);
				}
				break;

			case MVKDescriptorBindOperationCode::UseResource:
				if (resource)
					mvkEncoder.getState().mtlShared()._useResource.add(resource, useResourceStage, target);
				break;

			case MVKDescriptorBindOperationCode::UseBufferWithLiveCheck:
			case MVKDescriptorBindOperationCode::UseTextureWithLiveCheck:
				if (resource) {
					MVKLiveList& list = Op == MVKDescriptorBindOperationCode::UseBufferWithLiveCheck ? dev->getLiveResources().buffers : dev->getLiveResources().textures;
					if (auto live = list.isLive(resource))
						mvkEncoder.getState().mtlShared()._useResource.addImmediate(resource, encoder, binder.useResource, useResourceStage, target);
				}
				break;
		}
	}
}

static void executeBindOps(id<MTLCommandEncoder> encoder,
                           MVKCommandEncoder& mvkEncoder,
                           const MVKVulkanCommonEncoderState& common,
                           const MVKImplicitBufferData& implicitBufferData,
                           MVKArrayRef<const MVKDescriptorBindOperation> ops,
                           MVKResourceUsageStages useResourceStage,
                           MVKStageResourceBits& exists,
                           MVKStageResourceBindings& bindings,
                           const MVKResourceBinder& RESTRICT binder) {
	bool didUseResource = false;
	for (const MVKDescriptorBindOperation& op : ops) {
		MVKDescriptorSet* set = common._descriptorSets[op.set];
		uint32_t target = op.target;
		MVKDescriptorSetLayout* setLayout = common._layout->getDescriptorSetLayout(op.set);
		const MVKDescriptorBinding& binding = setLayout->bindings()[op.bindingIdx];
		const char* src = set->cpuBuffer + binding.cpuOffset + op.offset();
		const uint32_t* dynOffs = implicitBufferData.dynamicOffsets.data() + op.target2;
		uint32_t count = binding.isVariable() ? set->variableDescriptorCount : binding.descriptorCount;
		size_t stride = descriptorCPUSize(binding.cpuLayout);

		if (isUseResource(op.opcode)) {
			// Unlike binds, useResource can't be undone by binding something else
			// So we can store a list of which resources have been used in a bit array and use that to early exit on repeat binds
			// Some resources (e.g. multi-planar textures) can require multiple bind ops to fully bind, mark in a separate pass after all bind ops have executed
			if (bindings.descriptorSetResourceUse[op.set].get(op.bindingIdx))
				continue;
			didUseResource = true;
		}

		switch (op.opcode) {
#define CASE(x) case MVKDescriptorBindOperationCode::x: \
				executeBindOp<MVKDescriptorBindOperationCode::x>( \
					encoder, mvkEncoder, src, count, stride, target, dynOffs, useResourceStage, exists, bindings, binder); \
				break;
			CASE(BindBytes)
			CASE(BindBuffer)
			CASE(BindBufferDynamic)
			CASE(BindTexture)
			CASE(BindSampler)
			CASE(BindBufferWithLiveCheck)
			CASE(BindBufferDynamicWithLiveCheck)
			CASE(BindTextureWithLiveCheck)
			CASE(BindSamplerWithLiveCheck)
			CASE(UseResource)
			CASE(UseBufferWithLiveCheck)
			CASE(UseTextureWithLiveCheck)
#undef CASE
			case MVKDescriptorBindOperationCode::BindImmutableSampler: {
				MVKSampler*const* samplers = &setLayout->immutableSamplers()[binding.immSamplerIndex];
				for (uint32_t i = 0; i < count; i++)
					bindSampler(encoder, samplers[i]->getMTLSamplerState(), target + i, exists, bindings, binder);
				break;
			}
		}
	}

	if (didUseResource) {
		for (const MVKDescriptorBindOperation& op : ops) {
			if (isUseResource(op.opcode) && !bindings.descriptorSetResourceUse[op.set].get(op.bindingIdx))
				bindings.descriptorSetResourceUse[op.set].set(op.bindingIdx);
		}
	}
}

template <typename T, int N>
static MVKArrayRef<const T> getImplicitBindingData(const MVKSmallVector<T, N>& data, size_t limit) {
	return MVKArrayRef(data.data(), std::min(data.size(), limit));
}

static MVKResourceUsageStages getUseResourceStage(MVKMetalGraphicsStage stage) {
	// The single-stage enums are the same
	return static_cast<MVKResourceUsageStages>(stage);
}

/** Check if `add` is a subset of `current` */
static bool isCompatible(MVKResourceUsageStages current, MVKResourceUsageStages add) {
	if (current == add)
		return true;
	if (current == MVKResourceUsageStages::All)
		return true;
	return false;
}

static MVKResourceUsageStages combineStages(MVKResourceUsageStages a, MVKResourceUsageStages b) {
	if (a == b)
		return a;
	return MVKResourceUsageStages::All;
}

static void bindMetalResources(id<MTLCommandEncoder> encoder,
                               MVKCommandEncoder& mvkEncoder,
                               const MVKVulkanCommonEncoderState& common,
                               const MVKPipelineStageResourceInfo& resources,
                               const MVKImplicitBufferData& implicitBufferData,
                               const uint8_t* pushConstants,
                               MVKShaderStage vkStage,
                               MVKResourceUsageStages useResourceStage,
                               MVKStageResourceBits& exists,
                               MVKStageResourceBindings& bindings,
                               const MVKResourceBinder& RESTRICT binder) {
	// Clear descriptor set resource use bitarray for new sets.
	MVKStaticBitSet<kMVKMaxDescriptorSetCount> setsNeeded = resources.resources.descriptorSetData.clearingAllIn(exists.descriptorSetData);
	exists.descriptorSetData |= resources.resources.descriptorSetData;
	for (size_t idx : setsNeeded) {
		const MVKDescriptorSetLayout* layout = common._layout->getDescriptorSetLayout(idx);
		bindings.descriptorSetResourceUse[idx].resizeAndClear(layout->bindings().size());
	}

	// Helper commands can overwrite buffer bindings without changing descriptor set resource use.
	// Let the buffer binding cache restore argument buffers only when their bindings have changed.
	for (size_t idx : resources.resources.descriptorSetData) {
		MVKDescriptorSet* set = common._descriptorSets[idx];
		bindBuffer(encoder, set->gpuBufferObject, set->gpuBufferOffset, idx, exists, bindings, binder);
	}

	executeBindOps(encoder, mvkEncoder, common, implicitBufferData, resources.bindScript.ops.contents(), useResourceStage, exists, bindings, binder);

	MVKMetalSharedCommandEncoderState& mtlShared = mvkEncoder.getState().mtlShared();
	if (resources.usesPhysicalStorageBufferAddresses && !isCompatible(mtlShared._gpuAddressableResourceStages, useResourceStage)) {
		if (mtlShared._gpuAddressableResourceStages == MVKResourceUsageStages::None)
			mtlShared._gpuAddressableResourceStages = useResourceStage;
		else
			mtlShared._gpuAddressableResourceStages = combineStages(mtlShared._gpuAddressableResourceStages, useResourceStage);
		mvkEncoder.getDevice()->encodeGPUAddressableBuffers(mtlShared._useResource, useResourceStage);
	}

	const MVKShaderStageResourceBinding& resourceCounts = common._layout->getResourceCounts().stages[vkStage];
	for (MVKImplicitBuffer buffer : resources.implicitBuffers.needed & MVKNonVolatileImplicitBuffers) {
		assert(buffer < static_cast<MVKImplicitBuffer>(MVKNonVolatileImplicitBuffer::Count));
		MVKNonVolatileImplicitBuffer nvbuffer = static_cast<MVKNonVolatileImplicitBuffer>(buffer);
		uint32_t idx = resources.implicitBuffers.ids[buffer];
		if (exists.buffers.get(idx) && bindings.buffers[idx] == MVKStageResourceBindings::ImplicitBuffer(buffer))
			continue;
		if (bindings.implicitBufferIndices[nvbuffer] != idx) {
			// Index is changing, invalidate the old buffer since it will no longer get updated by other invalidations
			uint32_t oldIndex = bindings.implicitBufferIndices[nvbuffer];
			bindings.implicitBufferIndices[nvbuffer] = idx;
			if (bindings.buffers[oldIndex] == MVKStageResourceBindings::ImplicitBuffer(buffer))
				bindings.buffers[oldIndex] = MVKStageResourceBindings::InvalidBuffer();
		}
		exists.buffers.set(resources.implicitBuffers.ids[buffer]);
		bindings.buffers[idx] = MVKStageResourceBindings::ImplicitBuffer(buffer);
		switch (nvbuffer) {
			case MVKNonVolatileImplicitBuffer::PushConstant:
				bindImmediateData(encoder, mvkEncoder, pushConstants, common._layout->getPushConstantsLength(), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::Swizzle:
				bindImmediateData(encoder, mvkEncoder, getImplicitBindingData(implicitBufferData.textureSwizzles, resourceCounts.textureIndex), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::BufferSize:
				bindImmediateData(encoder, mvkEncoder, getImplicitBindingData(implicitBufferData.bufferSizes, resourceCounts.bufferIndex), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::DynamicOffset:
				bindImmediateData(encoder, mvkEncoder, getImplicitBindingData(implicitBufferData.dynamicOffsets, resourceCounts.dynamicOffsetBufferIndex), idx, binder);
				break;
			case MVKNonVolatileImplicitBuffer::ViewRange: {
				uint32_t viewRange[] = {
					mvkEncoder.getSubpass()->getFirstViewIndexInMetalPass(mvkEncoder.getMultiviewPassIndex()),
					mvkEncoder.getSubpass()->getViewCountInMetalPass(mvkEncoder.getMultiviewPassIndex())
				};
				binder.setBytes(encoder, viewRange, sizeof(viewRange), idx);
				break;
			}
			case MVKNonVolatileImplicitBuffer::EmulatedReversedDepthViewport:
				bindImmediateData(encoder,
				                  mvkEncoder,
				                  reinterpret_cast<const uint8_t*>(&implicitBufferData.emulatedReversedDepthViewportMask),
				                  sizeof(implicitBufferData.emulatedReversedDepthViewportMask),
				                  idx,
				                  binder);
				break;
			case MVKNonVolatileImplicitBuffer::Count:
				assert(0);
				break;
		}
	}
	for (MVKImplicitBuffer buffer : resources.implicitBuffers.needed.removingAll(MVKNonVolatileImplicitBuffers)) {
		// Mark needed volatile implicit buffers used in buffer tracking, they'll get set during the draw
		size_t idx = resources.implicitBuffers.ids[buffer];
		exists.buffers.set(idx);
		bindings.buffers[idx] = MVKStageResourceBindings::InvalidBuffer();
	}
}

/**
 * Binds resources for running Vulkan graphics commands on a Metal render command encoder.
 *
 * Binds resources in stage `vkStage` of `vkState` to stage `mtlStage` of `mtlState`.
 */
static void bindVulkanGraphicsToMetalGraphics(
  id<MTLRenderCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanGraphicsCommandEncoderState& vkState,
  const MVKVulkanSharedCommandEncoderState& vkShared,
  MVKMetalGraphicsCommandEncoderState& mtlState,
  MVKGraphicsPipeline* pipeline,
  MVKShaderStage vkStage,
  MVKMetalGraphicsStage mtlStage) {
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState,
	                   pipeline->getStageResources(vkStage),
	                   vkState._implicitBufferData[vkStage],
	                   vkShared._pushConstants.data(),
	                   vkStage,
	                   getUseResourceStage(mtlStage),
	                   mtlState._exists[mtlStage],
	                   mtlState._bindings[mtlStage],
	                   MVKResourceBinder::Get(mtlStage));
}

/**
 * Binds resources for running Vulkan graphics commands on a Metal compute command encoder.
 *
 * Binds resources in stage `vkStage` of `vkState` to `mtlState`.
 */
static void bindVulkanGraphicsToMetalCompute(
  id<MTLComputeCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanGraphicsCommandEncoderState& vkState,
  const MVKVulkanSharedCommandEncoderState& vkShared,
  MVKMetalComputeCommandEncoderState& mtlState,
  MVKGraphicsPipeline* pipeline,
  MVKShaderStage vkStage) {
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState,
	                   pipeline->getStageResources(vkStage),
	                   vkState._implicitBufferData[vkStage],
	                   vkShared._pushConstants.data(),
	                   vkStage,
	                   MVKResourceUsageStages::Compute,
	                   mtlState._exists,
	                   mtlState._bindings,
	                   MVKResourceBinder::Compute());
}

/** Binds resources for running Vulkan compute commands on a Metal compute command encoder. */
static void bindVulkanComputeToMetalCompute(
  id<MTLComputeCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanComputeCommandEncoderState& vkState,
  const MVKVulkanSharedCommandEncoderState& vkShared,
  MVKMetalComputeCommandEncoderState& mtlState,
  MVKComputePipeline* pipeline) {
	bindMetalResources(encoder,
	                   mvkEncoder,
	                   vkState,
	                   pipeline->getStageResources(),
	                   vkState._implicitBufferData,
	                   vkShared._pushConstants.data(),
	                   kMVKShaderStageCompute,
	                   MVKResourceUsageStages::Compute,
	                   mtlState._exists,
	                   mtlState._bindings,
	                   MVKResourceBinder::Compute());
}

template <bool DynamicStride>
static void bindVertexBuffersTemplate(id<MTLCommandEncoder> encoder,
                                      const MVKVulkanGraphicsCommandEncoderState& vkState,
                                      MVKStageResourceBits& exists,
                                      MVKStageResourceBindings& bindings,
                                      const MVKVertexBufferBinder& RESTRICT binder) {
	MVKGraphicsPipeline* pipeline = vkState._pipeline;
	for (size_t vkidx : pipeline->getVkVertexBuffers()) {
		const auto& buffer = vkState._vertexBuffers[vkidx];
		uint32_t idx = pipeline->getMetalBufferIndexForVertexAttributeBinding(static_cast<uint32_t>(vkidx));
		bindVertexBuffer<DynamicStride>(encoder, buffer.mtlBuffer, buffer.offset, buffer.stride,
		                                idx, exists, bindings, binder);
	}
	for (const auto& xltdBuffer : pipeline->getTranslatedVertexBindings()) {
		const auto& buffer = vkState._vertexBuffers[xltdBuffer.binding];
		uint32_t idx = pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBuffer.translationBinding);
		bindVertexBuffer<DynamicStride>(encoder, buffer.mtlBuffer, buffer.offset + xltdBuffer.translationOffset, buffer.stride,
		                                idx, exists, bindings, binder);
	}
}

static void bindVertexBuffers(id<MTLCommandEncoder> encoder,
                              const MVKVulkanGraphicsCommandEncoderState& vkState,
                              MVKStageResourceBits& exists,
                              MVKStageResourceBindings& bindings,
                              const MVKVertexBufferBinder& RESTRICT binder) {
	if (vkState._pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride))
		bindVertexBuffersTemplate<true> (encoder, vkState, exists, bindings, binder);
	else
		bindVertexBuffersTemplate<false>(encoder, vkState, exists, bindings, binder);
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKStageResourceBindings& bindings, MVKNonVolatileImplicitBuffer buffer) {
	uint32_t idx = bindings.implicitBufferIndices[buffer];
	if (bindings.buffers[idx] == MVKStageResourceBindings::ImplicitBuffer(buffer)) {
		bindings.buffers[idx] = MVKStageResourceBindings::NullBuffer();
	}
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKMetalGraphicsCommandEncoderState& state, MVKNonVolatileImplicitBuffer buffer) {
	for (uint32_t i = 0; i < static_cast<uint32_t>(MVKMetalGraphicsStage::Count); i++) {
		MVKMetalGraphicsStage stage = static_cast<MVKMetalGraphicsStage>(i);
		invalidateImplicitBuffer(state._bindings[stage], buffer);
	}
}

/** If the contents of an implicit buffer changes, call this to ensure that the contents will be rebound before the next draw. */
static void invalidateImplicitBuffer(MVKMetalComputeCommandEncoderState& state, MVKNonVolatileImplicitBuffer buffer) {
	invalidateImplicitBuffer(state._bindings, buffer);
}

/** Invalidate the implicit buffers that depend on the contents of the bound descriptor sets. */
template <typename MTLState>
static void invalidateDescriptorSetImplicitBuffers(MTLState& state) {
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::BufferSize);
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::DynamicOffset);
	invalidateImplicitBuffer(state, MVKNonVolatileImplicitBuffer::Swizzle);
}

static bool isGraphicsStage(MVKShaderStage stage) {
	return stage < kMVKShaderStageCompute;
}

#pragma mark - MVKUseResourceHelper

static constexpr MTLResourceUsage MTLResourceUsageReadWrite = MTLResourceUsageRead | MTLResourceUsageWrite;

static bool isCompatible(MVKUseResourceHelper::ResourceInfo current, MVKUseResourceHelper::ResourceInfo add) {
	if (!current.write && add.write)
		return false;
	return isCompatible(current.stages, add.stages);
}

void MVKUseResourceHelper::add(id<MTLResource> resource, MVKResourceUsageStages stage, bool write) {
	ResourceInfo info { stage, write, true };
	auto res = used.emplace(resource, info);
	if (res.second || !isCompatible(res.first->second, info)) {
		ResourceInfo& stored = res.first->second;
		if (!res.second) {
			stored.deferred = true;
			stored.write |= info.write;
			stored.stages = combineStages(stored.stages, info.stages);
		}
		entries[stored.stages].get(stored.write).push_back(resource);
	}
}

void MVKUseResourceHelper::addImmediate(id<MTLResource> resource, id<MTLCommandEncoder> enc, MVKResourceBinder::UseResource func, MVKResourceUsageStages stage, bool write) {
	ResourceInfo info { stage, write, false };
	auto res = used.emplace(resource, info);
	if (res.second || !isCompatible(res.first->second, info)) {
		ResourceInfo& stored = res.first->second;
		if (!res.second) {
			stored.write |= info.write;
			stored.stages = combineStages(stored.stages, info.stages);
		}
		// For ordering reasons, if it's deferred, we need to do this write deferred as well.
		// Otherwise a deferred useResource for a narrower usage could overwrite this one.
		// Conveniently, if it was deferred once, it must be staying alive, so no problems there.
		if (stored.deferred)
			entries[stored.stages].get(stored.write).push_back(resource);
		else
			func(enc, resource, write ? MTLResourceUsageReadWrite : MTLResourceUsageRead, stored.stages);
	}
}

void MVKUseResourceHelper::bindAndResetGraphics(id<MTLRenderCommandEncoder> encoder) {
	// If a resource is used multiple times on different stages, it may appear in multiple lists.
	// As long as the iteration order hits stages that combine multiple render stages after the stages it combines,
	// this should be OK, as the last useResource will be the one for the most comprehensive list of stages.
	for (uint32_t i = 0; i < std::size(entries.elements); i++) {
		MVKResourceUsageStages stages = static_cast<MVKResourceUsageStages>(i);
		MTLRenderStages mtlStages = getMTLStages(stages);
		Entry& entry = entries[stages];
		if (!entry.read.empty()) {
			[encoder useResources:entry.read.data() count:entry.read.size() usage:MTLResourceUsageRead stages:mtlStages];
			entry.read.clear();
		}
		if (!entry.readWrite.empty()) {
			[encoder useResources:entry.readWrite.data() count:entry.readWrite.size() usage:MTLResourceUsageReadWrite stages:mtlStages];
			entry.readWrite.clear();
		}
	}
}
void MVKUseResourceHelper::bindAndResetCompute(id<MTLComputeCommandEncoder> encoder) {
	Entry& entry = entries[MVKResourceUsageStages::Compute];
	if (!entry.read.empty()) {
		[encoder useResources:entry.read.data() count:entry.read.size() usage:MTLResourceUsageRead];
		entry.read.clear();
	}
	if (!entry.readWrite.empty()) {
		[encoder useResources:entry.readWrite.data() count:entry.readWrite.size() usage:MTLResourceUsageReadWrite];
		entry.readWrite.clear();
	}
	for (uint32_t i = 1; i < std::size(entries.elements); i++) {
		// Compute should never fill any but the first set
		assert(entries.elements[i].read.empty());
		assert(entries.elements[i].readWrite.empty());
	}
}

#pragma mark - MVKVulkanCommonCommandEncoderState

void MVKVulkanCommonEncoderState::ensurePushDescriptorSize(uint32_t size) {
	if (size > _pushDescData.size()) {
		_pushDescData.resize(size);
		_pushDescriptor.cpuBuffer = reinterpret_cast<char*>(_pushDescData.data());
	}
}

void MVKVulkanCommonEncoderState::setLayout(MVKPipelineLayout* layout) {
	_layout = layout;
	if (layout && layout->hasPushDescriptor()) {
		size_t idx = layout->pushDescriptor();
		_descriptorSets[idx] = &_pushDescriptor;
		MVKDescriptorSetLayout* dsl = layout->getDescriptorSetLayout(idx);
		uint32_t size = dsl->cpuSize();
		_pushDescriptor.cpuBufferSize = size;
		ensurePushDescriptorSize(size);
	}
}

MVKVulkanCommonEncoderState::MVKVulkanCommonEncoderState(const MVKVulkanCommonEncoderState& other) {
	memcpy(_descriptorSets, other._descriptorSets, sizeof(_descriptorSets));
	_pushDescriptor = other._pushDescriptor;
	setLayout(other._layout);
	memcpy(_pushDescriptor.cpuBuffer, other._pushDescriptor.cpuBuffer, _pushDescriptor.cpuBufferSize);
}

MVKVulkanCommonEncoderState& MVKVulkanCommonEncoderState::operator=(const MVKVulkanCommonEncoderState& other) {
	memmove(_descriptorSets, other._descriptorSets, sizeof(_descriptorSets));
	_pushDescriptor = other._pushDescriptor;
	setLayout(other._layout);
	memmove(_pushDescriptor.cpuBuffer, other._pushDescriptor.cpuBuffer, _pushDescriptor.cpuBufferSize);
	return *this;
}

#pragma mark - MVKVulkanGraphicsCommandEncoderState

MVKArrayRef<const MTLSamplePosition> MVKVulkanGraphicsCommandEncoderState::getSamplePositions() const {
	MVKArrayRef<const MTLSamplePosition> res;
	if (_pipeline) {
		if (pickRenderState(MVKRenderStateFlag::SampleLocationsEnable).enable.has(MVKRenderStateEnableFlag::SampleLocations)) {
			bool dynamic = _pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::SampleLocations);
			uint32_t count = (dynamic ? &_renderState : &_pipeline->getStaticStateData())->numSampleLocations;
			const MTLSamplePosition* samples = dynamic ? _sampleLocations : _pipeline->getSampleLocations();
			res = MVKArrayRef(samples, count);
		}
	}
	return res;
}

bool MVKVulkanGraphicsCommandEncoderState::isBresenhamLines() const {
	if (!_pipeline)
		return false;
	if (pickRenderState(MVKRenderStateFlag::LineRasterizationMode).lineRasterizationMode != MVKLineRasterizationMode::Bresenham)
		return false;

	switch (pickRenderState(MVKRenderStateFlag::PrimitiveTopology).primitiveType) {
		case MTLPrimitiveTypeLine:
		case MTLPrimitiveTypeLineStrip:
			return true;

		case MTLPrimitiveTypeTriangle:
		case MTLPrimitiveTypeTriangleStrip:
			return pickRenderState(MVKRenderStateFlag::PolygonMode).polygonMode == MVKPolygonMode::Lines;

		default:
			return false;
	}
}

void MVKVulkanGraphicsCommandEncoderState::bindDescriptorSets(
	MVKPipelineLayout* layout,
	uint32_t firstSet,
	uint32_t setCount,
	MVKDescriptorSet*const* sets,
	uint32_t dynamicOffsetCount,
	const uint32_t* dynamicOffsets)
{
	bool needsImplicitData = dynamicOffsetCount != 0;
	if (!needsImplicitData) {
		for (uint32_t i = 0; i < setCount; i++) {
			if (sets[i] && layout->getDescriptorSetLayout(firstSet + i)->argBufMode() == MVKArgumentBufferMode::Off) {
				needsImplicitData = true;
				break;
			}
		}
	}
	// Argument buffers already contain sizes and swizzles. With no dynamic
	// offsets, these sets have no per-stage implicit data to prepare.
	if (needsImplicitData) {
		for (uint32_t i = 0; i <= kMVKShaderStageFragment; i++) {
			MVKShaderStage stage = static_cast<MVKShaderStage>(i);
			::bindDescriptorSets(_implicitBufferData[stage], stage, layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
		}
	}
	for (uint32_t i = 0; i < setCount; i++) {
		_descriptorSets[firstSet + i] = sets[i];
	}
}

#pragma mark - MVKVulkanComputeCommandEncoderState

void MVKVulkanComputeCommandEncoderState::bindDescriptorSets(
	MVKPipelineLayout* layout,
	uint32_t firstSet,
	uint32_t setCount,
	MVKDescriptorSet*const* sets,
	uint32_t dynamicOffsetCount,
	const uint32_t* dynamicOffsets)
{
	::bindDescriptorSets(_implicitBufferData, kMVKShaderStageCompute, layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	for (uint32_t i = 0; i < setCount; i++) {
		_descriptorSets[firstSet + i] = sets[i];
	}
}

#pragma mark - MVKMetalGraphicsCommandEncoderState

static uint32_t getSampleCount(VkSampleCountFlags vk) {
	if (vk <= VK_SAMPLE_COUNT_1_BIT)
		return 1;
	if (vk <= VK_SAMPLE_COUNT_2_BIT)
		return 2;
	if (vk <= VK_SAMPLE_COUNT_4_BIT)
		return 4;
	static_assert(kMVKMaxSampleCount == 8, "Cases need update");
	return 8;
}

void MVKMetalGraphicsCommandEncoderState::reset(VkSampleCountFlags sampleCount) {
#if MVK_BUILD_METAL4_FOUNDATION
	_metal4ForceState = false;
	_metal4UnknownState = {};
#endif
	memset(static_cast<MVKMetalGraphicsCommandEncoderStateQuickReset*>(this), 0, offsetof(MVKMetalGraphicsCommandEncoderStateQuickReset, MEMSET_RESET_LINE));
	_lineWidth = 1;
	_sampleCount = getSampleCount(sampleCount);
	_depthStencil.reset();

	// Enabled by default in Metal.
	_flags.set(MVKMetalRenderEncoderStateFlag::PrimitiveRestartEnable, true);
	_primitiveRestartIndex = 0xFFFFFFFF;
}

void MVKMetalGraphicsCommandEncoderState::bindFragmentBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	bindBuffer(encoder, buffer, offset, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	bindBytes(encoder, data, size, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	bindTexture(encoder, texture, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindFragmentSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	bindSampler(encoder, sampler, index, _exists.fragment(), _bindings.fragment(), MVKFragmentBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexBuffer(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	bindBuffer(encoder, buffer, offset, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexBytes(id<MTLRenderCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	bindBytes(encoder, data, size, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexTexture(id<MTLRenderCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	bindTexture(encoder, texture, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}
void MVKMetalGraphicsCommandEncoderState::bindVertexSampler(id<MTLRenderCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	bindSampler(encoder, sampler, index, _exists.vertex(), _bindings.vertex(), MVKVertexBinder());
}

void MVKMetalGraphicsCommandEncoderState::changePipeline(MVKGraphicsPipeline* from, MVKGraphicsPipeline* to) {
	_flags.remove(MVKMetalRenderEncoderStateFlag::PipelineReady);
	// Everything that was static is now dirty
	if (from) {
		markDirty(from->getStaticStateFlags());
	}
	if (to)
		markDirty(to->getStaticStateFlags());
}

static constexpr MVKRenderStateFlags FlagsViewportScissor {
	MVKRenderStateFlag::Viewports,
	MVKRenderStateFlag::Scissors,
};

static constexpr MVKRenderStateFlags FlagsMetalState {
	MVKRenderStateFlag::BlendConstants,
	MVKRenderStateFlag::DepthClipEnable,
	MVKRenderStateFlag::FrontFace,
	MVKRenderStateFlag::StencilReference,
#if MVK_USE_METAL_PRIVATE_API
	MVKRenderStateFlag::LineWidth,
	MVKRenderStateFlag::ProvokingVertexMode,
#endif
};

static constexpr MVKRenderStateFlags FlagsHandledByBindStateData = FlagsViewportScissor | FlagsMetalState;

static bool shouldEmulateReversedDepthViewport(const MVKPhysicalDevice* physicalDevice) {
	return physicalDevice->shouldEmulateReversedDepthViewport();
}

void MVKMetalGraphicsCommandEncoderState::bindStateData(
  id<MTLRenderCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKRenderStateData& data,
  MVKRenderStateFlags flags,
  const VkViewport* viewports,
  const VkRect2D* scissors) {
	if (flags.hasAny(FlagsViewportScissor)) {
		if (flags.has(MVKRenderStateFlag::Viewports) &&
		  (_numViewports != data.numViewports || !mvkAreEqual(_viewports, viewports, data.numViewports))) {
			_numViewports = data.numViewports;
			mvkCopy(_viewports, viewports, data.numViewports);
			MTLViewport mtlViewports[kMVKMaxViewportScissorCount];
			uint32_t numViewports = data.numViewports;
			uint32_t emulatedReversedDepthViewportMask = 0;
			bool shouldEmulateReversedDepthViewports = shouldEmulateReversedDepthViewport(mvkEncoder.getDevice()->getPhysicalDevice());
			for (uint32_t i = 0; i < numViewports; i++) {
				mtlViewports[i].width = viewports[i].width;
				mtlViewports[i].height = viewports[i].height;
				mtlViewports[i].originX = viewports[i].x;
				mtlViewports[i].originY = viewports[i].y;
				bool isReversedDepthViewport = viewports[i].minDepth > viewports[i].maxDepth;
				// Only reversed Vulkan depth ranges are emulated. Normal depth ranges are passed to Metal unchanged.
				// The reversed range is swapped to preserve arbitrary Vulkan depth subranges after shader Z inversion.
				if (shouldEmulateReversedDepthViewports && isReversedDepthViewport) {
					emulatedReversedDepthViewportMask |= 1u << i;
					mtlViewports[i].znear = viewports[i].maxDepth;
					mtlViewports[i].zfar = viewports[i].minDepth;
				} else {
					mtlViewports[i].znear = viewports[i].minDepth;
					mtlViewports[i].zfar = viewports[i].maxDepth;
				}
			}
			mvkEncoder.getState().setGraphicsEmulatedReversedDepthViewportMask(emulatedReversedDepthViewportMask);
			if (numViewports == 1) {
				[encoder setViewport:mtlViewports[0]];
			} else {
				[encoder setViewports:mtlViewports count:numViewports];
			}
		}
		if (flags.has(MVKRenderStateFlag::Scissors) &&
		  (_numScissors != data.numScissors || !mvkAreEqual(_scissors, scissors, data.numScissors))) {
			if (!_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor) || _numScissors != data.numScissors)
				_flags.add(MVKMetalRenderEncoderStateFlag::ScissorDirty);
			_numScissors = data.numScissors;
			mvkCopy(_scissors, scissors, data.numScissors);
		}
	}

	if (flags.hasAny(FlagsMetalState)) {
		if (flags.has(MVKRenderStateFlag::BlendConstants) && !mvkAreEqual(&_blendConstants, &data.blendConstants)) {
			_blendConstants = data.blendConstants;
			const float* c = data.blendConstants.float32;
			[encoder setBlendColorRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
		}
		if (flags.has(MVKRenderStateFlag::DepthClipEnable)) {
			bool enable = data.enable.has(MVKRenderStateEnableFlag::DepthClamp);
			if (_flags.has(MVKMetalRenderEncoderStateFlag::DepthClampEnable) != enable) {
				_flags.flip(MVKMetalRenderEncoderStateFlag::DepthClampEnable);
				[encoder setDepthClipMode:enable ? MTLDepthClipModeClamp : MTLDepthClipModeClip];
			}
		}
		if (flags.has(MVKRenderStateFlag::FrontFace) && _frontFace != data.frontFace) {
			_frontFace = data.frontFace;
			[encoder setFrontFacingWinding:static_cast<MTLWinding>(data.frontFace)];
		}
		if (flags.has(MVKRenderStateFlag::StencilReference) && !mvkAreEqual(&_stencilReference, &data.stencilReference)) {
			_stencilReference = data.stencilReference;
			if (_stencilReference.frontFaceValue == _stencilReference.backFaceValue)
				[encoder setStencilReferenceValue:_stencilReference.frontFaceValue];
			else
				[encoder setStencilFrontReferenceValue:_stencilReference.frontFaceValue backReferenceValue:_stencilReference.backFaceValue];
		}
#if MVK_USE_METAL_PRIVATE_API
		if (mvkEncoder.getMVKConfig().useMetalPrivateAPI) {
			auto mvkRendEnc = static_cast<id<MVKMTLRenderCommandEncoder>>(encoder);
			if (flags.has(MVKRenderStateFlag::LineWidth) && _lineWidth != data.lineWidth) {
				_lineWidth = data.lineWidth;
				if ([mvkRendEnc respondsToSelector:@selector(setLineWidth:)]) {
					[mvkRendEnc setLineWidth:_lineWidth];
				}
			}
			if (flags.has(MVKRenderStateFlag::ProvokingVertexMode) && _provokingVertexMode != data.provokingVertexMode) {
				_provokingVertexMode = data.provokingVertexMode;
				if ([mvkRendEnc respondsToSelector:@selector(setProvokingVertexMode:)]) {
					[mvkRendEnc setProvokingVertexMode:_provokingVertexMode];
				}
			}
		}
#endif
	}
}

void MVKMetalGraphicsCommandEncoderState::bindState(
	id<MTLRenderCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vk)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	MVKRenderStateFlags staticStateFlags = pipeline->getStaticStateFlags();
	MVKRenderStateFlags dynamicStateFlags = pipeline->getDynamicStateFlags();
	MVKRenderStateFlags anyStateNeeded = (staticStateFlags | dynamicStateFlags).removingAll(_stateReady);
	const MVKRenderStateData& staticStateData = pipeline->getStaticStateData();
	const MVKRenderStateData& dynamicStateData = vk._renderState;
#define PICK_STATE(x) (dynamicStateFlags.has(MVKRenderStateFlag::x) ? &dynamicStateData : &staticStateData)
	// Handle anything that requires data from multiple (possibly different) sources out here

	// Polygon mode and primitive topology need to be handled specially, as we implement point mode by switching the primitive topology
	// Cull mode and discard both are specially handled only when using dynamic state
	// Whether cull mode discards is affected by whether we're rendering triangles, so do all of them at once
	static constexpr MVKRenderStateFlags FlagsWithSpecialHandling = {
		MVKRenderStateFlag::CullMode,
		MVKRenderStateFlag::PolygonMode,
		MVKRenderStateFlag::PrimitiveTopology,
		MVKRenderStateFlag::RasterizerDiscardEnable,
	};
	if (anyStateNeeded.hasAny(FlagsWithSpecialHandling)) {
		// Special handling, static can override dynamic due to Metal not supporting full dynamic topology
		_stateReady.addAll(FlagsWithSpecialHandling);
		uint8_t prim = PICK_STATE(PrimitiveTopology)->primitiveType;
		MVKPolygonMode fill = PICK_STATE(PolygonMode)->polygonMode;
		if (fill == MVKPolygonMode::Point) {
			MTLPrimitiveTopologyClass topologyClass = pipeline->getPrimitiveTopologyClass();
			if (topologyClass == MTLPrimitiveTopologyClassPoint || topologyClass == MTLPrimitiveTopologyClassUnspecified) {
				// Supported by pipeline, yay
				prim = MTLPrimitiveTypePoint;
			} else {
				// Not supported, lines are probably closer than fill
				fill = MVKPolygonMode::Lines;
				mvkEncoder.reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetPolygonMode(): Metal does not support setting VK_POLYGON_MODE_POINT dynamically.");
			}
		}
		_primitiveType = prim;
		bool isTriangle = prim == MTLPrimitiveTypeTriangle || prim == MTLPrimitiveTypeTriangleStrip;
		// Fill mode only affects triangles in Metal, might as well save a few API calls
		if (isTriangle && fill != _polygonMode) {
			_polygonMode = fill;
			[encoder setTriangleFillMode:static_cast<MTLTriangleFillMode>(fill)];
		}
		// Same for cull mode
		uint8_t cull = PICK_STATE(CullMode)->cullMode;
		if (isTriangle && cull != _cullMode) {
			_cullMode = cull;
			[encoder setCullMode:static_cast<MTLCullMode>(cull)];
		}

		MVKRenderStateEnableFlags dynEnable = dynamicStateData.enable;
		bool dynRasterizationDisable = isTriangle && dynamicStateFlags.has(MVKRenderStateFlag::CullMode) && dynEnable.has(MVKRenderStateEnableFlag::CullBothFaces);
		dynRasterizationDisable |= dynamicStateFlags.has(MVKRenderStateFlag::RasterizerDiscardEnable) && dynEnable.has(MVKRenderStateEnableFlag::RasterizerDiscard);
		bool staticRasterizationDisable = pipeline->isRasterizationDisabled();

		if (dynRasterizationDisable != _flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor) && !staticRasterizationDisable) {
			_flags.flip(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor);
			_flags.add(MVKMetalRenderEncoderStateFlag::ScissorDirty);
		}
	}

	// Depth stencil has many sources that all go together into one Metal DepthStencilState
	static constexpr MVKRenderStateFlags FlagsDepthStencil {
		MVKRenderStateFlag::DepthCompareOp,
		MVKRenderStateFlag::DepthTestEnable,
		MVKRenderStateFlag::DepthWriteEnable,
		MVKRenderStateFlag::StencilCompareMask,
		MVKRenderStateFlag::StencilOp,
		MVKRenderStateFlag::StencilTestEnable,
		MVKRenderStateFlag::StencilWriteMask,
	};
	if (anyStateNeeded.hasAny(FlagsDepthStencil)) {
		_stateReady.addAll(FlagsDepthStencil);
		MVKRenderSubpass* subpass = mvkEncoder.getSubpass();
		MVKMTLDepthStencilDescriptorData desc;
		if (subpass->isStencilAttachmentUsed() && PICK_STATE(StencilTestEnable)->depthStencil.stencilTestEnabled) {
			const MVKMTLDepthStencilDescriptorData& op = PICK_STATE(StencilOp)->depthStencil;
			desc.backFaceStencilData.op = op.backFaceStencilData.op;
			desc.frontFaceStencilData.op = op.frontFaceStencilData.op;
			const MVKMTLDepthStencilDescriptorData& read = PICK_STATE(StencilCompareMask)->depthStencil;
			desc.backFaceStencilData.readMask = read.backFaceStencilData.readMask;
			desc.frontFaceStencilData.readMask = read.frontFaceStencilData.readMask;
			const MVKMTLDepthStencilDescriptorData& write = PICK_STATE(StencilWriteMask)->depthStencil;
			desc.backFaceStencilData.writeMask = write.backFaceStencilData.writeMask;
			desc.frontFaceStencilData.writeMask = write.frontFaceStencilData.writeMask;
		}
		if (subpass->isDepthAttachmentUsed() && PICK_STATE(DepthTestEnable)->enable.has(MVKRenderStateEnableFlag::DepthTest)) {
			desc.depthWriteEnabled = PICK_STATE(DepthWriteEnable)->depthStencil.depthWriteEnabled;
			desc.depthCompareFunction = PICK_STATE(DepthCompareOp)->depthStencil.depthCompareFunction;
		}
		desc.simplify(true);
		if (!mvkAreEqual(&desc, &_depthStencil)) {
			_depthStencil = desc;
			[encoder setDepthStencilState:mvkEncoder.getCommandEncodingPool()->getMTLDepthStencilState(desc)];
		}
	}

	// Flags with a separate enable flag can come from two places at once
	static constexpr MVKRenderStateFlags FlagsWithEnable {
		MVKRenderStateFlag::DepthBias,
		MVKRenderStateFlag::DepthBiasEnable,
#if MVK_XCODE_26
		MVKRenderStateFlag::DepthBounds,
		MVKRenderStateFlag::DepthBoundsTestEnable,
#endif
#if MVK_USE_METAL_PRIVATE_API
		MVKRenderStateFlag::PrimitiveRestartEnable,
#endif
	};
	if (anyStateNeeded.hasAny(FlagsWithEnable)) {
		_stateReady.addAll(anyStateNeeded & FlagsWithEnable);
		if (anyStateNeeded.hasAny({ MVKRenderStateFlag::DepthBias, MVKRenderStateFlag::DepthBiasEnable })) {
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
			if (PICK_STATE(DepthBiasEnable)->enable.has(MVKRenderStateEnableFlag::DepthBias)) {
				const MVKDepthBias& src = PICK_STATE(DepthBias)->depthBias;
				if (!wasEnabled || !mvkAreEqual(&src, &_depthBias)) {
					_flags.add(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
					_depthBias = src;
					[encoder setDepthBias:src.depthBiasConstantFactor
					           slopeScale:src.depthBiasSlopeFactor
					                clamp:src.depthBiasClamp];
				}
			} else if (wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
				[encoder setDepthBias:0 slopeScale:0 clamp:0];
			}
		}
#if MVK_XCODE_26
		if (anyStateNeeded.hasAny({ MVKRenderStateFlag::DepthBounds, MVKRenderStateFlag::DepthBoundsTestEnable }) &&
		    mvkEncoder.getMetalFeatures().depthBoundsTest)
		{
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
			if (PICK_STATE(DepthBoundsTestEnable)->enable.has(MVKRenderStateEnableFlag::DepthBoundsTest)) {
				const MVKDepthBounds& src = PICK_STATE(DepthBounds)->depthBounds;
				if (!wasEnabled || !mvkAreEqual(&src, &_depthBounds)) {
					_flags.add(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
					_depthBounds = src;
					[encoder setDepthTestMinBound:src.minDepthBound maxBound:src.maxDepthBound];
				}
			} else if (wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
				[encoder setDepthTestMinBound:0.0f maxBound:1.0f];
			}
		}
#endif
#if MVK_USE_METAL_PRIVATE_API
		if (anyStateNeeded.has(MVKRenderStateFlag::PrimitiveRestartEnable) &&
		    mvkEncoder.getMVKConfig().useMetalPrivateAPI &&
		    [mvkEncoder._mtlRenderEncoder respondsToSelector:@selector(setPrimitiveRestartEnabled:index:)])
		{
			auto mvkRendEnc = static_cast<id<MVKMTLRenderCommandEncoder>>(mvkEncoder._mtlRenderEncoder);
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::PrimitiveRestartEnable);
			if (PICK_STATE(PrimitiveRestartEnable)->enable.has(MVKRenderStateEnableFlag::PrimitiveRestart)) {
				const uint32_t index = mvkPrimRestartIndexFromVkIndexType(vk._indexBuffer.vkIndexType);
				if (!wasEnabled || _primitiveRestartIndex != index) {
					_flags.add(MVKMetalRenderEncoderStateFlag::PrimitiveRestartEnable);
					_primitiveRestartIndex = index;
					[mvkRendEnc setPrimitiveRestartEnabled:true index:index];
				}
			} else if (wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::PrimitiveRestartEnable);
				[mvkRendEnc setPrimitiveRestartEnabled:false index:0xFFFFFFFF];
			}
		}
#endif
	}
#undef PICK_STATE

	// For all the things that are sourced from one place, do them in two separate calls to bindStateData
	MVKRenderStateFlags handledByBindStateData = anyStateNeeded & FlagsHandledByBindStateData;
	_stateReady.addAll(handledByBindStateData);
	if (MVKRenderStateFlags neededStatic = handledByBindStateData & staticStateFlags; !neededStatic.empty()) {
		bindStateData(encoder, mvkEncoder, staticStateData, neededStatic, pipeline->getViewports(), pipeline->getScissors());
	}
	if (MVKRenderStateFlags neededDynamic = handledByBindStateData & dynamicStateFlags; !neededDynamic.empty()) {
		bindStateData(encoder, mvkEncoder, dynamicStateData, neededDynamic, vk._viewports, vk._scissors);
	}

	// Scissor can be affected by a number of things so do it at the end
	if (_flags.has(MVKMetalRenderEncoderStateFlag::ScissorDirty)) {
		_flags.remove(MVKMetalRenderEncoderStateFlag::ScissorDirty);
		MTLScissorRect mtlScissors[kMVKMaxViewportScissorCount];
		uint32_t numScissors = _numScissors;
		if (_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor)) {
			mvkClear(mtlScissors, numScissors);
		} else {
			for (uint32_t i = 0; i < numScissors; i++)
				mtlScissors[i] = mvkMTLScissorRectFromVkRect2D(mvkEncoder.clipToRenderArea(_scissors[i]));
		}
		if (numScissors == 1) {
			[encoder setScissorRect:mtlScissors[0]];
		} else {
			[encoder setScissorRects:mtlScissors count:numScissors];
		}
	}
}

void MVKMetalGraphicsCommandEncoderState::prepareDraw(
  id<MTLRenderCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanGraphicsCommandEncoderState& vk,
  const MVKVulkanSharedCommandEncoderState& vkShared) {
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	if (!pipeline->getMainPipelineState()) // Abort if pipeline could not be created.
		return;

	// Pipeline
	if (!_flags.has(MVKMetalRenderEncoderStateFlag::PipelineReady)) {
		_flags.add(MVKMetalRenderEncoderStateFlag::PipelineReady);
		id<MTLRenderPipelineState> mtlPipeline;
		const MVKRenderSubpass* subpass = mvkEncoder.getSubpass();
		if (subpass->isMultiview() && !pipeline->isTessellationPipeline()) {
			mtlPipeline = pipeline->getMultiviewPipelineState(subpass->getViewCountInMetalPass(mvkEncoder.getMultiviewPassIndex()));
		} else {
			mtlPipeline = pipeline->getMainPipelineState();
		}
		if (mtlPipeline != _pipeline) {
			_pipeline = mtlPipeline;
			[encoder setRenderPipelineState:mtlPipeline];
		}
	}

	// State
	bindState(encoder, mvkEncoder, vk);

	// Resources
	if (pipeline->isTessellationPipeline()) {
		bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageTessEval, MVKMetalGraphicsStage::Vertex);
	} else {
		bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageVertex,   MVKMetalGraphicsStage::Vertex);
		bindVertexBuffers(encoder, vk, _exists.vertex(), _bindings.vertex(), MVKVertexBufferBinder::Vertex());
	}
	bindVulkanGraphicsToMetalGraphics(encoder, mvkEncoder, vk, vkShared, *this, pipeline, kMVKShaderStageFragment, MVKMetalGraphicsStage::Fragment);
	mvkEncoder.getState().mtlShared()._useResource.bindAndResetGraphics(encoder);
}

void MVKMetalGraphicsCommandEncoderState::prepareHelperDraw(
  id<MTLRenderCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKHelperDrawState& state) {
	_stateReady.removeAll({
		MVKRenderStateFlag::CullMode,
		MVKRenderStateFlag::DepthBiasEnable,
		MVKRenderStateFlag::DepthBoundsTestEnable,
		MVKRenderStateFlag::DepthCompareOp,
		MVKRenderStateFlag::DepthTestEnable,
		MVKRenderStateFlag::DepthWriteEnable,
		MVKRenderStateFlag::LineWidth,
		MVKRenderStateFlag::PolygonMode,
		MVKRenderStateFlag::PrimitiveRestartEnable,
		MVKRenderStateFlag::ProvokingVertexMode,
		MVKRenderStateFlag::RasterizerDiscardEnable,
		MVKRenderStateFlag::Scissors,
		MVKRenderStateFlag::StencilCompareMask,
		MVKRenderStateFlag::StencilOp,
		MVKRenderStateFlag::StencilReference,
		MVKRenderStateFlag::StencilTestEnable,
		MVKRenderStateFlag::StencilWriteMask,
		MVKRenderStateFlag::Viewports,
	});
	_flags.removeAll({
		MVKMetalRenderEncoderStateFlag::PipelineReady,
	});
	if (_pipeline != state.pipeline) {
		_pipeline = state.pipeline;
		[encoder setRenderPipelineState:state.pipeline];
	}
	if (_cullMode != MTLCullModeNone) {
		_cullMode = MTLCullModeNone;
		[encoder setCullMode:MTLCullModeNone];
	}
	if (_flags.has(MVKMetalRenderEncoderStateFlag::DepthBiasEnable)) {
		_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
		[encoder setDepthBias:0 slopeScale:0 clamp:0];
	}
	if (_polygonMode != MVKPolygonMode::Fill) {
		_polygonMode = MVKPolygonMode::Fill;
		[encoder setTriangleFillMode:MTLTriangleFillModeFill];
	}
	MVKMTLDepthStencilDescriptorData ds = MVKMTLDepthStencilDescriptorData::Write(state.writeDepth, state.writeStencil);
	if (!mvkAreEqual(&_depthStencil, &ds)) {
		_depthStencil = ds;
		[encoder setDepthStencilState:mvkEncoder.getCommandEncodingPool()->getMTLDepthStencilState(state.writeDepth, state.writeStencil)];
	}
	if (state.writeStencil && (_stencilReference.backFaceValue  != state.stencilReference
	                        || _stencilReference.frontFaceValue != state.stencilReference))
	{
		_stencilReference.backFaceValue  = state.stencilReference;
		_stencilReference.frontFaceValue = state.stencilReference;
		[encoder setStencilReferenceValue:state.stencilReference];
	}
	if (_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor)
	    || _numScissors != 1 || !mvkAreEqual(&_scissors[0], &state.viewportAndScissor))
	{
		_flags.remove(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor);
		_numScissors = 1;
		_scissors[0] = state.viewportAndScissor;
		[encoder setScissorRect:mvkMTLScissorRectFromVkRect2D(state.viewportAndScissor)];
	}
	VkViewport viewport = {
		static_cast<float>(state.viewportAndScissor.offset.x),
		static_cast<float>(state.viewportAndScissor.offset.y),
		static_cast<float>(state.viewportAndScissor.extent.width),
		static_cast<float>(state.viewportAndScissor.extent.height),
		0,
		1
	};
	if (_numViewports != 1 || !mvkAreEqual(&_viewports[0], &viewport)) {
		_numViewports = 1;
		_viewports[0] = viewport;
		[encoder setViewport:mvkMTLViewportFromVkViewport(viewport)];
	}
#if MVK_USE_METAL_PRIVATE_API
	if (mvkEncoder.getMVKConfig().useMetalPrivateAPI) {
		auto mvkRendEnc = static_cast<id<MVKMTLRenderCommandEncoder>>(encoder);
		if ((!_flags.has(MVKMetalRenderEncoderStateFlag::PrimitiveRestartEnable) || _primitiveRestartIndex != 0xFFFFFFFF)) {
			_flags.add(MVKMetalRenderEncoderStateFlag::PrimitiveRestartEnable);
			_primitiveRestartIndex = 0xFFFFFFFF;
			if ([mvkEncoder._mtlRenderEncoder respondsToSelector:@selector(setPrimitiveRestartEnabled:index:)]) {
				[mvkRendEnc setPrimitiveRestartEnabled:true index:_primitiveRestartIndex];
			}
		}
		if (_provokingVertexMode != 0) {
			_provokingVertexMode = MTLProvokingVertexModeFirst;
			if ([mvkEncoder._mtlRenderEncoder respondsToSelector:@selector(setProvokingVertexMode:)]) {
				[mvkRendEnc setProvokingVertexMode:_provokingVertexMode];
			}
		}
	}
#endif
}

#pragma mark - MVKMetalComputeCommandEncoderState


void MVKMetalComputeCommandEncoderState::bindPipeline(id<MTLComputeCommandEncoder> encoder, id<MTLComputePipelineState> pipeline) {
	_vkPipeline = nullptr;
	if (_pipeline != pipeline) {
		_pipeline = pipeline;
		[encoder setComputePipelineState:pipeline];
	}
}
void MVKMetalComputeCommandEncoderState::bindBuffer(id<MTLComputeCommandEncoder> encoder, id<MTLBuffer> buffer, VkDeviceSize offset, NSUInteger index) {
	::bindBuffer(encoder, buffer, offset, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindBytes(id<MTLComputeCommandEncoder> encoder, const void* data, size_t size, NSUInteger index) {
	::bindBytes(encoder, data, size, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindTexture(id<MTLComputeCommandEncoder> encoder, id<MTLTexture> texture, NSUInteger index) {
	::bindTexture(encoder, texture, index, _exists, _bindings, MVKComputeBinder());
}
void MVKMetalComputeCommandEncoderState::bindSampler(id<MTLComputeCommandEncoder> encoder, id<MTLSamplerState> sampler, NSUInteger index) {
	::bindSampler(encoder, sampler, index, _exists, _bindings, MVKComputeBinder());
}

void MVKMetalComputeCommandEncoderState::prepareComputeDispatch(
  id<MTLComputeCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKVulkanComputeCommandEncoderState& vk,
  const MVKVulkanSharedCommandEncoderState& vkShared) {
	MVKComputePipeline* pipeline = vk._pipeline;
	id<MTLComputePipelineState> mtlPipeline = pipeline->getPipelineState();
	if (!mtlPipeline) // Abort if pipeline could not be created.
		return;

	_vkPipeline = pipeline;

	if (_pipeline != mtlPipeline) {
		_pipeline = mtlPipeline;
		[encoder setComputePipelineState:mtlPipeline];
	}

	if (_vkStage != kMVKShaderStageCompute) {
		if (_vkStage != kMVKShaderStageCount) {
			// Switching between graphics and compute, need to invalidate implicit buffers too
			invalidateDescriptorSetImplicitBuffers(*this);
			_exists.descriptorSetData.reset();
		}
		_vkStage = kMVKShaderStageCompute;
	}

	bindVulkanComputeToMetalCompute(encoder, mvkEncoder, vk, vkShared, *this, pipeline);
	mvkEncoder.getState().mtlShared()._useResource.bindAndResetCompute(encoder);
}

void MVKMetalComputeCommandEncoderState::prepareRenderDispatch(
	id<MTLComputeCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vk,
	const MVKVulkanSharedCommandEncoderState& vkShared,
	MVKShaderStage stage)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	if (!pipeline->getMainPipelineState()) // Abort if pipeline could not be created.
		return;


	id<MTLComputePipelineState> mtlPipeline = nil;
	if (stage == kMVKShaderStageVertex) {
		if (!mvkEncoder._isIndexedDraw) {
			mtlPipeline = pipeline->getTessVertexStageState();
		} else if (vk._indexBuffer.mtlIndexType == MTLIndexTypeUInt16) {
			mtlPipeline = pipeline->getTessVertexStageIndex16State();
		} else {
			mtlPipeline = pipeline->getTessVertexStageIndex32State();
		}
	} else if (stage == kMVKShaderStageTessCtl) {
		mtlPipeline = pipeline->getTessControlStageState();
	} else {
		assert(0);
	}

	if (_vkPipeline != pipeline) {
		_vkPipeline = pipeline;
	}

	if (_pipeline != mtlPipeline) {
		_pipeline = mtlPipeline;
		[encoder setComputePipelineState:mtlPipeline];
	}

	if (_vkStage != stage) {
		if (_vkStage == kMVKShaderStageCompute) {
			// Switching between graphics and compute, need to invalidate implicit buffers too
			invalidateDescriptorSetImplicitBuffers(*this);
			_exists.descriptorSetData.reset();
		}
		_vkStage = stage;
	}

	bindVulkanGraphicsToMetalCompute(encoder, mvkEncoder, vk, vkShared, *this, pipeline, stage);
	if (stage == kMVKShaderStageVertex)
		bindVertexBuffers(encoder, vk, _exists, _bindings, MVKVertexBufferBinder::Compute());
	mvkEncoder.getState().mtlShared()._useResource.bindAndResetCompute(encoder);
}

void MVKMetalComputeCommandEncoderState::reset() {
	memset((void*)this, 0, offsetof(MVKMetalComputeCommandEncoderState, MEMSET_RESET_LINE));
	_vkStage = kMVKShaderStageCount;
}

#pragma mark - MVKCommandEncoderState

static constexpr MVKRenderStateFlags SampleLocationFlags {
	MVKRenderStateFlag::SampleLocations,
	MVKRenderStateFlag::SampleLocationsEnable,
};

static constexpr MTLSamplePosition kSampPosCenter = {0.5, 0.5};
static MTLSamplePosition kSamplePositionsAllCenter[] = { kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter, kSampPosCenter };
static_assert(sizeof(kSamplePositionsAllCenter) / sizeof(MTLSamplePosition) == kMVKMaxSampleCount, "kSamplePositionsAllCenter is not competely populated.");

static MVKArrayRef<const MTLSamplePosition> getSamplePositions(const MVKVulkanGraphicsCommandEncoderState& vk, bool locOverride, uint32_t sampleCount) {
	if (locOverride)
		return MVKArrayRef(kSamplePositionsAllCenter, sampleCount);
	return vk.getSamplePositions();
}

MVKArrayRef<const MTLSamplePosition> MVKCommandEncoderState::updateSamplePositions() {
	// Multisample Bresenham lines require sampling from the pixel center.
	bool locOverride = _mtlGraphics._sampleCount > 1 && _vkGraphics.isBresenhamLines();
	if (locOverride == _mtlGraphics._flags.has(MVKMetalRenderEncoderStateFlag::SamplePositionsOverridden) && _mtlGraphics._stateReady.hasAll(SampleLocationFlags))
		return MVKArrayRef(_mtlGraphics._samplePositions, _mtlGraphics._numSamplePositions);
	MVKArrayRef<const MTLSamplePosition> res = getSamplePositions(_vkGraphics, locOverride, _mtlGraphics._sampleCount);
	_mtlGraphics._stateReady.addAll(SampleLocationFlags);
	_mtlGraphics._flags.set(MVKMetalRenderEncoderStateFlag::SamplePositionsOverridden, locOverride);
	_mtlGraphics._numSamplePositions = res.size();
	if (res.size() > 0)
		mvkCopy(_mtlGraphics._samplePositions, res.data(), res.size());
	return res;
}

bool MVKCommandEncoderState::needsMetalRenderPassRestart() {
	// Multisample Bresenham lines require sampling from the pixel center.
	bool locOverride = _mtlGraphics._sampleCount > 1 && _vkGraphics.isBresenhamLines();
	if (locOverride == _mtlGraphics._flags.has(MVKMetalRenderEncoderStateFlag::SamplePositionsOverridden) && _mtlGraphics._stateReady.hasAll(SampleLocationFlags))
		return false;
	MVKArrayRef<const MTLSamplePosition> positions = getSamplePositions(_vkGraphics, locOverride, _mtlGraphics._sampleCount);
	size_t count = positions.size();
	bool res = count != _mtlGraphics._numSamplePositions || !mvkAreEqual(positions.data(), _mtlGraphics._samplePositions, count);
	if (!res)
		_mtlGraphics._stateReady.addAll(SampleLocationFlags);
	return res;
}

/** Used by applyToActiveMTLState to indicate that you want to apply to whichever state is active. */
static constexpr VkPipelineBindPoint VK_PIPELINE_BIND_POINT_ALL = VK_PIPELINE_BIND_POINT_MAX_ENUM;

static void invalidateImplicitBuffer(MVKCommandEncoderState& state, VkPipelineBindPoint bindPoint, MVKNonVolatileImplicitBuffer buffer) {
	state.applyToActiveMTLState(bindPoint, [buffer](auto& mtl){ invalidateImplicitBuffer(mtl, buffer); });
#if MVK_BUILD_METAL4_FOUNDATION
	state.invalidateMetal4ImplicitBuffer(bindPoint, buffer);
#endif
}

void MVKCommandEncoderState::setGraphicsEmulatedReversedDepthViewportMask(uint32_t mask) {
	bool changed = false;
	for (auto& stageData : _vkGraphics._implicitBufferData) {
		if (stageData.emulatedReversedDepthViewportMask != mask) {
			stageData.emulatedReversedDepthViewportMask = mask;
			changed = true;
		}
	}
	if (changed) {
		invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_GRAPHICS, MVKNonVolatileImplicitBuffer::EmulatedReversedDepthViewport);
	}
}

void MVKCommandEncoderState::bindGraphicsPipeline(MVKGraphicsPipeline* pipeline) {
	_mtlGraphics.changePipeline(_vkGraphics._pipeline, pipeline);
	_vkGraphics._pipeline = pipeline;
	MVKPipelineLayout* layout = pipeline->getLayout();
	if (_vkGraphics._layout != layout) {
		if (!_vkGraphics._layout || _vkGraphics._layout->getPushConstantsLength() < layout->getPushConstantsLength()) {
			mvkEnsureSize(_vkShared._pushConstants, layout->getPushConstantsLength());
			invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_GRAPHICS, MVKNonVolatileImplicitBuffer::PushConstant);
		}
		_vkGraphics.setLayout(layout);
	}
}

void MVKCommandEncoderState::bindComputePipeline(MVKComputePipeline* pipeline) {
	_vkCompute._pipeline = pipeline;
	MVKPipelineLayout* layout = pipeline->getLayout();
	if (_vkCompute._layout != layout) {
		if (!_vkCompute._layout || _vkCompute._layout->getPushConstantsLength() < layout->getPushConstantsLength()) {
			mvkEnsureSize(_vkShared._pushConstants, layout->getPushConstantsLength());
			invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_COMPUTE, MVKNonVolatileImplicitBuffer::PushConstant);
		}
		_vkCompute.setLayout(layout);
	}
}

void MVKCommandEncoderState::pushConstants(uint32_t offset, uint32_t size, const void* data) {
	mvkEnsureSize(_vkShared._pushConstants, offset + size);
	memcpy(_vkShared._pushConstants.data() + offset, data, size);
	invalidateImplicitBuffer(*this, VK_PIPELINE_BIND_POINT_ALL, MVKNonVolatileImplicitBuffer::PushConstant);
}

void MVKCommandEncoderState::bindDescriptorSets(
  VkPipelineBindPoint bindPoint,
  MVKPipelineLayout* layout,
  uint32_t firstSet,
  uint32_t setCount,
  MVKDescriptorSet*const* sets,
  uint32_t dynamicOffsetCount,
  const uint32_t* dynamicOffsets) {
	auto affected = MVKStaticBitSet<kMVKMaxDescriptorSetCount>::range(firstSet, firstSet + setCount);
#if MVK_BUILD_METAL4_FOUNDATION
	invalidateMetal4ImplicitBuffer(bindPoint, MVKNonVolatileImplicitBuffer::BufferSize);
	invalidateMetal4ImplicitBuffer(bindPoint, MVKNonVolatileImplicitBuffer::DynamicOffset);
	invalidateMetal4ImplicitBuffer(bindPoint, MVKNonVolatileImplicitBuffer::Swizzle);
#endif
	applyToActiveMTLState(bindPoint, [affected](auto& mtl){
		invalidateDescriptorSetImplicitBuffers(mtl);
		for (MVKStageResourceBits& exists : mtl.exists()) {
			exists.descriptorSetData.clearAllIn(affected);
		}
	});
	if (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS) {
		_vkGraphics.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	} else if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE) {
		_vkCompute.bindDescriptorSets(layout, firstSet, setCount, sets, dynamicOffsetCount, dynamicOffsets);
	}
}

MVKVulkanCommonEncoderState* MVKCommandEncoderState::getVkEncoderState(VkPipelineBindPoint bindPoint) {
	switch (bindPoint) {
		case VK_PIPELINE_BIND_POINT_GRAPHICS: return &_vkGraphics;
		case VK_PIPELINE_BIND_POINT_COMPUTE:  return &_vkCompute;
		default: return nullptr;
	}
}

void MVKCommandEncoderState::pushDescriptorSet(VkPipelineBindPoint bindPoint, MVKPipelineLayout* layout, uint32_t set, uint32_t writeCount, const VkWriteDescriptorSet* writes) {
	assert(layout->pushDescriptor() == set);
	if (MVKVulkanCommonEncoderState* state = getVkEncoderState(bindPoint)) [[likely]] {
		MVKDescriptorSetLayout* dsl = layout->getDescriptorSetLayout(set);
		state->ensurePushDescriptorSize(dsl->cpuSize());
		mvkPushDescriptorSet(state->_pushDescriptor.cpuBuffer, dsl, writeCount, writes);
	}
}

void MVKCommandEncoderState::pushDescriptorSet(MVKDescriptorUpdateTemplate* updateTemplate, MVKPipelineLayout* layout, uint32_t set, const void* data) {
	assert(layout->pushDescriptor() == set);
	if (MVKVulkanCommonEncoderState* state = getVkEncoderState(updateTemplate->getBindPoint())) [[likely]] {
		MVKDescriptorSetLayout* dsl = layout->getDescriptorSetLayout(set);
		state->ensurePushDescriptorSize(dsl->cpuSize());
		mvkPushDescriptorSetTemplate(state->_pushDescriptor.cpuBuffer, dsl, updateTemplate, data);
	}
}

void MVKCommandEncoderState::bindVertexBuffers(uint32_t firstBinding, MVKArrayRef<const MVKVertexMTLBufferBinding> buffers) {
	mvkCopy(&_vkGraphics._vertexBuffers[firstBinding], buffers.data(), buffers.size());
}

void MVKCommandEncoderState::bindIndexBuffer(const MVKIndexMTLBufferBinding& buffer) {
	_vkGraphics._indexBuffer = buffer;
#if MVK_USE_METAL_PRIVATE_API
	// Let state tracker know to update primitive restart config if the index type has changed.
	_mtlGraphics.markDirty(MVKRenderStateFlag::PrimitiveRestartEnable);
#endif
}

void MVKCommandEncoderState::offsetZeroDivisorVertexBuffers(MVKCommandEncoder& mvkEncoder, MVKGraphicsStage stage, MVKGraphicsPipeline* pipeline, uint32_t firstInstance) {
	for (const auto& binding : pipeline->getZeroDivisorVertexBindings()) {
		uint32_t mtlBuffIdx = pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first);
		auto& buffer = _vkGraphics._vertexBuffers[binding.first];
		switch (stage) {
			case kMVKGraphicsStageVertex:
				[mvkEncoder.getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBufferOffset: buffer.offset + firstInstance * binding.second
				                                                                                  atIndex: mtlBuffIdx];
				break;
			case kMVKGraphicsStageRasterization:
				[mvkEncoder._mtlRenderEncoder setVertexBufferOffset:buffer.offset + firstInstance * binding.second
				                                            atIndex:mtlBuffIdx];
				break;
			default:
				assert(false); // If we hit this, something went wrong.
				break;
		}
	}
}

void MVKCommandEncoderState::beginGraphicsEncoding(VkSampleCountFlags sampleCount) {
#if MVK_BUILD_METAL4_FOUNDATION
	_metal4GraphicsPipeline = nil;
	_metal4GraphicsTablesBound = false;
#endif
	_mtlGraphics.reset(sampleCount);
	_mtlShared.reset();
	_mtlActiveEncoder = CommandEncoderClass::Graphics;
}

void MVKCommandEncoderState::beginComputeEncoding() {
#if MVK_BUILD_METAL4_FOUNDATION
	invalidateMetal4ComputeBindings();
#endif
	_mtlCompute.reset();
	_mtlShared.reset();
	_mtlActiveEncoder = CommandEncoderClass::Compute;
}

template <typename Fn>
void MVKCommandEncoderState::applyToActiveMTLState(VkPipelineBindPoint bindPoint, Fn&& fn) {
	switch (_mtlActiveEncoder) {
		case CommandEncoderClass::Graphics:
			if (bindPoint != VK_PIPELINE_BIND_POINT_COMPUTE)
				std::forward<Fn>(fn)(_mtlGraphics);
			break;
		case CommandEncoderClass::Compute:
			if (bindPoint == VK_PIPELINE_BIND_POINT_COMPUTE && _mtlCompute._vkStage != kMVKShaderStageCompute)
				break;
			if (bindPoint == VK_PIPELINE_BIND_POINT_GRAPHICS && !isGraphicsStage(_mtlCompute._vkStage))
				break;
			std::forward<Fn>(fn)(_mtlCompute);
			break;
		default:
			break;
	}
}

#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

/// Used to indicate that the current metal visibility result mode needs to be set regardless of what mode is wanted
/// (when visibility queries are currently active but on the wrong index).
static constexpr uint8_t VisibilityResultModeNeedsUpdate = 0xff;

static bool isMetalVisibilityActive(uint8_t mode) {
	// return false for both Disabled and NeedsUpdate
	static_assert(static_cast<int8_t>(MTLVisibilityResultModeDisabled) <= 0);
	static_assert(static_cast<int8_t>(VisibilityResultModeNeedsUpdate) <= 0);
	static_assert(static_cast<int8_t>(MTLVisibilityResultModeBoolean)  > 0);
	static_assert(static_cast<int8_t>(MTLVisibilityResultModeCounting) > 0);
	return static_cast<int8_t>(mode) > 0;
}

struct alignas(8) QueryResultOffsets {
	uint32_t dst;
	uint32_t src;
};

// Copy native segments into the Vulkan query pool and clear consumed slots for reuse.
// Don't copy occlusion info until after rasterization, as Metal renderpasses can be ended prematurely during tessellation.
void MVKOcclusionQueryCommandEncoderState::endMetalRenderPass(MVKCommandEncoder* cmdEncoder) {
	nextMetalQuery(cmdEncoder);
	_metalVisibilityResultMode = MTLVisibilityResultModeDisabled;
	_lastFenceUpdate = nullptr;
	if (!_shouldAccumulate || _pendingQuerySegments.empty()) { return; }

	_shouldAccumulate = false;
	const MVKVisibilityBuffer& vizBuff = cmdEncoder->_pEncodingContext->visibilityResultBuffer;
	if (!vizBuff.buffer()) {
		assert(0 && "Has visibility results but no buffer to write them to");
		_pendingQuerySegments.clear();
		return;
	}

#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) { accumulateMetal4(cmdEncoder); return; }
#endif
	id<MTLComputePipelineState> mtlAccumState = cmdEncoder->getCommandEncodingPool()->getAccumulateOcclusionQueryResultsMTLComputePipelineState();
	id<MTLComputeCommandEncoder> mtlAccumEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseAccumOcclusionQuery);
	for (uint32_t i = 0; i < _numCopyFences; i++) {
		[mtlAccumEncoder waitForFence:_copyFences[i].write];
		[mtlAccumEncoder updateFence:_copyFences[i].read];
	}
	_numCopyFences = 0;
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	state.bindPipeline(mtlAccumEncoder, mtlAccumState);
	state.bindBuffer(mtlAccumEncoder, vizBuff.buffer(), 0, 2);
	static constexpr size_t max_size = 4096 / sizeof(QueryResultOffsets);
	QueryResultOffsets offsets[std::min(max_size, _pendingQuerySegments.size())];
	uint32_t idx = 0;
	uint32_t executionWidth = static_cast<uint32_t>([mtlAccumState threadExecutionWidth]);
	const auto& mtlFeats = cmdEncoder->getMetalFeatures();
	for (auto cur = _pendingQuerySegments.begin(), end = _pendingQuerySegments.end(); cur < end; cur++) {
		offsets[idx].dst = cur->query;
		offsets[idx].src = cur->visibilityBufferOffset / kMVKQuerySlotSizeInBytes;
		idx++;
		auto next = cur + 1;
		if (next == end || idx >= max_size || next->queryPool != cur->queryPool) {
			// Send what we've collected
			uint32_t count = idx;
			idx = 0;
			state.bindBuffer(mtlAccumEncoder, cur->queryPool->getVisibilityResultMTLBuffer(), 0, 1);
			MTLSize tgsize = MTLSizeMake(executionWidth, 1, 1);
			if (mtlFeats.nonUniformThreadgroups) {
				state.bindBytes(mtlAccumEncoder, offsets, count * sizeof(QueryResultOffsets), 0);
				[mtlAccumEncoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:tgsize];
			} else {
				uint32_t rest = 0;
				if (count >= executionWidth) {
					uint32_t first = count / executionWidth;
					rest = first * executionWidth;
					count -= rest;
					state.bindBytes(mtlAccumEncoder, offsets, rest * sizeof(QueryResultOffsets), 0);
					[mtlAccumEncoder dispatchThreadgroups:MTLSizeMake(first, 1, 1) threadsPerThreadgroup:tgsize];
				}
				if (count) {
					state.bindBytes(mtlAccumEncoder, offsets + rest, count * sizeof(QueryResultOffsets), 0);
					[mtlAccumEncoder dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(count, 1, 1)];
				}
			}
		}
	}
	_pendingQuerySegments.clear();
}

// A Vulkan query can span multiple native segments. Unconsumed segments keep
// their slots until accumulation, including across internal native pass splits.
void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
	assert(!_currentPool && "Shouldn't have active query when beginning a new one!");
	bool shouldCount = mvkAreAllFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
	_currentVisibilityResultMode = shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean;
	_currentPool = pQueryPool;
	_currentQueryIndex = query;
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKCommandEncoder* cmdEncoder, MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
	assert(_currentPool == pQueryPool && _currentQueryIndex == query && "Ended query that wasn't active!");
	_shouldAccumulate = true;
	bool hasRenderEncoder = cmdEncoder->_mtlRenderEncoder != nil;
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) { hasRenderEncoder = cmdEncoder->getMetal4RenderEncoder() != nil; }
#endif
	if (hasRenderEncoder) {
		nextMetalQuery(cmdEncoder);
		_metalVisibilityResultMode = VisibilityResultModeNeedsUpdate;
	} else {
		// Called outside of a render pass
		// Run accumulation immediately
		endMetalRenderPass(cmdEncoder);
	}
	_currentVisibilityResultMode = MTLVisibilityResultModeDisabled;
	_currentPool = nullptr;
}

void MVKOcclusionQueryCommandEncoderState::nextMetalQuery(MVKCommandEncoder* cmdEncoder) {
	if (!isMetalVisibilityActive(_metalVisibilityResultMode))
		return; // No draws were run
	MVKVisibilityBuffer& buffer = cmdEncoder->_pEncodingContext->visibilityResultBuffer;
	if (_pendingQuerySegments.empty() || buffer.isFirstWithCurrentFence()) {
		assert(_numCopyFences < std::size(_copyFences));
		if (_numCopyFences < std::size(_copyFences)) {
			auto current = buffer.currentFence();
			_copyFences[_numCopyFences++] = { current.read, current.write };
		}
	}
	_pendingQuerySegments.emplace_back(_currentPool, _currentQueryIndex, buffer.offset());
	buffer.advanceOffset();
	// Consume before callbacks on both backends. A full buffer can reenter this
	// method through endMetalRenderPass; don't append the segment a second time.
	_metalVisibilityResultMode = VisibilityResultModeNeedsUpdate;
	const uint32_t capacity = buffer.size() / kMVKQuerySlotSizeInBytes;
	assert(capacity && _pendingQuerySegments.size() <= capacity);
	if (_pendingQuerySegments.size() == capacity) {
		// Pending segments survive native pass boundaries. Drain before the next
		// writer reuses the oldest unread slot, regardless of where this pass began.
		_shouldAccumulate = true;
		bool hasRenderEncoder = cmdEncoder->_mtlRenderEncoder != nil;
#if MVK_BUILD_METAL4_FOUNDATION
		if (cmdEncoder->isUsingMetal4()) { hasRenderEncoder = cmdEncoder->getMetal4RenderEncoder() != nil; }
#endif
		if (hasRenderEncoder) {
			cmdEncoder->encodeStoreActions(true);
			cmdEncoder->endMetalRenderEncoding();
		}
	} else if (_numCopyFences >= 2) {
		// Accumulate at the next natural boundary before a forced split is needed.
		_shouldAccumulate = true;
	}
}

void MVKOcclusionQueryCommandEncoderState::prepareHelperDraw(MVKCommandEncoder* mvkEncoder) {
	if (_metalVisibilityResultMode == MTLVisibilityResultModeDisabled) { return; }
	nextMetalQuery(mvkEncoder);
	// Query consumption may have ended the encoder. Restart before any helper
	// state, bindings, or debug groups are applied to the new encoder.
	mvkEncoder->restartMetalRenderPassIfNeeded();
	[mvkEncoder->_mtlRenderEncoder setVisibilityResultMode:MTLVisibilityResultModeDisabled
										 offset:mvkEncoder->_pEncodingContext->visibilityResultBuffer.offset()];
	_metalVisibilityResultMode = MTLVisibilityResultModeDisabled;
}

void MVKOcclusionQueryCommandEncoderState::encode(id<MTLRenderCommandEncoder> encoder, MVKCommandEncoder* mvkEncoder) {
	auto current = static_cast<MTLVisibilityResultMode>(_currentVisibilityResultMode);
	if (_metalVisibilityResultMode == current)
		return;
	MVKVisibilityBuffer& buffer = mvkEncoder->_pEncodingContext->visibilityResultBuffer;
	_metalVisibilityResultMode = current;
	[encoder setVisibilityResultMode:current
	                          offset:buffer.offset()];
	if (current != MTLVisibilityResultModeDisabled) {
		auto fence = buffer.currentFence();
		if (_lastFenceUpdate != fence.write) {
			_lastFenceUpdate = fence.write;
			[encoder waitForFence:fence.prevRead beforeStages:MTLRenderStageFragment];
			[encoder  updateFence:fence.write     afterStages:MTLRenderStageFragment];
		}
	}
}

#if MVK_BUILD_METAL4_FOUNDATION
bool MVKOcclusionQueryCommandEncoderState::encodeMetal4(id<MTL4RenderCommandEncoder> encoder,
													 MVKCommandEncoder* mvkEncoder) {
	if (!encoder) { return metal4Failure(*mvkEncoder, "Native visibility encoder is unavailable."); }
	auto mode = static_cast<MTLVisibilityResultMode>(_currentVisibilityResultMode);
	if (_metalVisibilityResultMode == mode) { return true; }
	const auto& buffer = mvkEncoder->_pEncodingContext->visibilityResultBuffer;
	if (mode != MTLVisibilityResultModeDisabled &&
	    (!buffer.buffer() || buffer.offset() > buffer.buffer().length ||
	     kMVKQuerySlotSizeInBytes > buffer.buffer().length - buffer.offset())) {
		return metal4Failure(*mvkEncoder, "Native visibility result offset exceeds its buffer.");
	}
	[encoder setVisibilityResultMode:mode offset:buffer.offset()];
	_metalVisibilityResultMode = mode;
	if (mode != MTLVisibilityResultModeDisabled) { mvkEncoder->recordMetal4VisibilityWrite(); }
	return true;
}

bool MVKOcclusionQueryCommandEncoderState::prepareMetal4HelperDraw(MVKCommandEncoder* mvkEncoder) {
	if (_metalVisibilityResultMode != MTLVisibilityResultModeDisabled) { nextMetalQuery(mvkEncoder); }
	// Advancing a full buffer can end the pass and accumulate its contents.
	// Obtain a fresh encoder before the helper sets any render state.
	mvkEncoder->restartMetalRenderPassIfNeeded();
	auto encoder = mvkEncoder->getMetal4RenderEncoder();
	if (!encoder) { return metal4Failure(*mvkEncoder, "Native visibility helper encoder is unavailable."); }
	[encoder setVisibilityResultMode:MTLVisibilityResultModeDisabled
							 offset:mvkEncoder->_pEncodingContext->visibilityResultBuffer.offset()];
	_metalVisibilityResultMode = MTLVisibilityResultModeDisabled;
	return true;
}

void MVKOcclusionQueryCommandEncoderState::accumulateMetal4(MVKCommandEncoder* cmdEncoder) {
	auto* batch = cmdEncoder->getMetal4Submission();
	auto source = cmdEncoder->_pEncodingContext->visibilityResultBuffer.buffer();
	auto pipeline = cmdEncoder->getCommandEncodingPool()->getAccumulateOcclusionQueryResultsMTLComputePipelineState();
	// This encoder's queue barrier orders fragment visibility writes from all
	// completed render passes before Dispatch. The next render pass waits for
	// these Dispatch reads and clear writes before reusing wrapped visibility slots.
	auto encoder = cmdEncoder->getMetal4ComputeEncoder(kMVKCommandUseAccumOcclusionQuery, false, false, 0,
	                                                 MVKMetal4QueryOperation::OcclusionAccumulate);
	auto* tables = cmdEncoder->getMetal4ComputeHelperArgumentTables({3, 0, 0});
	using Stage = MVKMetal4ArgumentTables::Stage;
	bool valid = tables && encoder && source && pipeline && pipeline.threadExecutionWidth &&
		batch->addResource(source) && batch->retainObject(pipeline) &&
		tables->setBuffer(Stage::Compute, source, 0, 2);
	_numCopyFences = 0;
	if (!valid) { cmdEncoder->failMetal4Encoding("Could not retain native occlusion accumulation resources."); return; }
	[encoder setComputePipelineState:pipeline];
	static constexpr size_t maxCount = 4096 / sizeof(QueryResultOffsets);
	QueryResultOffsets offsets[maxCount];
	uint32_t count = 0;
	for (auto cur = _pendingQuerySegments.begin(), end = _pendingQuerySegments.end(); cur < end; ++cur) {
		offsets[count++] = {cur->query, static_cast<uint32_t>(cur->visibilityBufferOffset / kMVKQuerySlotSizeInBytes)};
		auto next = cur + 1;
		if (next == end || count == maxCount || next->queryPool != cur->queryPool) {
			auto destination = cur->queryPool->getVisibilityResultMTLBuffer();
			auto upload = batch->uploadBytesRange(offsets, count * sizeof(QueryResultOffsets));
			valid = destination && upload.buffer && batch->addResource(destination) &&
				tables->setBuffer(Stage::Compute, destination, 0, 1) &&
				tables->setBuffer(Stage::Compute, upload.buffer, upload.offset, 0) && tables->bindCompute(encoder);
			if (!valid) { cmdEncoder->failMetal4Encoding("Could not bind native occlusion accumulation data."); return; }
			// The existing atomic accumulation kernel has no bounds guard. Use
			// exact thread counts, including on devices without nonuniform groups.
			NSUInteger width = std::min(NSUInteger(count), pipeline.threadExecutionWidth);
			if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
				[encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
			} else {
				NSUInteger groups = count / width, remainder = count % width;
				[encoder dispatchThreadgroups:MTLSizeMake(groups, 1, 1) threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
				if (remainder) {
					if (!tables->setBuffer(Stage::Compute, upload.buffer, upload.offset + groups * width * sizeof(QueryResultOffsets), 0) || !tables->bindCompute(encoder)) {
						cmdEncoder->failMetal4Encoding("Could not bind native occlusion accumulation remainder."); return;
					}
					[encoder dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(remainder, 1, 1)];
				}
			}
			count = 0;
		}
	}
	_pendingQuerySegments.clear();
}

void MVKMetalGraphicsCommandEncoderState::bindMetal4StateData(
  id<MTL4RenderCommandEncoder> encoder,
  MVKCommandEncoder& mvkEncoder,
  const MVKRenderStateData& data,
  MVKRenderStateFlags flags,
  const VkViewport* viewports,
  const VkRect2D* scissors) {
	if (flags.hasAny(FlagsViewportScissor)) {
		if (flags.has(MVKRenderStateFlag::Viewports) &&
		  (_metal4ForceState || _numViewports != data.numViewports || !mvkAreEqual(_viewports, viewports, data.numViewports))) {
			_numViewports = data.numViewports;
			mvkCopy(_viewports, viewports, data.numViewports);
			MTLViewport mtlViewports[kMVKMaxViewportScissorCount];
			uint32_t numViewports = data.numViewports;
			uint32_t emulatedReversedDepthViewportMask = 0;
			bool shouldEmulateReversedDepthViewports = shouldEmulateReversedDepthViewport(mvkEncoder.getDevice()->getPhysicalDevice());
			for (uint32_t i = 0; i < numViewports; i++) {
				mtlViewports[i].width = viewports[i].width;
				mtlViewports[i].height = viewports[i].height;
				mtlViewports[i].originX = viewports[i].x;
				mtlViewports[i].originY = viewports[i].y;
				bool isReversedDepthViewport = viewports[i].minDepth > viewports[i].maxDepth;
				// Only reversed Vulkan depth ranges are emulated. Normal depth ranges are passed to Metal unchanged.
				// The reversed range is swapped to preserve arbitrary Vulkan depth subranges after shader Z inversion.
				if (shouldEmulateReversedDepthViewports && isReversedDepthViewport) {
					emulatedReversedDepthViewportMask |= 1u << i;
					mtlViewports[i].znear = viewports[i].maxDepth;
					mtlViewports[i].zfar = viewports[i].minDepth;
				} else {
					mtlViewports[i].znear = viewports[i].minDepth;
					mtlViewports[i].zfar = viewports[i].maxDepth;
				}
			}
			mvkEncoder.getState().setGraphicsEmulatedReversedDepthViewportMask(emulatedReversedDepthViewportMask);
			if (numViewports == 1) {
				[encoder setViewport:mtlViewports[0]];
			} else {
				[encoder setViewports:mtlViewports count:numViewports];
			}
		}
		if (flags.has(MVKRenderStateFlag::Scissors) &&
		  (_metal4ForceState || _numScissors != data.numScissors || !mvkAreEqual(_scissors, scissors, data.numScissors))) {
			if (_metal4ForceState || !_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor) || _numScissors != data.numScissors)
				_flags.add(MVKMetalRenderEncoderStateFlag::ScissorDirty);
			_numScissors = data.numScissors;
			mvkCopy(_scissors, scissors, data.numScissors);
		}
	}

	if (flags.hasAny(FlagsMetalState)) {
		if (flags.has(MVKRenderStateFlag::BlendConstants) && (_metal4ForceState || !mvkAreEqual(&_blendConstants, &data.blendConstants))) {
			_blendConstants = data.blendConstants;
			const float* c = data.blendConstants.float32;
			[encoder setBlendColorRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
		}
		if (flags.has(MVKRenderStateFlag::DepthClipEnable)) {
			bool enable = data.enable.has(MVKRenderStateEnableFlag::DepthClamp);
			if (_metal4ForceState || _flags.has(MVKMetalRenderEncoderStateFlag::DepthClampEnable) != enable) {
				_flags.set(MVKMetalRenderEncoderStateFlag::DepthClampEnable, enable);
				[encoder setDepthClipMode:enable ? MTLDepthClipModeClamp : MTLDepthClipModeClip];
			}
		}
		if (flags.has(MVKRenderStateFlag::FrontFace) && (_metal4ForceState || _frontFace != data.frontFace)) {
			_frontFace = data.frontFace;
			[encoder setFrontFacingWinding:static_cast<MTLWinding>(data.frontFace)];
		}
		if (flags.has(MVKRenderStateFlag::StencilReference) && (_metal4ForceState || !mvkAreEqual(&_stencilReference, &data.stencilReference))) {
			_stencilReference = data.stencilReference;
			if (_stencilReference.frontFaceValue == _stencilReference.backFaceValue)
				[encoder setStencilReferenceValue:_stencilReference.frontFaceValue];
			else
				[encoder setStencilFrontReferenceValue:_stencilReference.frontFaceValue backReferenceValue:_stencilReference.backFaceValue];
		}
	}
}

bool MVKMetalGraphicsCommandEncoderState::bindMetal4State(
	id<MTL4RenderCommandEncoder> encoder,
	MVKCommandEncoder& mvkEncoder,
	const MVKVulkanGraphicsCommandEncoderState& vk)
{
	MVKGraphicsPipeline* pipeline = vk._pipeline;
	MVKRenderStateFlags staticStateFlags = pipeline->getStaticStateFlags();
	MVKRenderStateFlags dynamicStateFlags = pipeline->getDynamicStateFlags();
	MVKRenderStateFlags anyStateNeeded = (staticStateFlags | dynamicStateFlags).removingAll(_stateReady);
	// Unknown fields stay unknown until a pipeline actually consumes/restores
	// them. A line, stencil-disabled or discard draw must not validate cached
	// triangle/stencil/viewport values that the helper changed behind our back.
	MVKRenderStateFlags unknownNeeded = _metal4UnknownState & (staticStateFlags | dynamicStateFlags);
	uint8_t drawPrimitive = vk.pickRenderState(MVKRenderStateFlag::PrimitiveTopology).primitiveType;
	if (vk.pickRenderState(MVKRenderStateFlag::PolygonMode).polygonMode == MVKPolygonMode::Point ||
		(drawPrimitive != MTLPrimitiveTypeTriangle && drawPrimitive != MTLPrimitiveTypeTriangleStrip)) {
		unknownNeeded.removeAll({MVKRenderStateFlag::CullMode, MVKRenderStateFlag::PolygonMode});
	}
	anyStateNeeded.addAll(unknownNeeded);
	_metal4ForceState = !unknownNeeded.empty();
	if (_metal4ForceState) {
		// Native multiview uses instance expansion, not vertex amplification.
		[encoder setVertexAmplificationCount:1 viewMappings:nullptr];
		if (_numScissors) { _flags.add(MVKMetalRenderEncoderStateFlag::ScissorDirty); }
	}
	const MVKRenderStateData& staticStateData = pipeline->getStaticStateData();
	const MVKRenderStateData& dynamicStateData = vk._renderState;
#define PICK_STATE(x) (dynamicStateFlags.has(MVKRenderStateFlag::x) ? &dynamicStateData : &staticStateData)
	// Handle anything that requires data from multiple (possibly different) sources out here

	// Polygon mode and primitive topology need to be handled specially, as we implement point mode by switching the primitive topology
	// Cull mode and discard both are specially handled only when using dynamic state
	// Whether cull mode discards is affected by whether we're rendering triangles, so do all of them at once
	static constexpr MVKRenderStateFlags FlagsWithSpecialHandling = {
		MVKRenderStateFlag::CullMode,
		MVKRenderStateFlag::PolygonMode,
		MVKRenderStateFlag::PrimitiveTopology,
		MVKRenderStateFlag::RasterizerDiscardEnable,
	};
	if (anyStateNeeded.hasAny(FlagsWithSpecialHandling)) {
		// Special handling, static can override dynamic due to Metal not supporting full dynamic topology
		_stateReady.addAll(FlagsWithSpecialHandling);
		uint8_t prim = PICK_STATE(PrimitiveTopology)->primitiveType;
		MVKPolygonMode fill = PICK_STATE(PolygonMode)->polygonMode;
		if (fill == MVKPolygonMode::Point) {
			MTLPrimitiveTopologyClass topologyClass = pipeline->getPrimitiveTopologyClass();
			if (topologyClass == MTLPrimitiveTopologyClassPoint || topologyClass == MTLPrimitiveTopologyClassUnspecified) {
				// Supported by pipeline, yay
				prim = MTLPrimitiveTypePoint;
			} else {
				// Not supported, lines are probably closer than fill
				fill = MVKPolygonMode::Lines;
				mvkEncoder.reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetPolygonMode(): Metal does not support setting VK_POLYGON_MODE_POINT dynamically.");
			}
		}
		_primitiveType = prim;
		bool isTriangle = prim == MTLPrimitiveTypeTriangle || prim == MTLPrimitiveTypeTriangleStrip;
		// Fill mode only affects triangles in Metal, might as well save a few API calls
		if (isTriangle && (_metal4ForceState || fill != _polygonMode)) {
			_polygonMode = fill;
			[encoder setTriangleFillMode:static_cast<MTLTriangleFillMode>(fill)];
		}
		// Same for cull mode
		uint8_t cull = PICK_STATE(CullMode)->cullMode;
		if (isTriangle && (_metal4ForceState || cull != _cullMode)) {
			_cullMode = cull;
			[encoder setCullMode:static_cast<MTLCullMode>(cull)];
		}

		MVKRenderStateEnableFlags dynEnable = dynamicStateData.enable;
		bool dynRasterizationDisable = isTriangle && dynamicStateFlags.has(MVKRenderStateFlag::CullMode) && dynEnable.has(MVKRenderStateEnableFlag::CullBothFaces);
		dynRasterizationDisable |= dynamicStateFlags.has(MVKRenderStateFlag::RasterizerDiscardEnable) && dynEnable.has(MVKRenderStateEnableFlag::RasterizerDiscard);
		bool staticRasterizationDisable = pipeline->isRasterizationDisabled();

		if (dynRasterizationDisable != _flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor) && !staticRasterizationDisable) {
			_flags.flip(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor);
			_flags.add(MVKMetalRenderEncoderStateFlag::ScissorDirty);
		}
	}

	// Depth stencil has many sources that all go together into one Metal DepthStencilState
	static constexpr MVKRenderStateFlags FlagsDepthStencil {
		MVKRenderStateFlag::DepthCompareOp,
		MVKRenderStateFlag::DepthTestEnable,
		MVKRenderStateFlag::DepthWriteEnable,
		MVKRenderStateFlag::StencilCompareMask,
		MVKRenderStateFlag::StencilOp,
		MVKRenderStateFlag::StencilTestEnable,
		MVKRenderStateFlag::StencilWriteMask,
	};
	if (anyStateNeeded.hasAny(FlagsDepthStencil)) {
		_stateReady.addAll(FlagsDepthStencil);
		MVKRenderSubpass* subpass = mvkEncoder.getSubpass();
		MVKMTLDepthStencilDescriptorData desc;
		if (subpass->isStencilAttachmentUsed() && PICK_STATE(StencilTestEnable)->depthStencil.stencilTestEnabled) {
			const MVKMTLDepthStencilDescriptorData& op = PICK_STATE(StencilOp)->depthStencil;
			desc.backFaceStencilData.op = op.backFaceStencilData.op;
			desc.frontFaceStencilData.op = op.frontFaceStencilData.op;
			const MVKMTLDepthStencilDescriptorData& read = PICK_STATE(StencilCompareMask)->depthStencil;
			desc.backFaceStencilData.readMask = read.backFaceStencilData.readMask;
			desc.frontFaceStencilData.readMask = read.frontFaceStencilData.readMask;
			const MVKMTLDepthStencilDescriptorData& write = PICK_STATE(StencilWriteMask)->depthStencil;
			desc.backFaceStencilData.writeMask = write.backFaceStencilData.writeMask;
			desc.frontFaceStencilData.writeMask = write.frontFaceStencilData.writeMask;
		}
		if (subpass->isDepthAttachmentUsed() && PICK_STATE(DepthTestEnable)->enable.has(MVKRenderStateEnableFlag::DepthTest)) {
			desc.depthWriteEnabled = PICK_STATE(DepthWriteEnable)->depthStencil.depthWriteEnabled;
			desc.depthCompareFunction = PICK_STATE(DepthCompareOp)->depthStencil.depthCompareFunction;
		}
		desc.simplify(true);
		if (_metal4ForceState || !mvkAreEqual(&desc, &_depthStencil)) {
			_depthStencil = desc;
			id<MTLDepthStencilState> state = mvkEncoder.getCommandEncodingPool()->getMTLDepthStencilState(desc);
			Metal4BindingSink sink { mvkEncoder, Metal4Stage::Vertex };
			if (!state || !sink.object(state)) { return metal4Failure(mvkEncoder, "Native depth-stencil state is unavailable."); }
			[encoder setDepthStencilState:state];
		}
	}

	// Flags with a separate enable flag can come from two places at once
	static constexpr MVKRenderStateFlags FlagsWithEnable {
		MVKRenderStateFlag::DepthBias,
		MVKRenderStateFlag::DepthBiasEnable,
#if MVK_XCODE_26
		MVKRenderStateFlag::DepthBounds,
		MVKRenderStateFlag::DepthBoundsTestEnable,
#endif
	};
	if (anyStateNeeded.hasAny(FlagsWithEnable)) {
		_stateReady.addAll(anyStateNeeded & FlagsWithEnable);
		if (anyStateNeeded.hasAny({ MVKRenderStateFlag::DepthBias, MVKRenderStateFlag::DepthBiasEnable })) {
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
			if (PICK_STATE(DepthBiasEnable)->enable.has(MVKRenderStateEnableFlag::DepthBias)) {
				const MVKDepthBias& src = PICK_STATE(DepthBias)->depthBias;
				if (_metal4ForceState || !wasEnabled || !mvkAreEqual(&src, &_depthBias)) {
					_flags.add(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
					_depthBias = src;
					[encoder setDepthBias:src.depthBiasConstantFactor
					           slopeScale:src.depthBiasSlopeFactor
					                clamp:src.depthBiasClamp];
				}
			} else if (_metal4ForceState || wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBiasEnable);
				[encoder setDepthBias:0 slopeScale:0 clamp:0];
			}
		}
#if MVK_XCODE_26
		if (anyStateNeeded.hasAny({ MVKRenderStateFlag::DepthBounds, MVKRenderStateFlag::DepthBoundsTestEnable }) &&
		    mvkEncoder.getMetalFeatures().depthBoundsTest)
		{
			bool wasEnabled = _flags.has(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
			if (PICK_STATE(DepthBoundsTestEnable)->enable.has(MVKRenderStateEnableFlag::DepthBoundsTest)) {
				const MVKDepthBounds& src = PICK_STATE(DepthBounds)->depthBounds;
				if (_metal4ForceState || !wasEnabled || !mvkAreEqual(&src, &_depthBounds)) {
					_flags.add(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
					_depthBounds = src;
					[encoder setDepthTestMinBound:src.minDepthBound maxBound:src.maxDepthBound];
				}
			} else if (_metal4ForceState || wasEnabled) {
				_flags.remove(MVKMetalRenderEncoderStateFlag::DepthBoundsEnable);
				[encoder setDepthTestMinBound:0.0f maxBound:1.0f];
			}
		}
#endif
	}
#undef PICK_STATE

	// For all the things that are sourced from one place, do them in two separate calls to bindStateData
	MVKRenderStateFlags handledByBindStateData = anyStateNeeded & FlagsHandledByBindStateData;
	_stateReady.addAll(handledByBindStateData);
	if (MVKRenderStateFlags neededStatic = handledByBindStateData & staticStateFlags; !neededStatic.empty()) {
		bindMetal4StateData(encoder, mvkEncoder, staticStateData, neededStatic, pipeline->getViewports(), pipeline->getScissors());
	}
	if (MVKRenderStateFlags neededDynamic = handledByBindStateData & dynamicStateFlags; !neededDynamic.empty()) {
		bindMetal4StateData(encoder, mvkEncoder, dynamicStateData, neededDynamic, vk._viewports, vk._scissors);
	}

	// Scissor can be affected by a number of things so do it at the end
	if (_flags.has(MVKMetalRenderEncoderStateFlag::ScissorDirty)) {
		_flags.remove(MVKMetalRenderEncoderStateFlag::ScissorDirty);
		MTLScissorRect mtlScissors[kMVKMaxViewportScissorCount];
		uint32_t numScissors = _numScissors;
		if (_flags.has(MVKMetalRenderEncoderStateFlag::RasterizationDisabledByScissor)) {
			mvkClear(mtlScissors, numScissors);
		} else {
			for (uint32_t i = 0; i < numScissors; i++)
				mtlScissors[i] = mvkMTLScissorRectFromVkRect2D(mvkEncoder.clipToRenderArea(_scissors[i]));
		}
		if (numScissors == 1) {
			[encoder setScissorRect:mtlScissors[0]];
		} else {
			[encoder setScissorRects:mtlScissors count:numScissors];
		}
	}
	MVKRenderStateFlags restored = anyStateNeeded;
	if (_primitiveType != MTLPrimitiveTypeTriangle && _primitiveType != MTLPrimitiveTypeTriangleStrip) {
		restored.removeAll({MVKRenderStateFlag::CullMode, MVKRenderStateFlag::PolygonMode});
	}
	_metal4UnknownState.removeAll(restored);
	_metal4ForceState = false;
	return true;
}


#endif
