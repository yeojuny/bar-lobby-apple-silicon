/*
 * MVKCmdDraw.mm
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

#include "MVKCmdDraw.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKBuffer.h"
#include "MVKDeviceMemory.h"
#include "MVKImage.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"
#if MVK_BUILD_METAL4_FOUNDATION
#include "MVKMetal4ArgumentTable.h"
#include "MVKMetal4Submission.h"
#include "MVKMetal4PrimitiveBatch.h"

static bool bindMetal4DrawID(MVKCommandEncoder* encoder, MVKGraphicsPipeline* pipeline, uint32_t drawID) {
	if (!pipeline->needsDrawIdBuffer()) { return true; }
	NSError* error = nil;
	auto upload = encoder->getMetal4Submission()->uploadBytesRange(&drawID, sizeof(drawID), &error);
	if (!upload.buffer || !encoder->getMetal4ArgumentTables()->setBuffer(MVKMetal4ArgumentTables::Stage::Vertex,
	    upload.buffer, upload.offset, pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId], &error)) {
		encoder->failMetal4Encoding("Native draw-ID upload failed."); return false;
	}
	return true;
}

static void recordMetal4Draw(MVKCommandEncoder* encoder, bool indirect) {
	if (auto* stats = encoder->getMetal4EncodingStats()) {
		++stats->drawCalls;
		stats->indirectDrawCalls += indirect;
		auto* pipeline = encoder->getGraphicsPipeline();
		if (!pipeline) { ++stats->invariantUnsupportedDraws; return; }
		pipeline->recordMetal4InvariantDrawUse();
		switch (pipeline->metal4InvariantGate()) {
			case MVKMetal4InvariantGate::NoFlat: ++stats->invariantNoFlatDraws; break;
			case MVKMetal4InvariantGate::Admitted: ++stats->invariantAdmittedDraws; break;
			case MVKMetal4InvariantGate::ExternalWrites: ++stats->invariantExternalWritesDraws; break;
			case MVKMetal4InvariantGate::Builtins: ++stats->invariantBuiltinsDraws; break;
			case MVKMetal4InvariantGate::Layout: ++stats->invariantLayoutDraws; break;
			case MVKMetal4InvariantGate::ProofRejected: ++stats->invariantProofRejectedDraws; break;
			default: ++stats->invariantUnsupportedDraws; break;
		}
	}
}

// Vulkan and Metal's ordinary indirect records carry the same GPU-produced
// values. Do not read or rewrite them on the CPU: the producer may still run.
static_assert(sizeof(VkDrawIndirectCommand) == sizeof(MTLDrawPrimitivesIndirectArguments));
static_assert(offsetof(VkDrawIndirectCommand, vertexCount) == offsetof(MTLDrawPrimitivesIndirectArguments, vertexCount));
static_assert(offsetof(VkDrawIndirectCommand, instanceCount) == offsetof(MTLDrawPrimitivesIndirectArguments, instanceCount));
static_assert(offsetof(VkDrawIndirectCommand, firstVertex) == offsetof(MTLDrawPrimitivesIndirectArguments, vertexStart));
static_assert(offsetof(VkDrawIndirectCommand, firstInstance) == offsetof(MTLDrawPrimitivesIndirectArguments, baseInstance));
static_assert(sizeof(VkDrawIndexedIndirectCommand) == sizeof(MTLDrawIndexedPrimitivesIndirectArguments));
static_assert(offsetof(VkDrawIndexedIndirectCommand, indexCount) == offsetof(MTLDrawIndexedPrimitivesIndirectArguments, indexCount));
static_assert(offsetof(VkDrawIndexedIndirectCommand, instanceCount) == offsetof(MTLDrawIndexedPrimitivesIndirectArguments, instanceCount));
static_assert(offsetof(VkDrawIndexedIndirectCommand, firstIndex) == offsetof(MTLDrawIndexedPrimitivesIndirectArguments, indexStart));
static_assert(offsetof(VkDrawIndexedIndirectCommand, vertexOffset) == offsetof(MTLDrawIndexedPrimitivesIndirectArguments, baseVertex));
static_assert(offsetof(VkDrawIndexedIndirectCommand, firstInstance) == offsetof(MTLDrawIndexedPrimitivesIndirectArguments, baseInstance));

struct Metal4PrimitiveConversion {
	// provokingLast bit0: LAST rotation; bit1: a second original-index result.
	uint32_t topology, indexBytes, provokingLast, outputCapacity;
	uint64_t inputCapacity;
	uint32_t instanceMultiplier, threadStride;
};
static_assert(sizeof(Metal4PrimitiveConversion) == 32 && offsetof(Metal4PrimitiveConversion, inputCapacity) == 16);
static_assert(VK_PRIMITIVE_TOPOLOGY_POINT_LIST == 0 && VK_PRIMITIVE_TOPOLOGY_LINE_LIST == 1 &&
	VK_PRIMITIVE_TOPOLOGY_LINE_STRIP == 2 && VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST == 3 &&
	VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP == 4 && VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN == 5);

using Metal4ConvertedDraw = MVKMetal4ConvertedDraw;

static uint32_t metal4IndexBytes(const MVKIndexMTLBufferBinding* binding) {
	if (!binding) { return 0; }
	switch (binding->vkIndexType) {
		case VK_INDEX_TYPE_UINT8: return 1;
		case VK_INDEX_TYPE_UINT16: return 2;
		case VK_INDEX_TYPE_UINT32: return 4;
		default: return 0;
	}
}

MVKMetal4PrimitiveState::MVKMetal4PrimitiveState(MVKGraphicsPipeline* p, const MVKRenderStateData& dynamic) : pipeline(p) {
    if (!pipeline) { return; }
    auto pick = [&](MVKRenderStateFlag flag) -> const MVKRenderStateData& {
        return pipeline->getDynamicStateFlags().has(flag) ? dynamic : pipeline->getStaticStateData();
    };
    topology = pick(MVKRenderStateFlag::PrimitiveTopology).vkPrimitiveTopology;
    restart = pick(MVKRenderStateFlag::PrimitiveRestartEnable).enable.has(MVKRenderStateEnableFlag::PrimitiveRestart);
    provokingLast = pick(MVKRenderStateFlag::ProvokingVertexMode).provokingVertexMode != 0;
    polygonPoint = pick(MVKRenderStateFlag::PolygonMode).polygonMode == MVKPolygonMode::Point;
}

bool MVKMetal4PrimitiveState::needsConversion(const MVKIndexMTLBufferBinding* indices) const {
    bool strip = topology == VK_PRIMITIVE_TOPOLOGY_LINE_STRIP || topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    return topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN ||
        (indices && (indices->vkIndexType == VK_INDEX_TYPE_UINT8 || restart != strip)) ||
        (provokingLast && pipeline->metal4UsesProvokingVertex() && topology != VK_PRIMITIVE_TOPOLOGY_POINT_LIST);
}

static bool metal4NeedsPrimitiveConversion(MVKCommandEncoder* encoder, const MVKIndexMTLBufferBinding* indices) {
    auto& state = encoder->getVkGraphics();
    return MVKMetal4PrimitiveState(state._pipeline, state._renderState).needsConversion(indices);
}

static bool metal4CanSelectOriginalIndices(const MVKMetal4PrimitiveState& state, uint32_t indexBytes) {
    bool list = state.topology == VK_PRIMITIVE_TOPOLOGY_POINT_LIST ||
        state.topology == VK_PRIMITIVE_TOPOLOGY_LINE_LIST || state.topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    return state.restart && list && (indexBytes == 2 || indexBytes == 4) &&
        (!state.provokingLast || state.topology == VK_PRIMITIVE_TOPOLOGY_POINT_LIST ||
         !state.pipeline->metal4UsesProvokingVertex());
}

static uint64_t metal4PrimitiveCount(uint64_t count, uint32_t topology) {
	switch (topology) {
		case 0: return count;
		case 1: return count / 2;
		case 2: return count > 1 ? count - 1 : 0;
		case 3: return count / 3;
		default: return count > 2 ? count - 2 : 0;
	}
}

static bool metal4FusedRestartEnabled() {
	// Private experiment, fixed for this process. Ordinary launches continue
	// using the original kernel; no capability or product setting is changed.
	static const bool enabled = [] {
		const char* value = std::getenv("MVK_CONFIG_METAL4_FUSED_RESTART");
		return value && std::strcmp(value, "1") == 0;
	}();
	return enabled;
}

// Produce one GPU indirect record plus list indices. For indexed indirect
// draws, maxInputCount comes from the bound index range, never CPU-read args.
// Scratch can be reused across draws: getMetal4ComputeEncoder waits for all
// previous queue stages, and the following render pass waits for this dispatch.
static bool convertMetal4Primitives(MVKCommandEncoder* encoder, id<MTLBuffer> arguments,
		uint64_t argumentOffset, const MVKIndexMTLBufferBinding* indices, uint64_t maxInputCount,
		uint32_t instanceMultiplier, Metal4ConvertedDraw& output, bool indirectArguments = false, const MVKMetal4PrimitiveState* planned = nullptr, bool independentConversion = false) {
	auto fail = [&](const char* message) { encoder->failMetal4Encoding(message); return false; };
	auto state = planned ? *planned : MVKMetal4PrimitiveState(encoder->getVkGraphics()._pipeline, encoder->getVkGraphics()._renderState);
	uint32_t topology = state.topology, indexBytes = metal4IndexBytes(indices);
	if (state.polygonPoint &&
	    topology != VK_PRIMITIVE_TOPOLOGY_POINT_LIST) {
		return fail("Native polygon-point primitive conversion is not integrated.");
	}
	if (topology > VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN || !state.pipeline || state.pipeline->isTessellationPipeline() ||
	    !arguments || argumentOffset > arguments.length || sizeof(VkDrawIndexedIndirectCommand) > arguments.length - argumentOffset ||
	    (argumentOffset & 3) || !instanceMultiplier || (indices && !indexBytes)) {
		return fail("Native primitive conversion arguments/topology are unsupported or invalid.");
	}
	uint64_t inputCapacity = maxInputCount;
	if (indices) {
		if (!indices->mtlBuffer || indices->offset > indices->mtlBuffer.length || indices->offset % indexBytes) {
			return fail("Native primitive conversion index range is invalid.");
		}
		inputCapacity = std::min(uint64_t(indices->size), uint64_t(indices->mtlBuffer.length - indices->offset)) / indexBytes;
		if (maxInputCount > inputCapacity) { return fail("Native primitive conversion exceeds the bound index range."); }
	}
	uint32_t primitiveSize = topology == 0 ? 1 : topology < 3 ? 2 : 3;
	uint64_t primitiveCount = metal4PrimitiveCount(maxInputCount, topology);
	uint64_t capacity = std::max(uint64_t(1), primitiveCount * primitiveSize);
	if (maxInputCount > UINT32_MAX || capacity > UINT32_MAX || capacity > encoder->getMTLDevice().maxBufferLength / sizeof(uint32_t)) {
		return fail("Native primitive conversion scratch exceeds device/indirect count limits.");
	}
	bool restart = indices && state.restart;
	// Preserve the separate opt-in fused experiment and its original result ABI.
	bool fusedRestart = restart && !indirectArguments &&
		topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST &&
		(indexBytes == 2 || indexBytes == 4) && maxInputCount >= 2048 && metal4FusedRestartEnabled();
	bool selectOriginal = indices && !fusedRestart && metal4CanSelectOriginalIndices(state, indexBytes);
	uint32_t resultRecords = selectOriginal ? 2 : 1;
	bool allocatedScratch = !output.indices;
	if (allocatedScratch) {
		output.capacity = uint32_t(capacity);
		output.indices = encoder->getTempMTLBuffer(capacity * sizeof(uint32_t), true);
		output.arguments = encoder->getTempMTLBuffer(resultRecords * sizeof(MTLDrawIndexedPrimitivesIndirectArguments), true);
		output.argumentRecords = resultRecords;
	}
	if (!output.indices || !output.arguments || capacity > output.capacity || resultRecords > output.argumentRecords ||
	    !output.indices->_mtlBuffer || !output.arguments->_mtlBuffer) { return fail("Native primitive conversion scratch allocation failed."); }
	output.primitive = topology == 0 ? MTLPrimitiveTypePoint : topology < 3 ? MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle;
	output.originalIndexAddress = 0;
	if (selectOriginal) {
		uint64_t address = indices->mtlBuffer.gpuAddress;
		if (!address || indices->offset > UINT64_MAX - address ||
		    inputCapacity * indexBytes > UINT64_MAX - address - indices->offset) {
			return fail("Native original-index address overflows.");
		}
		output.originalIndexAddress = address + indices->offset;
		output.originalIndexLength = inputCapacity * indexBytes;
		output.originalIndexType = indexBytes == 2 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
	}
	bool renderWasActive = encoder->getMetal4RenderEncoder() != nil;
	auto* batch = encoder->getMetal4Submission();
	auto compute = encoder->getMetal4ComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers, independentConversion);
	auto pipeline = encoder->getCommandEncodingPool()->getMetal4PrimitiveConversionMTLComputePipelineState(restart, fusedRestart);
	if (!compute || !pipeline || !pipeline.threadExecutionWidth || !pipeline.maxTotalThreadsPerThreadgroup) { return fail("Native primitive conversion pipeline is unavailable."); }
	// Indirect draw counts live on the GPU. Dispatch a bounded grid and let each
	// thread process its strided share of the actual count instead of launching
	// one thread for every primitive the entire bound index buffer could hold.
	constexpr NSUInteger maxThreads = 8192;
	NSUInteger threads = restart ? std::min(uint64_t(256), std::max(uint64_t(1), maxInputCount))
		: std::min(uint64_t(maxThreads), std::max(uint64_t(1), primitiveCount));
	NSUInteger width = std::min(threads, restart ? pipeline.maxTotalThreadsPerThreadgroup : pipeline.threadExecutionWidth);
	// The restart kernel uses one group so its sentinel decision needs only a
	// threadgroup barrier, without another dispatch, buffer, or queue barrier.
	NSUInteger groups = restart ? 1 : std::min((threads + width - 1) / width, maxThreads / width);
	Metal4PrimitiveConversion parameters {topology, indexBytes, uint32_t(state.provokingLast) | (selectOriginal ? 2u : 0u),
		output.capacity, inputCapacity, instanceMultiplier, uint32_t(groups * width)};
	auto upload = batch->uploadBytesRangeWithPrimitiveInputs(&parameters, sizeof(parameters),
		pipeline, arguments, indices ? indices->mtlBuffer : nil);
	auto* tables = encoder->getMetal4PrimitiveConversionArgumentTables();
	using Stage = MVKMetal4ArgumentTables::Stage;
	bool valid = upload.buffer && tables &&
		tables->setBuffer(Stage::Compute, indices ? indices->mtlBuffer : arguments, indices ? indices->offset : argumentOffset, 0) &&
		tables->setBuffer(Stage::Compute, arguments, argumentOffset, 1) &&
		tables->setBuffer(Stage::Compute, output.indices->_mtlBuffer, output.indices->_offset, 2) &&
		tables->setBuffer(Stage::Compute, output.arguments->_mtlBuffer, output.arguments->_offset, 3) &&
		tables->setBuffer(Stage::Compute, upload.buffer, upload.offset, 4) && tables->bindCompute(compute);
	if (!valid) { return fail("Native primitive conversion pipeline/binding failed."); }
	[compute setComputePipelineState:pipeline];
	[compute dispatchThreadgroups:MTLSizeMake(groups, 1, 1) threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
	if (auto* stats = encoder->getMetal4EncodingStats()) {
		bool strip = topology == VK_PRIMITIVE_TOPOLOGY_LINE_STRIP || topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
		bool fan = topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN;
		++stats->converted;
		stats->provokingVertex += state.provokingLast && state.pipeline->metal4UsesProvokingVertex() && topology != VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
		stats->listRestart += restart && !strip && !fan;
		stats->stripRestart += indices && strip && !restart;
		stats->fan += fan;
		stats->uint8Indices += indexBytes == 1;
		stats->restartKernelCalls += restart;
		stats->fusedRestartKernelCalls += fusedRestart;
		stats->maxInputCountSum += maxInputCount;
		stats->maxInputCountMax = std::max(stats->maxInputCountMax, maxInputCount);
		if (indirectArguments) { stats->indirectBoundCountSum += maxInputCount; }
		else { stats->directInputCountSum += maxInputCount; }
		if (allocatedScratch) { stats->scratchBytes += capacity * sizeof(uint32_t) + resultRecords * sizeof(MTLDrawIndexedPrimitivesIndirectArguments); }
		stats->renderWasActive += renderWasActive;
	}
	return true;
}

// Each threadgroup consumes one immutable record. GPU addresses name only
// buffers retained/resident in the current submission, never host pointers.
struct alignas(8) Metal4RestartBatchRecord {
    uint64_t indexAddress, sourceAddress, outputAddress, resultAddress;
    Metal4PrimitiveConversion parameters;
};
static_assert(sizeof(Metal4RestartBatchRecord) == 64 && alignof(Metal4RestartBatchRecord) == 8 &&
    offsetof(Metal4RestartBatchRecord, parameters) == 32);

static bool metal4CanBatchRestart(const MVKMetal4DrawPlanState::Entry& entry) {
    auto bytes = metal4IndexBytes(&entry.index);
    return mvkMetal4PrimitiveBatch::eligible(entry.indexed, entry.primitive.topology,
        entry.primitive.restart, entry.primitive.polygonPoint, bytes);
}

static NSUInteger metal4RestartWidth(const MVKMetal4DrawPlanState::Entry& entry, NSUInteger maxThreads) {
    return mvkMetal4PrimitiveBatch::width(entry.arguments.indexCount, maxThreads);
}

static bool metal4PrimitiveAddress(id<MTLBuffer> buffer, uint64_t offset, uint64_t length,
                                   uint64_t alignment, uint64_t& address) {
    if (!buffer || offset > buffer.length || length > buffer.length - offset) { return false; }
    uint64_t base = buffer.gpuAddress;
    if (!base || offset > UINT64_MAX - base) { return false; }
    address = base + offset;
    return !(address % alignment) && length <= UINT64_MAX - address;
}

static bool convertMetal4RestartBatch(MVKCommandEncoder* encoder,
        const std::vector<MVKMetal4DrawPlanState::Entry>& entries, size_t first, size_t count,
        NSUInteger width, id<MTLComputePipelineState> pipeline, std::vector<Metal4ConvertedDraw>& outputs) {
    auto fail = [&](const char* message) { encoder->failMetal4Encoding(message); return false; };
    if (first > entries.size() || count > entries.size() - first || count < 2 || count > 256 ||
        !width || !pipeline || width > pipeline.maxTotalThreadsPerThreadgroup) {
        return fail("Native restart batch shape is invalid.");
    }
    auto* batch = encoder->getMetal4Submission();
    MVKSmallVector<VkDrawIndexedIndirectCommand, 4> arguments;
    MVKSmallVector<Metal4RestartBatchRecord, 4> records(count);
    arguments.reserve(count); outputs.resize(count);
    for (size_t i = 0; i < count; ++i) {
        const auto& entry = entries[first + i];
        uint32_t bytes = metal4IndexBytes(&entry.index);
        if (!metal4CanBatchRestart(entry) || !entry.index.mtlBuffer ||
            entry.index.offset > entry.index.mtlBuffer.length || entry.index.offset % bytes) {
            return fail("Native restart batch input is invalid.");
        }
        uint64_t inputCapacity = std::min(uint64_t(entry.index.size), uint64_t(entry.index.mtlBuffer.length - entry.index.offset)) / bytes;
        if (entry.arguments.firstIndex > inputCapacity || entry.arguments.indexCount > inputCapacity - entry.arguments.firstIndex) {
            return fail("Native restart batch exceeds the bound index range.");
        }
        uint32_t topology = entry.primitive.topology, capacity;
        if (!mvkMetal4PrimitiveBatch::capacity(topology, entry.arguments.indexCount,
                encoder->getMTLDevice().maxBufferLength, capacity)) {
            return fail("Native restart batch scratch exceeds the device limit.");
        }
        auto& output = outputs[i];
        output.capacity = capacity;
        output.primitive = topology == 0 ? MTLPrimitiveTypePoint : topology < 3 ? MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle;
        bool selectOriginal = metal4CanSelectOriginalIndices(entry.primitive, bytes);
        output.argumentRecords = selectOriginal ? 2 : 1;
        output.indices = encoder->getTempMTLBuffer(capacity * sizeof(uint32_t), true);
        output.arguments = encoder->getTempMTLBuffer(output.argumentRecords * sizeof(MTLDrawIndexedPrimitivesIndirectArguments), true);
        if (!output.indices || !output.arguments ||
            !metal4PrimitiveAddress(entry.index.mtlBuffer, entry.index.offset, inputCapacity * bytes, bytes, records[i].indexAddress) ||
            !metal4PrimitiveAddress(output.indices->_mtlBuffer, output.indices->_offset, capacity * sizeof(uint32_t), 4, records[i].outputAddress) ||
            !metal4PrimitiveAddress(output.arguments->_mtlBuffer, output.arguments->_offset, output.argumentRecords * sizeof(MTLDrawIndexedPrimitivesIndirectArguments), 4, records[i].resultAddress)) {
            return fail("Native restart batch scratch/address allocation failed.");
        }
        // Temp output leases already register their buffers and survive through
        // retirement. Explicitly own every input addressed indirectly by a record.
        if (!batch->addResource(entry.index.mtlBuffer)) { return fail("Native restart batch input registration failed."); }
        if (selectOriginal) {
            output.originalIndexAddress = records[i].indexAddress;
            output.originalIndexLength = inputCapacity * bytes;
            output.originalIndexType = bytes == 2 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
        }
        records[i].parameters = {topology, bytes, uint32_t(entry.primitive.provokingLast) | (selectOriginal ? 2u : 0u),
                                  output.capacity, inputCapacity, 1, uint32_t(width)};
        arguments.push_back(entry.arguments);
    }
    // Both uploads are immutable submission-owned arena slices. Every record's
    // sourceAddress includes its direct argument-array element offset exactly once.
    auto args = batch->uploadBytesRange(arguments.data(), arguments.size() * sizeof(arguments[0]));
    if (!args.buffer) { return fail("Native restart batch argument upload failed."); }
    for (size_t i = 0; i < count; ++i) {
        if (i * sizeof(arguments[0]) > UINT64_MAX - args.offset ||
            !metal4PrimitiveAddress(args.buffer, args.offset + i * sizeof(arguments[0]), sizeof(arguments[0]), 4, records[i].sourceAddress)) {
            return fail("Native restart batch argument address is invalid.");
        }
    }
    auto recordUpload = batch->uploadBytesRange(records.data(), records.size() * sizeof(records[0]));
    uint64_t recordAddress;
    if (!recordUpload.buffer || !metal4PrimitiveAddress(recordUpload.buffer, recordUpload.offset,
        records.size() * sizeof(records[0]), alignof(Metal4RestartBatchRecord), recordAddress) || !batch->retainObject(pipeline)) {
        return fail("Native restart batch record upload/pipeline retention failed.");
    }
    auto compute = encoder->getMetal4ComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
    auto* tables = encoder->getMetal4ComputeHelperArgumentTables({1, 0, 0});
    if (!compute || !tables || !tables->setBuffer(MVKMetal4ArgumentTables::Stage::Compute,
            recordUpload.buffer, recordUpload.offset, 0) || !tables->bindCompute(compute)) {
        return fail("Native restart batch binding failed.");
    }
    [compute setComputePipelineState:pipeline];
    [compute dispatchThreadgroups:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
    if (auto* stats = encoder->getMetal4EncodingStats()) {
        ++stats->restartKernelCalls; ++stats->batchedRestartDispatches;
        stats->batchedRestartDraws += count;
        for (size_t i = 0; i < count; ++i) {
            const auto& entry = entries[first + i];
            uint32_t topology = entry.primitive.topology;
            bool strip = topology == VK_PRIMITIVE_TOPOLOGY_LINE_STRIP || topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
            bool fan = topology == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN;
            ++stats->converted;
            stats->listRestart += !strip && !fan;
            stats->fan += fan;
            stats->uint8Indices += metal4IndexBytes(&entry.index) == 1;
            stats->provokingVertex += entry.primitive.provokingLast && entry.primitive.pipeline->metal4UsesProvokingVertex() &&
                topology != VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
            stats->maxInputCountSum += entry.arguments.indexCount;
            stats->maxInputCountMax = std::max(stats->maxInputCountMax, uint64_t(entry.arguments.indexCount));
            stats->directInputCountSum += entry.arguments.indexCount;
            stats->scratchBytes += uint64_t(outputs[i].capacity) * sizeof(uint32_t) +
                outputs[i].argumentRecords * sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
        }
    }
    return true;
}

bool MVKCommandEncoder::metal4CanPreconvertIndices(const MVKIndexMTLBufferBinding& binding) {
    return binding.mtlBuffer && metal4CanPreconvertBuffer(binding.sourceBuffer);
}

bool MVKCommandEncoder::metal4CanPreconvertBuffer(MVKBuffer* buffer) {
    if (!buffer || !buffer->getDeviceMemory() || !buffer->getDeviceMemory()->isMetal4KnownInternalAllocation()) { return false; }
    // Check all authoritative attachments, including resolve targets. Whole
    // allocation exclusion deliberately rejects even non-overlapping ranges.
    for (size_t i = 0; i < _attachments.size(); ++i) {
        auto* view = _attachments[i];
        if (view && !view->getImage()->isMetal4DisjointFromBuffer(buffer)) { return false; }
    }
    return true;
}

bool MVKMetal4DrawPlanState::addDraw(const MVKCommand* command, const VkDrawIndexedIndirectCommand& args, bool indexed) {
    if (!args.indexCount || !args.instanceCount) { return true; }
    // Even a draw needing no conversion is a potential writer before a later
    // converted draw. Never cross an unproved graphics shader.
    if (!pipeline || !pipeline->metal4HasNoExternalShaderWrites() || pipeline->isTessellationPipeline()) { return false; }
    MVKMetal4PrimitiveState primitive(pipeline, dynamic);
    if (!primitive.needsConversion(indexed ? &index : nullptr)) {
        if (entries.empty()) { ++leadingOrdinaryDraws; }
        return true;
    }
    if (primitive.topology > VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN ||
        (primitive.polygonPoint && primitive.topology != VK_PRIMITIVE_TOPOLOGY_POINT_LIST)) { return false; }
    if (indexed) {
        auto bytes = metal4IndexBytes(&index);
        uint64_t first = uint64_t(args.firstIndex) * bytes, length = uint64_t(args.indexCount) * bytes;
        if (!bytes || !encoder->metal4CanPreconvertIndices(index) || index.offset % bytes ||
            index.offset > index.mtlBuffer.length || first > index.size || length > index.size - first ||
            first > index.mtlBuffer.length - index.offset || length > index.mtlBuffer.length - index.offset - first) { return false; }
    }
    uint64_t size = std::max(uint64_t(1), metal4PrimitiveCount(args.indexCount, primitive.topology) *
                           (primitive.topology == 0 ? 1 : primitive.topology < 3 ? 2 : 3)) * sizeof(uint32_t);
    // A bounded prefix avoids unbounded speculative allocations/CPU lookahead.
    constexpr uint64_t maxBytes = 64 * 1024 * 1024;
    if (entries.size() >= 256 || size > maxBytes || scratchBytes > maxBytes - size) { return false; }
    entries.push_back({command, primitive, index, args, indexed});
    scratchBytes += size;
    return true;
}

const MVKMetal4ConvertedDraw* MVKCommandEncoder::getMetal4PreconvertedDraw(const MVKCommand* command) const {
    auto it = _metal4PreconvertedDraws.find(command);
    return it == _metal4PreconvertedDraws.end() ? nullptr : &it->second;
}

void MVKCommandEncoder::preconvertMetal4Draws(MVKCommand* firstCommand) {
    // Internal component-comparison opt-out; no product backend selector.
    const char* option = std::getenv("MVK_CONFIG_METAL4_PREPASS");
    if (option && std::strcmp(option, "0") == 0) { return; }
    const auto& state = getVkGraphics();
    MVKMetal4DrawPlanState plan {this, state._pipeline, state._renderState, state._indexBuffer, {}, 0};
    uint32_t inspected = 0;
    for (auto* command = firstCommand; command && inspected++ < 2048; command = command->_next) {
        if (!command->planMetal4Draws(plan)) { break; }
    }
    if (plan.entries.empty()) { return; }
    // Preserve the entry dependency, including commands in earlier encoders.
    // After it, these dispatches only read original inputs and write disjoint
    // submission-owned outputs. They require no mutual Dispatch barrier.
    // Only a nonempty ordinary prefix can benefit. Keep the original full
    // render-entry dependency for queries, an existing encoder, or no prefix.
    bool handoff = plan.leadingOrdinaryDraws && !_mtl4ComputeEncoder && !_mtl4RenderEncoder &&
        !_cmdBuffer->_needsVisibilityResultMTLBuffer && !_cmdBuffer->_hasStageCounterTimestampCommand;
    auto producer = getMetal4ComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers, false, handoff);
    if (!producer) { return; }
    uint64_t producerEpoch = _metal4EncodingEpoch;
    _metal4IndependentConversions = true;
    id<MTLComputePipelineState> originalRestartPipeline = nil, batchedRestartPipeline = nil;
    bool batchPipelineQueried = false;
    const bool batchingEnabled = !metal4FusedRestartEnabled();
    NSUInteger originalMaxThreads = 0;
    size_t fallbackUntil = 0;
    for (size_t i = 0; i < plan.entries.size();) {
        const auto& entry = plan.entries[i];
        if (batchingEnabled && i >= fallbackUntil && metal4CanBatchRestart(entry)) {
            if (!originalRestartPipeline) {
                originalRestartPipeline = getCommandEncodingPool()->getMetal4PrimitiveConversionMTLComputePipelineState(true, false);
                if (originalRestartPipeline && originalRestartPipeline.threadExecutionWidth) {
                    originalMaxThreads = originalRestartPipeline.maxTotalThreadsPerThreadgroup;
                }
            }
            if (originalMaxThreads) {
                NSUInteger width = metal4RestartWidth(entry, originalMaxThreads);
                size_t count = 1;
                while (i + count < plan.entries.size() && metal4CanBatchRestart(plan.entries[i + count])) {
                    width = mvkMetal4PrimitiveBatch::appendWidth(uint32_t(width),
                        plan.entries[i + count].arguments.indexCount, originalMaxThreads);
                    ++count;
                }
                if (count >= 2) {
                    if (!batchPipelineQueried) {
                        batchedRestartPipeline = getCommandEncodingPool()->getMetal4BatchedRestartMTLComputePipelineState();
                        batchPipelineQueried = true;
                    }
                    if (batchedRestartPipeline && batchedRestartPipeline.threadExecutionWidth &&
                        width <= batchedRestartPipeline.maxTotalThreadsPerThreadgroup) {
                        std::vector<Metal4ConvertedDraw> converted;
                        if (!convertMetal4RestartBatch(this, plan.entries, i, count, width, batchedRestartPipeline, converted)) { break; }
                        for (size_t j = 0; j < count; ++j) { _metal4PreconvertedDraws.emplace(plan.entries[i + j].command, converted[j]); }
                        i += count;
                        continue;
                    }
                    // Unsupported batch width/PSO preserves the original route;
                    // don't repeatedly rescan the same run on each fallback draw.
                    fallbackUntil = i + count;
                }
            }
        }
        auto args = _metal4Submission->uploadBytesRange(&entry.arguments, sizeof(entry.arguments));
        MVKMetal4ConvertedDraw converted;
        if (!convertMetal4Primitives(this, args.buffer, args.offset, entry.indexed ? &entry.index : nullptr,
                                     entry.arguments.indexCount, 1, converted, false, &entry.primitive)) { break; }
        _metal4PreconvertedDraws.emplace(entry.command, converted);
        ++i;
    }
    _metal4IndependentConversions = false;
    if (handoff && !_metal4EncodingFailed && _metal4PreconvertedDraws.size() == plan.entries.size() &&
        _mtl4ComputeEncoder == producer && _metal4EncodingEpoch == producerEpoch) {
        _metal4PrepassProducer = producer;
        _metal4PrepassProducerEpoch = producerEpoch;
        _metal4PrepassLeadingDraws = plan.leadingOrdinaryDraws;
    }
    // The ordinary entry retains its full barrier. A proven handoff captures
    // prior attachment/resource obligations before conversion and waits for
    // scratch Dispatch output at the first prepared draw. Resolve policy stays.
    if (auto* stats = getMetal4EncodingStats()) {
        ++stats->prepassBatches;
        stats->preconvertedDraws += _metal4PreconvertedDraws.size();
    }
}

bool MVKCmdBindIndexBuffer::planMetal4Draws(MVKMetal4DrawPlanState& state) const {
    // Null-descriptor placeholders are allocated by encode(), never by planning.
    if (!_binding.sourceBuffer || !_binding.mtlBuffer) { return false; }
    state.index = _binding;
    return true;
}

bool MVKCmdDraw::planMetal4Draws(MVKMetal4DrawPlanState& state) const {
    if (_firstVertex > INT32_MAX) { return false; }
    return state.addDraw(this, {_vertexCount, _instanceCount, 0, int32_t(_firstVertex), _firstInstance}, false);
}

bool MVKCmdDrawIndexed::planMetal4Draws(MVKMetal4DrawPlanState& state) const {
    return state.addDraw(this, {_indexCount, _instanceCount, _firstIndex, _vertexOffset, _firstInstance}, true);
}

static void drawMetal4Converted(id<MTL4RenderCommandEncoder> render, const Metal4ConvertedDraw& converted) {
	// The GPU makes the two records mutually exclusive. Keep them adjacent and
	// under the same draw-ID, graphics state and visibility-query scope.
	if (converted.originalIndexAddress) {
		[render drawIndexedPrimitives:converted.primitive indexType:converted.originalIndexType
			indexBuffer:converted.originalIndexAddress indexBufferLength:converted.originalIndexLength
			indirectBuffer:converted.arguments->_mtlBuffer.gpuAddress + converted.arguments->_offset + sizeof(MTLDrawIndexedPrimitivesIndirectArguments)];
	}
	[render drawIndexedPrimitives:converted.primitive indexType:MTLIndexTypeUInt32
		indexBuffer:converted.indices->_mtlBuffer.gpuAddress + converted.indices->_offset
		indexBufferLength:NSUInteger(converted.capacity) * sizeof(uint32_t)
		indirectBuffer:converted.arguments->_mtlBuffer.gpuAddress + converted.arguments->_offset];
}

static void encodeMetal4Indirect(MVKCommandEncoder* encoder, id<MTLBuffer> arguments,
                                VkDeviceSize offset, uint32_t stride, uint32_t count,
                                id<MTLBuffer> countBuffer, const MVKIndexMTLBufferBinding* indices, MVKBuffer* argumentSource = nullptr) {
	if (!count) { return; }
	auto* pipeline = encoder->getGraphicsPipeline();
	auto* subpass = encoder->getSubpass();
	if (!pipeline || !subpass) { encoder->failMetal4Encoding("Native indirect draw requires graphics state."); return; }
	if (countBuffer || pipeline->getZeroDivisorVertexBindings().size() != 0 ||
	    (subpass->isMultiview() && encoder->getPhysicalDevice()->canUseInstancingForMultiview())) {
		encoder->failMetal4Encoding("Native indirect count/zero-divisor/instanced-multiview conversion is not integrated."); return;
	}
	uint64_t recordSize = indices ? sizeof(MTLDrawIndexedPrimitivesIndirectArguments) : sizeof(MTLDrawPrimitivesIndirectArguments);
	uint64_t span = uint64_t(count - 1) * stride + recordSize;
	if (!arguments || (count > 1 && (stride < recordSize || (stride & 3))) ||
	    offset > arguments.length || span > arguments.length - offset || offset > UINT64_MAX - arguments.gpuAddress ||
	    ((arguments.gpuAddress + offset) & 3)) {
		encoder->failMetal4Encoding("Native indirect draw argument range/alignment is invalid."); return;
	}
	uint64_t indexAddress = 0, indexLength = 0;
	if (indices) {
		if (!indices->mtlBuffer || !metal4IndexBytes(indices) ||
		    indices->offset > indices->mtlBuffer.length || indices->offset > UINT64_MAX - indices->mtlBuffer.gpuAddress) {
			encoder->failMetal4Encoding("Native indirect index range/type is invalid or requires conversion."); return;
		}
		uint64_t elementSize = metal4IndexBytes(indices);
		indexAddress = indices->mtlBuffer.gpuAddress + indices->offset;
		indexLength = std::min(uint64_t(indices->size), uint64_t(indices->mtlBuffer.length - indices->offset));
		// Metal requires a whole number of indices even for an odd-sized VkBuffer.
		indexLength -= indexLength % elementSize;
		if (indexAddress % elementSize) { encoder->failMetal4Encoding("Native indirect index address is misaligned."); return; }
	}
	NSError* error = nil;
	if (!encoder->getMetal4Submission()->addResource(arguments, &error) ||
	    (indices && !encoder->getMetal4Submission()->addResource(indices->mtlBuffer, &error))) {
		encoder->failMetal4Encoding("Native indirect resource retention failed."); return;
	}
	encoder->_isIndexedDraw = indices != nullptr;
	if (metal4NeedsPrimitiveConversion(encoder, indices)) {
		if (!indices) {
			encoder->failMetal4Encoding("Native nonindexed indirect primitive conversion has no bounded vertex-count allocation yet."); return;
		}
        uint64_t maxCount = indexLength / metal4IndexBytes(indices);
        auto primitive = MVKMetal4PrimitiveState(pipeline, encoder->getVkGraphics()._renderState);
        uint64_t capacity = std::max(uint64_t(1), metal4PrimitiveCount(maxCount, primitive.topology) *
                                    (primitive.topology == 0 ? 1 : primitive.topology < 3 ? 2 : 3));
        constexpr uint64_t maxBatchBytes = 64 * 1024 * 1024;
        uint64_t bytesPerDraw = capacity * sizeof(uint32_t) +
            (metal4CanSelectOriginalIndices(primitive, metal4IndexBytes(indices)) ? 2 : 1) * sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
        bool sourceRange = argumentSource && argumentSource->getMTLBuffer() == arguments &&
            offset >= argumentSource->getMTLBufferOffset() &&
            offset - argumentSource->getMTLBufferOffset() <= argumentSource->getByteCount() &&
            span <= argumentSource->getByteCount() - (offset - argumentSource->getMTLBufferOffset());
        // Hoisting later records over earlier draws is valid only if those draws
        // cannot write either input: reject shader side effects and every shared,
        // imported/unknown, or aliasable attachment allocation. Query/sample and
        // secondary-command boundaries are never crossed: this is one Vk command.
        bool batch = count > 1 && count <= 256 && maxCount <= UINT32_MAX && capacity <= UINT32_MAX &&
            bytesPerDraw <= maxBatchBytes / count && sourceRange &&
            pipeline->metal4HasNoExternalShaderWrites() && !pipeline->isTessellationPipeline() &&
            encoder->metal4CanPreconvertIndices(*indices) && encoder->metal4CanPreconvertBuffer(argumentSource);
        if (batch) {
            if (auto* stats = encoder->getMetal4EncodingStats()) {
                ++stats->indirectConversionBatches;
                stats->indirectBatchedDraws += count;
            }
            std::vector<Metal4ConvertedDraw> converted(count);
            for (uint32_t draw = 0; draw < count; ++draw) {
                // First conversion keeps all entry dependencies. Later ones only
                // read original input and write separate submission-owned scratch.
                if (!convertMetal4Primitives(encoder, arguments, offset + uint64_t(draw) * stride, indices,
                                             maxCount, 1, converted[draw], true, &primitive, draw != 0)) { return; }
            }
            encoder->restartMetalRenderPassIfNeeded();
            auto render = encoder->getMetal4RenderEncoder();
            if (!encoder->getState().prepareMetal4Draw(render, *encoder, true)) { return; }
            for (uint32_t draw = 0; draw < count; ++draw) {
                if (!bindMetal4DrawID(encoder, pipeline, draw)) { return; }
                recordMetal4Draw(encoder, true);
                drawMetal4Converted(render, converted[draw]);
            }
            return;
        }
        if (count > 1) {
            if (auto* stats = encoder->getMetal4EncodingStats()) { ++stats->indirectBatchFallbacks; }
        }
        // Unknown alias/write proofs and large bounds keep the previous bounded
        // scratch reuse, including full conversion -> draw -> conversion ordering.
        Metal4ConvertedDraw converted;
		for (uint32_t draw = 0; draw < count; ++draw) {
			if (!convertMetal4Primitives(encoder, arguments, offset + uint64_t(draw) * stride, indices, maxCount, 1, converted, true)) { return; }
			encoder->restartMetalRenderPassIfNeeded();
			auto render = encoder->getMetal4RenderEncoder();
			if (!encoder->getState().prepareMetal4Draw(render, *encoder, true) || !bindMetal4DrawID(encoder, pipeline, draw)) { return; }
			recordMetal4Draw(encoder, true);
			drawMetal4Converted(render, converted);
		}
		return;
	}
	encoder->restartMetalRenderPassIfNeeded();
	id<MTL4RenderCommandEncoder> render = encoder->getMetal4RenderEncoder();
	if (!encoder->getState().prepareMetal4Draw(render, *encoder)) { return; }
	uint64_t address = arguments.gpuAddress + offset;
	for (uint32_t draw = 0; draw < count; ++draw) {
		if (!bindMetal4DrawID(encoder, pipeline, draw)) { return; }
		recordMetal4Draw(encoder, true);
		if (indices) {
			[render drawIndexedPrimitives:encoder->getMtlGraphics().getPrimitiveType()
			                    indexType:static_cast<MTLIndexType>(indices->mtlIndexType)
			                  indexBuffer:indexAddress indexBufferLength:indexLength
			               indirectBuffer:address + uint64_t(draw) * stride];
		} else {
			[render drawPrimitives:encoder->getMtlGraphics().getPrimitiveType() indirectBuffer:address + uint64_t(draw) * stride];
		}
	}
}
#endif


#pragma mark -
#pragma mark MVKCmdBindVertexBuffers

template <size_t N>
VkResult MVKCmdBindVertexBuffers<N>::setContent(MVKCommandBuffer* cmdBuff,
												uint32_t firstBinding,
												uint32_t bindingCount,
												const VkBuffer* pBuffers,
												const VkDeviceSize* pOffsets,
												const VkDeviceSize* pSizes,
												const VkDeviceSize* pStrides) {
	_firstBinding = firstBinding;
	_bindings.clear();	// Clear for reuse
    _bindings.reserve(bindingCount);
    MVKVertexMTLBufferBinding b;
    for (uint32_t bindIdx = 0; bindIdx < bindingCount; bindIdx++) {
        MVKBuffer* mvkBuffer = (MVKBuffer*)pBuffers[bindIdx];
        b.mtlBuffer = mvkBuffer->getMTLBuffer();
        b.offset = mvkBuffer->getMTLBufferOffset() + pOffsets[bindIdx];
		b.size = pSizes ? uint32_t(pSizes[bindIdx] == VK_WHOLE_SIZE ? mvkBuffer->getByteCount() - pOffsets[bindIdx] : pSizes[bindIdx]) : 0;
		b.stride = pStrides ? (uint32_t)pStrides[bindIdx] : 0;
        _bindings.push_back(b);
    }

	return VK_SUCCESS;
}
template <size_t N>
void MVKCmdBindVertexBuffers<N>::encode(MVKCommandEncoder* cmdEncoder) {
	cmdEncoder->getState().bindVertexBuffers(_firstBinding, _bindings.contents());
}

template class MVKCmdBindVertexBuffers<1>;
template class MVKCmdBindVertexBuffers<2>;
template class MVKCmdBindVertexBuffers<8>;


#pragma mark -
#pragma mark MVKCmdBindIndexBuffer

VkResult MVKCmdBindIndexBuffer::setContent(MVKCommandBuffer* cmdBuff,
										   VkBuffer buffer,
										   VkDeviceSize offset,
										   VkIndexType indexType) {
	return setContent(cmdBuff, buffer, offset, VK_WHOLE_SIZE, indexType);
}

VkResult MVKCmdBindIndexBuffer::setContent(MVKCommandBuffer* cmdBuff,
										   VkBuffer buffer,
										   VkDeviceSize offset,
										   VkDeviceSize size,
										   VkIndexType indexType) {
	_binding.vkIndexType = indexType;
	_binding.mtlIndexType = mvkMTLIndexTypeFromVkIndexType(indexType);

	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
#if MVK_BUILD_METAL4_FOUNDATION
    _binding.sourceBuffer = mvkBuffer;
#endif
	if (mvkBuffer) {
		_binding.mtlBuffer = mvkBuffer->getMTLBuffer();
		_binding.offset = mvkBuffer->getMTLBufferOffset() + offset;
		_binding.size = size == VK_WHOLE_SIZE ? mvkBuffer->getByteCount() - offset : size;
	} else {
		_binding.mtlBuffer = nullptr;
		// Must be 0 for null buffer.
		_binding.offset = 0;
		_binding.size = size == VK_WHOLE_SIZE ? mvkMTLIndexTypeSizeInBytes((MTLIndexType)_binding.mtlIndexType) : size;
	}

	return VK_SUCCESS;
}

void MVKCmdBindIndexBuffer::encode(MVKCommandEncoder* cmdEncoder) {
    if (_binding.mtlBuffer == nullptr) {
        // In the null buffer case, offset must be 0, and since we don't support nullDescriptor, the indices are undefined.
        // Thus, we can use a simple temporary buffer to stand in for the index buffer here.
        const auto* placeholderBuffer = cmdEncoder->getTempMTLBuffer(_binding.size);
        _binding.mtlBuffer = placeholderBuffer->_mtlBuffer;
        _binding.offset = placeholderBuffer->_offset;
    }

    cmdEncoder->getState().bindIndexBuffer(_binding);
}


#pragma mark -
#pragma mark MVKCmdDraw

VkResult MVKCmdDraw::setContent(MVKCommandBuffer* cmdBuff,
								uint32_t vertexCount,
								uint32_t instanceCount,
								uint32_t firstVertex,
								uint32_t firstInstance,
								uint32_t drawIndex) {
	_vertexCount = vertexCount;
	_instanceCount = instanceCount;
	_firstVertex = firstVertex;
	_firstInstance = firstInstance;
	_drawIndex = drawIndex;

    // Validate
    if ((_firstInstance != 0) && !(cmdBuff->getMetalFeatures().baseVertexInstanceDrawing)) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDraw(): The current device does not support drawing with a non-zero base instance.");
    }

	return VK_SUCCESS;
}

// Populates and encodes a MVKCmdDrawIndexedIndirect command, after populating indexed indirect buffers.
void MVKCmdDraw::encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder) {

	// Create an indexed indirect buffer and populate it from the draw arguments.
	uint32_t indirectIdxBuffStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	auto* indirectIdxBuff = cmdEncoder->getTempMTLBuffer(indirectIdxBuffStride);
	auto* pIndArg = (MTLDrawIndexedPrimitivesIndirectArguments*)indirectIdxBuff->getContents();
	pIndArg->indexCount = _vertexCount;
	// let the indirect index point to the beginning of vertex index buffer below
	pIndArg->indexStart = 0;
	pIndArg->baseVertex = 0;
	pIndArg->instanceCount = _instanceCount;
	pIndArg->baseInstance = _firstInstance;

	// Create an index buffer populated with synthetic indexes.
	// Start populating indexes directly from the beginning and align with corresponding vertexes by adding _firstVertex
	MTLIndexType mtlIdxType = MTLIndexTypeUInt32;
	auto* vtxIdxBuff = cmdEncoder->getTempMTLBuffer(mvkMTLIndexTypeSizeInBytes(mtlIdxType) * _vertexCount);
	auto* pIdxBuff = (uint32_t*)vtxIdxBuff->getContents();

	for (uint32_t idx = 0; idx < _vertexCount; idx++) {
		pIdxBuff[idx] = _firstVertex + idx;
	}

	MVKIndexMTLBufferBinding ibb;
	ibb.mtlIndexType = mtlIdxType;
	ibb.mtlBuffer = vtxIdxBuff->_mtlBuffer;
	ibb.offset = vtxIdxBuff->_offset;
	ibb.size = vtxIdxBuff->_length;

	MVKCmdDrawIndexedIndirect diiCmd;
	diiCmd.setContent(cmdEncoder->_cmdBuffer,
					  indirectIdxBuff->_mtlBuffer,
					  indirectIdxBuff->_offset,
					  1,
					  indirectIdxBuffStride);
	diiCmd.encode(cmdEncoder, ibb);
}

void MVKCmdDraw::encode(MVKCommandEncoder* cmdEncoder) {

	if (_vertexCount == 0 || _instanceCount == 0) { return; }	// Nothing to do.
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) {
		cmdEncoder->_isIndexedDraw = false;
		auto* pipeline = cmdEncoder->getGraphicsPipeline();
		auto* subpass = cmdEncoder->getSubpass();
		if (!pipeline || !subpass) { cmdEncoder->failMetal4Encoding("Native draw requires graphics state."); return; }
		NSUInteger viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
		bool conversion = metal4NeedsPrimitiveConversion(cmdEncoder, nullptr);
		bool usesPrepared = false;
		Metal4ConvertedDraw converted;
		if (conversion) {
			if (_firstVertex > INT32_MAX || uint64_t(_instanceCount) * viewCount > UINT32_MAX) {
				cmdEncoder->failMetal4Encoding("Native converted draw exceeds indirect base-vertex/instance limits."); return;
			}
            if (const auto* prepared = cmdEncoder->getMetal4PreconvertedDraw(this)) { converted = *prepared; usesPrepared = true; }
            else {
			VkDrawIndexedIndirectCommand parameters {_vertexCount, _instanceCount, 0, int32_t(_firstVertex), _firstInstance};
			auto arguments = cmdEncoder->getMetal4Submission()->uploadBytesRange(&parameters, sizeof(parameters));
			if (!convertMetal4Primitives(cmdEncoder, arguments.buffer, arguments.offset, nullptr, _vertexCount, uint32_t(viewCount), converted)) { return; }
            }
		}
		cmdEncoder->restartMetalRenderPassIfNeeded();
		id<MTL4RenderCommandEncoder> encoder = cmdEncoder->getMetal4RenderEncoder();
		if (!cmdEncoder->getState().prepareMetal4Draw(encoder, *cmdEncoder, conversion)) { return; }
		if (!cmdEncoder->getState().offsetMetal4ZeroDivisorVertexBuffers(*cmdEncoder, pipeline, _firstInstance) || !bindMetal4DrawID(cmdEncoder, pipeline, _drawIndex)) { return; }
		if (usesPrepared && !cmdEncoder->waitForMetal4PreconvertedDraw(encoder)) { return; }
		recordMetal4Draw(cmdEncoder, false);
		if (conversion) { drawMetal4Converted(encoder, converted); return; }
		[encoder drawPrimitives:cmdEncoder->getMtlGraphics().getPrimitiveType() vertexStart:_firstVertex vertexCount:_vertexCount
		          instanceCount:NSUInteger(_instanceCount) * viewCount baseInstance:_firstInstance];
		return;
	}
#endif

	cmdEncoder->restartMetalRenderPassIfNeeded();

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	// Metal doesn't support triangle fans, so encode it as triangles via an indexed indirect triangles command instead.
	if (cmdEncoder->getState().vkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
		encodeIndexedIndirect(cmdEncoder);
		return;
	}

    cmdEncoder->_isIndexedDraw = false;

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
	struct {
		uint32_t inControlPointCount = 0;
		uint32_t patchCount = 0;
	} tessParams;
    uint32_t tessVertexCount = 0;
    uint32_t outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        tessParams.inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        tessVertexCount = _vertexCount / tessParams.inControlPointCount * tessParams.inControlPointCount;
        tessParams.patchCount = tessVertexCount / tessParams.inControlPointCount * _instanceCount;
        if (!tessParams.patchCount) { return; }
    }
    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(sizeof(uint32_t));

        // Zero for a single draw, or the index of this draw within a vkCmdDrawMulti*EXT() call.
        *(uint32_t*)tempDrawIDBuff->getContents() = _drawIndex;
    }
    for (uint32_t s : stages) {
        auto stage = MVKGraphicsStage(s);
        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

		if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

		id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;

		switch (stage) {
            case kMVKGraphicsStageVertex: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsVertexOutputBuffer()) {
                    vtxOutBuff = cmdEncoder->getTempMTLBuffer(_vertexCount * _instanceCount * 4 * dvcLimits.maxVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsDrawIdBuffer()) {
                    [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                          offset: tempDrawIDBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                }
				[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(_firstVertex, _firstInstance, tessVertexCount, _instanceCount)];
				// If there are vertex bindings with a zero vertex divisor, I need to offset them by
				// _firstInstance * stride, since that is the expected behaviour for a divisor of 0.
                cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
				id<MTLComputePipelineState> vtxState = pipeline->getTessVertexStageState();
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessVertexCount, _instanceCount, 1)
					             threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessVertexCount, vtxState.threadExecutionWidth), _instanceCount, 1)
                                      threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				}
                break;
			}
            case kMVKGraphicsStageTessControl: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsTessCtlOutputBuffer()) {
                    tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                          offset: tcOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsTessCtlPatchOutputBuffer()) {
                    tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                          offset: tcPatchOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                }
                tcLevelBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);
                [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                      offset: tcLevelBuff->_offset
                                     atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &tessParams,
                                            sizeof(tessParams),
                                            pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]);
                if (pipeline->needsVertexOutputBuffer()) {
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                }
				
				NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
				NSUInteger wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				while (wgSize > dvcLimits.maxComputeWorkGroupSize[0]) {
					sgSize >>= 1;
					wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				}
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessParams.patchCount * outControlPointCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessParams.patchCount * outControlPointCount, wgSize), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				}
                // Running this stage prematurely ended the render pass, so we have to start it up again.
                // TODO: On iOS, maybe we could use a tile shader to avoid this.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                break;
			}
            case kMVKGraphicsStageRasterization:
                if (pipeline->isTessellationPipeline()) {
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                offset: tcOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                offset: tcPatchOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
                    }
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                            offset: tcLevelBuff->_offset
                                                           atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
                    [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                        offset: tcLevelBuff->_offset
                                                                instanceStride: 0];
                    [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                    patchStart: 0
                                                    patchCount: tessParams.patchCount
                                              patchIndexBuffer: nil
                                        patchIndexBufferOffset: 0
                                                 instanceCount: 1
                                                  baseInstance: 0];
                } else {
                    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();
                    uint32_t viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
                    uint32_t instanceCount = _instanceCount * viewCount;
                    cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
                    if (pipeline->needsDrawIdBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                offset: tempDrawIDBuff->_offset
                                                               atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
                    if (mtlFeats.baseVertexInstanceDrawing) {
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                          vertexStart: _firstVertex
                                                          vertexCount: _vertexCount
                                                        instanceCount: instanceCount
                                                         baseInstance: _firstInstance];
                    } else {
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                          vertexStart: _firstVertex
                                                          vertexCount: _vertexCount
                                                        instanceCount: instanceCount];
                    }
                }
                break;
        }
    }
}


#pragma mark -
#pragma mark MVKCmdDrawIndexed

VkResult MVKCmdDrawIndexed::setContent(MVKCommandBuffer* cmdBuff,
									   uint32_t indexCount,
									   uint32_t instanceCount,
									   uint32_t firstIndex,
									   int32_t vertexOffset,
									   uint32_t firstInstance,
									   uint32_t drawIndex) {
	_indexCount = indexCount;
	_instanceCount = instanceCount;
	_firstIndex = firstIndex;
	_vertexOffset = vertexOffset;
	_firstInstance = firstInstance;
	_drawIndex = drawIndex;

    // Validate
	auto& mtlFeats = cmdBuff->getMetalFeatures();
    if ((_firstInstance != 0) && !(mtlFeats.baseVertexInstanceDrawing)) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexed(): The current device does not support drawing with a non-zero base instance.");
    }
    if ((_vertexOffset != 0) && !(mtlFeats.baseVertexInstanceDrawing)) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexed(): The current device does not support drawing with a non-zero base vertex.");
    }

	return VK_SUCCESS;
}

// Populates and encodes a MVKCmdDrawIndexedIndirect command, after populating an indexed indirect buffer.
void MVKCmdDrawIndexed::encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder) {

	// Create an indexed indirect buffer and populate it from the draw arguments.
	uint32_t indirectIdxBuffStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	auto* indirectIdxBuff = cmdEncoder->getTempMTLBuffer(indirectIdxBuffStride);
	auto* pIndArg = (MTLDrawIndexedPrimitivesIndirectArguments*)indirectIdxBuff->getContents();
	pIndArg->indexCount = _indexCount;
	pIndArg->indexStart = _firstIndex;
	pIndArg->baseVertex = _vertexOffset;
	pIndArg->instanceCount = _instanceCount;
	pIndArg->baseInstance = _firstInstance;

	MVKCmdDrawIndexedIndirect diiCmd;
	diiCmd.setContent(cmdEncoder->_cmdBuffer,
					  indirectIdxBuff->_mtlBuffer,
					  indirectIdxBuff->_offset,
					  1,
					  indirectIdxBuffStride);
	diiCmd.encode(cmdEncoder);
}

static const MVKMTLBufferAllocation* convertUint8IndexBuffer(MVKCommandEncoder* cmdEncoder, const MVKIndexMTLBufferBinding& ibb) {
    // Copy 8-bit indices into 16-bit index buffer compatible with Metal.
    const auto numIndices = ibb.size;
    auto* uint16Buf = cmdEncoder->getTempMTLBuffer(numIndices * 2);

    cmdEncoder->encodeStoreActions(true);

    // Determine the number of full threadgroups we can dispatch to cover the buffer content efficiently.
    // Some GPU's report different values for max threadgroup width between the pipeline state and device,
    // so conservatively use the minimum of these two reported values.
    id<MTLComputePipelineState> cps = cmdEncoder->getCommandEncodingPool()->getConvertUint8IndicesMTLComputePipelineState();
    NSUInteger tgWidth = std::min(cps.maxTotalThreadsPerThreadgroup, cmdEncoder->getMTLDevice().maxThreadsPerThreadgroup.width);
    NSUInteger tgCount = numIndices / tgWidth;

    MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
    id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandConvertUint8Indices);
    state.bindPipeline(mtlComputeEnc, cps);
    state.bindBuffer(mtlComputeEnc, ibb.mtlBuffer, ibb.offset, 0);
    state.bindBuffer(mtlComputeEnc, uint16Buf->_mtlBuffer, uint16Buf->_offset, 1);

    // Run as many full threadgroups as will fit into the buffer content.
    if (tgCount > 0) {
        [mtlComputeEnc dispatchThreadgroups: MTLSizeMake(tgCount, 1, 1)
                       threadsPerThreadgroup: MTLSizeMake(tgWidth, 1, 1)];
    }

    // If there is left-over buffer content after running full threadgroups, or if the buffer content
    // fits within a single threadgroup, run a single partial threadgroup of the appropriate size.
    auto remainderIndexCount = numIndices % tgWidth;
    if (remainderIndexCount > 0) {
        if (tgCount > 0) {
            const auto indicesConverted = tgCount * tgWidth;
            state.bindBuffer(mtlComputeEnc, ibb.mtlBuffer, ibb.offset + indicesConverted, 0);
            state.bindBuffer(mtlComputeEnc, uint16Buf->_mtlBuffer, uint16Buf->_offset + indicesConverted * 2, 1);
        }
        [mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1)
                       threadsPerThreadgroup: MTLSizeMake(remainderIndexCount, 1, 1)];
    }

    // Running this stage prematurely ended the render pass, so we have to start it up again.
    cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);

    return uint16Buf;
}

void MVKCmdDrawIndexed::encode(MVKCommandEncoder* cmdEncoder) {

	if (_indexCount == 0 || _instanceCount == 0) { return; }	// Nothing to do.
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) {
		const auto& binding = cmdEncoder->getVkGraphics()._indexBuffer;
		if (!binding.mtlBuffer || !metal4IndexBytes(&binding)) {
			cmdEncoder->failMetal4Encoding("Native index buffer/type is unavailable."); return;
		}
		uint64_t indexSize = metal4IndexBytes(&binding);
		uint64_t delta = uint64_t(_firstIndex) * indexSize;
		uint64_t required = uint64_t(_indexCount) * indexSize;
		if (delta > binding.size || required > binding.size - delta || binding.offset > binding.mtlBuffer.length ||
		    delta > binding.mtlBuffer.length - binding.offset || required > binding.mtlBuffer.length - binding.offset - delta ||
		    binding.offset > UINT64_MAX - delta || binding.offset + delta > UINT64_MAX - binding.mtlBuffer.gpuAddress) {
			cmdEncoder->failMetal4Encoding("Native indexed draw exceeds its bound index range."); return;
		}
		NSError* error = nil;
		if (!cmdEncoder->getMetal4Submission()->addResource(binding.mtlBuffer, &error)) {
			cmdEncoder->failMetal4Encoding("Native index buffer retention failed."); return;
		}
		cmdEncoder->_isIndexedDraw = true;
		auto* pipeline = cmdEncoder->getGraphicsPipeline();
		auto* subpass = cmdEncoder->getSubpass();
		if (!pipeline || !subpass) { cmdEncoder->failMetal4Encoding("Native indexed draw requires graphics state."); return; }
		NSUInteger viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
		bool conversion = metal4NeedsPrimitiveConversion(cmdEncoder, &binding);
		bool usesPrepared = false;
		Metal4ConvertedDraw converted;
		if (conversion) {
			if (uint64_t(_instanceCount) * viewCount > UINT32_MAX) {
				cmdEncoder->failMetal4Encoding("Native converted indexed draw exceeds indirect instance limits."); return;
			}
            if (const auto* prepared = cmdEncoder->getMetal4PreconvertedDraw(this)) { converted = *prepared; usesPrepared = true; }
            else {
			VkDrawIndexedIndirectCommand parameters {_indexCount, _instanceCount, _firstIndex, _vertexOffset, _firstInstance};
			auto arguments = cmdEncoder->getMetal4Submission()->uploadBytesRange(&parameters, sizeof(parameters));
			if (!convertMetal4Primitives(cmdEncoder, arguments.buffer, arguments.offset, &binding, _indexCount, uint32_t(viewCount), converted)) { return; }
            }
		}
		cmdEncoder->restartMetalRenderPassIfNeeded();
		id<MTL4RenderCommandEncoder> encoder = cmdEncoder->getMetal4RenderEncoder();
		if (!cmdEncoder->getState().prepareMetal4Draw(encoder, *cmdEncoder, conversion)) { return; }
		if (!cmdEncoder->getState().offsetMetal4ZeroDivisorVertexBuffers(*cmdEncoder, pipeline, _firstInstance) || !bindMetal4DrawID(cmdEncoder, pipeline, _drawIndex)) { return; }
		if (usesPrepared && !cmdEncoder->waitForMetal4PreconvertedDraw(encoder)) { return; }
		recordMetal4Draw(cmdEncoder, false);
		if (conversion) { drawMetal4Converted(encoder, converted); return; }
		NSUInteger remaining = std::min(uint64_t(binding.size - delta), uint64_t(binding.mtlBuffer.length - binding.offset - delta));
		remaining -= remaining % indexSize;
		[encoder drawIndexedPrimitives:cmdEncoder->getMtlGraphics().getPrimitiveType() indexCount:_indexCount
		                       indexType:static_cast<MTLIndexType>(binding.mtlIndexType)
		                     indexBuffer:binding.mtlBuffer.gpuAddress + binding.offset + delta indexBufferLength:remaining
		                   instanceCount:NSUInteger(_instanceCount) * viewCount baseVertex:_vertexOffset baseInstance:_firstInstance];
		return;
	}
#endif

	cmdEncoder->restartMetalRenderPassIfNeeded();

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;

	// Metal doesn't support triangle fans, so encode it as triangles via an indexed indirect triangles command instead.
	if (cmdEncoder->getState().vkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
		encodeIndexedIndirect(cmdEncoder);
		return;
	}

    cmdEncoder->_isIndexedDraw = true;

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    MVKIndexMTLBufferBinding ibb = cmdEncoder->getVkGraphics()._indexBuffer;
    if (ibb.vkIndexType == VK_INDEX_TYPE_UINT8) {
        auto* converted = convertUint8IndexBuffer(cmdEncoder, ibb);
        ibb.mtlBuffer = converted->_mtlBuffer;
        ibb.offset = converted->_offset;
        ibb.size = converted->_length;
    }

    size_t idxSize = mvkMTLIndexTypeSizeInBytes((MTLIndexType)ibb.mtlIndexType);
    VkDeviceSize idxBuffOffset = ibb.offset + (_firstIndex * idxSize);

    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
	struct {
		uint32_t inControlPointCount = 0;
		uint32_t patchCount = 0;
	} tessParams;
    uint32_t tessVertexCount = 0;
    uint32_t outControlPointCount = 0;
    if (pipeline->isTessellationPipeline()) {
        tessParams.inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        tessVertexCount = _indexCount / tessParams.inControlPointCount * tessParams.inControlPointCount;
        tessParams.patchCount = tessVertexCount / tessParams.inControlPointCount * _instanceCount;
        if (!tessParams.patchCount) { return; }
    }
    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(sizeof(uint32_t));

        // Zero for a single draw, or the index of this draw within a vkCmdDrawMulti*EXT() call.
        *(uint32_t*)tempDrawIDBuff->getContents() = _drawIndex;
    }
    for (uint32_t s : stages) {
        auto stage = MVKGraphicsStage(s);
        id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
        cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal

		if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

        switch (stage) {
            case kMVKGraphicsStageVertex: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsVertexOutputBuffer()) {
                    vtxOutBuff = cmdEncoder->getTempMTLBuffer(_indexCount * _instanceCount * 4 * dvcLimits.maxVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsDrawIdBuffer()) {
                    [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                          offset: tempDrawIDBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                }
				[mtlTessCtlEncoder setBuffer: ibb.mtlBuffer
                                      offset: idxBuffOffset
                                     atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]];
				[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(_vertexOffset, _firstInstance, tessVertexCount, _instanceCount)];
				// If there are vertex bindings with a zero vertex divisor, I need to offset them by
				// _firstInstance * stride, since that is the expected behaviour for a divisor of 0.
                cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
				id<MTLComputePipelineState> vtxState = ibb.mtlIndexType == MTLIndexTypeUInt16 ? pipeline->getTessVertexStageIndex16State() : pipeline->getTessVertexStageIndex32State();
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessVertexCount, _instanceCount, 1)
					             threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessVertexCount, vtxState.threadExecutionWidth), _instanceCount, 1)
                                      threadsPerThreadgroup: MTLSizeMake(vtxState.threadExecutionWidth, 1, 1)];
				}
                break;
			}
            case kMVKGraphicsStageTessControl: {
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                if (pipeline->needsTessCtlOutputBuffer()) {
                    tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                          offset: tcOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                }
                if (pipeline->needsTessCtlPatchOutputBuffer()) {
                    tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
                    [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                          offset: tcPatchOutBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                }
                tcLevelBuff = cmdEncoder->getTempMTLBuffer(tessParams.patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);
                [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                      offset: tcLevelBuff->_offset
                                     atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
                cmdEncoder->setComputeBytes(mtlTessCtlEncoder,
                                            &tessParams,
                                            sizeof(tessParams),
                                            pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]);
                if (pipeline->needsVertexOutputBuffer()) {
                    [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                          offset: vtxOutBuff->_offset
                                         atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                }
				// The vertex shader produced output in the correct order, so there's no need to use
				// an index buffer here.
				NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
				NSUInteger wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				while (wgSize > dvcLimits.maxComputeWorkGroupSize[0]) {
					sgSize >>= 1;
					wgSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
				}
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(tessParams.patchCount * outControlPointCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide(tessParams.patchCount * outControlPointCount, wgSize), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(wgSize, 1, 1)];
				}
                // Running this stage prematurely ended the render pass, so we have to start it up again.
                // TODO: On iOS, maybe we could use a tile shader to avoid this.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                break;
			}
            case kMVKGraphicsStageRasterization:
                if (pipeline->isTessellationPipeline()) {
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
                                                                offset: tcOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
                                                                offset: tcPatchOutBuff->_offset
                                                               atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
                    }
                    [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
                                                            offset: tcLevelBuff->_offset
                                                           atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
                    [cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
                                                                        offset: tcLevelBuff->_offset
                                                                instanceStride: 0];
                    // The tessellation control shader produced output in the correct order, so there's no need to use
                    // an index buffer here.
                    [cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
                                                    patchStart: 0
                                                    patchCount: tessParams.patchCount
                                              patchIndexBuffer: nil
                                        patchIndexBufferOffset: 0
                                                 instanceCount: 1
                                                  baseInstance: 0];
                } else {
                    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();
                    uint32_t viewCount = subpass->isMultiview() ? subpass->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) : 1;
                    uint32_t instanceCount = _instanceCount * viewCount;
                    cmdEncoder->getState().offsetZeroDivisorVertexBuffers(*cmdEncoder, stage, pipeline, _firstInstance);
                    if (pipeline->needsDrawIdBuffer()) {
                        [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                offset: tempDrawIDBuff->_offset
                                                               atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
                    if (mtlFeats.baseVertexInstanceDrawing) {
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                                  indexCount: _indexCount
                                                                   indexType: (MTLIndexType)ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: idxBuffOffset
                                                               instanceCount: instanceCount
                                                                  baseVertex: _vertexOffset
                                                                baseInstance: _firstInstance];
                    } else {
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                                  indexCount: _indexCount
                                                                   indexType: (MTLIndexType)ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: idxBuffOffset
                                                               instanceCount: instanceCount];
                    }
                }
                break;
        }
    }
}


// This is totally arbitrary, but we're forced to do this because we don't know how many vertices
// there are at encoding time. And this will probably be inadequate for large instanced draws.
// TODO: Consider breaking up such draws using different base instance values. But this will
// require yet more munging of the indirect buffers...
static const uint32_t kMVKMaxDrawIndirectVertexCount = 1024 * KIBI;

static const MVKMTLBufferAllocation* encodeIndirectCountConversion(
		MVKCommandEncoder* cmdEncoder,
		id<MTLBuffer> indirectBuffer,
		VkDeviceSize indirectBufferOffset,
		uint32_t indirectBufferStride,
		id<MTLBuffer> countBuffer,
		VkDeviceSize countBufferOffset,
		uint32_t drawCount,
		bool indexed) {
	VkDeviceSize commandSize = indexed ? sizeof(MTLDrawIndexedPrimitivesIndirectArguments) : sizeof(MTLDrawPrimitivesIndirectArguments);
	auto* convertedBuffer = cmdEncoder->getTempMTLBuffer(commandSize * drawCount, true);

	cmdEncoder->encodeStoreActions(true);
	auto* computeEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	id<MTLComputePipelineState> pipeline = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectCountConvertBuffersMTLComputePipelineState(indexed);
	state.bindPipeline(computeEncoder, pipeline);
	state.bindBuffer(computeEncoder, indirectBuffer, indirectBufferOffset, 0);
	state.bindBuffer(computeEncoder, convertedBuffer->_mtlBuffer, convertedBuffer->_offset, 1);
	state.bindStructBytes(computeEncoder, &indirectBufferStride, 2);
	state.bindStructBytes(computeEncoder, &drawCount, 3);
	state.bindBuffer(computeEncoder, countBuffer, countBufferOffset, 4);

	NSUInteger threadWidth = pipeline.threadExecutionWidth;
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[computeEncoder dispatchThreads: MTLSizeMake(drawCount, 1, 1)
						threadsPerThreadgroup: MTLSizeMake(threadWidth, 1, 1)];
	} else {
		[computeEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(drawCount, threadWidth), 1, 1)
						  threadsPerThreadgroup: MTLSizeMake(threadWidth, 1, 1)];
	}
	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	return convertedBuffer;
}

typedef struct MVKIndirectZeroDivisorVertexBuffer {
	uint32_t mtlBufferIndex;
	uint32_t stride;
	const MVKMTLBufferAllocation* allocation;
} MVKIndirectZeroDivisorVertexBuffer;

typedef MVKSmallVector<MVKIndirectZeroDivisorVertexBuffer, 4> MVKIndirectZeroDivisorVertexBuffers;

static MVKIndirectZeroDivisorVertexBuffers encodeIndirectZeroDivisorVertexBufferCopies(
		MVKCommandEncoder* cmdEncoder,
		MVKGraphicsPipeline* pipeline,
		id<MTLBuffer> indirectBuffer,
		VkDeviceSize indirectBufferOffset,
		uint32_t indirectBufferStride,
		uint32_t drawCount,
		bool indexed) {
	MVKIndirectZeroDivisorVertexBuffers copiedBuffers;
	auto bindings = pipeline->getZeroDivisorVertexBindings();
	if (drawCount == 0 || bindings.size() == 0) { return copiedBuffers; }

	cmdEncoder->encodeStoreActions(true);
	auto* computeEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	id<MTLComputePipelineState> computePipeline = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectCopyZeroDivisorVertexBuffersMTLComputePipelineState();
	uint32_t baseInstanceOffset = indexed ? 16 : 12;
	state.bindPipeline(computeEncoder, computePipeline);

	for (const auto& binding : bindings) {
		uint32_t sourceBinding = binding.first;
		VkDeviceSize translationOffset = 0;
		for (const auto& translatedBinding : pipeline->getTranslatedVertexBindings()) {
			if (translatedBinding.translationBinding == binding.first) {
				sourceBinding = translatedBinding.binding;
				translationOffset = translatedBinding.translationOffset;
				break;
			}
		}
		const auto& sourceBuffer = cmdEncoder->getVkGraphics()._vertexBuffers[sourceBinding];
		uint32_t vertexStride = pipeline->getDynamicStateFlags().has(MVKRenderStateFlag::VertexStride) ? sourceBuffer.stride : binding.second;
		if (vertexStride == 0) { continue; }
		if (sourceBuffer.mtlBuffer == nil) { continue; }

		auto* copiedBuffer = cmdEncoder->getTempMTLBuffer((NSUInteger)drawCount * vertexStride, true);
		copiedBuffers.push_back({pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first), vertexStride, copiedBuffer});
		state.bindBuffer(computeEncoder, indirectBuffer, indirectBufferOffset, 0);
		state.bindBuffer(computeEncoder, sourceBuffer.mtlBuffer, sourceBuffer.offset + translationOffset, 1);
		state.bindBuffer(computeEncoder, copiedBuffer->_mtlBuffer, copiedBuffer->_offset, 2);
		state.bindStructBytes(computeEncoder, &indirectBufferStride, 3);
		state.bindStructBytes(computeEncoder, &drawCount, 4);
		state.bindStructBytes(computeEncoder, &vertexStride, 5);
		state.bindStructBytes(computeEncoder, &baseInstanceOffset, 6);
		if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
			[computeEncoder dispatchThreads: MTLSizeMake((NSUInteger)drawCount * vertexStride, 1, 1)
					 threadsPerThreadgroup: MTLSizeMake(computePipeline.threadExecutionWidth, 1, 1)];
		} else {
			[computeEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>((NSUInteger)drawCount * vertexStride, computePipeline.threadExecutionWidth), 1, 1)
					  threadsPerThreadgroup: MTLSizeMake(computePipeline.threadExecutionWidth, 1, 1)];
		}
	}

	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	return copiedBuffers;
}

static void bindIndirectZeroDivisorVertexBuffers(MVKCommandEncoder* cmdEncoder,
																					 MVKGraphicsStage stage,
																					 const MVKIndirectZeroDivisorVertexBuffers& copiedBuffers,
																					 uint32_t drawIndex) {
	for (const auto& copiedBuffer : copiedBuffers) {
		NSUInteger offset = copiedBuffer.allocation->_offset + (NSUInteger)drawIndex * copiedBuffer.stride;
		switch (stage) {
			case kMVKGraphicsStageVertex:
				[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBuffer: copiedBuffer.allocation->_mtlBuffer
																								 offset: offset
																								atIndex: copiedBuffer.mtlBufferIndex];
				break;
			case kMVKGraphicsStageRasterization:
				[cmdEncoder->_mtlRenderEncoder setVertexBuffer: copiedBuffer.allocation->_mtlBuffer
																							  offset: offset
																							 atIndex: copiedBuffer.mtlBufferIndex];
				break;
			default:
				assert(false);
				break;
		}
	}
}

#pragma mark -
#pragma mark MVKCmdDrawIndirect

VkResult MVKCmdDrawIndirect::setContent(MVKCommandBuffer* cmdBuff,
										VkBuffer buffer,
										VkDeviceSize offset,
										uint32_t drawCount,
										uint32_t stride) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_mtlIndirectBuffer = mvkBuffer->getMTLBuffer();
	_mtlIndirectBufferOffset = mvkBuffer->getMTLBufferOffset() + offset;
	_mtlIndirectBufferStride = stride;
	_drawCount = drawCount;
	_mtlCountBuffer = nil;
	_mtlCountBufferOffset = 0;

    // Validate
	auto& mtlFeats = cmdBuff->getMetalFeatures();
    if ( !mtlFeats.indirectDrawing ) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndirect(): The current device does not support indirect drawing.");
    }
	if (cmdBuff->_lastTessellationPipeline && !mtlFeats.indirectTessellationDrawing) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndirect(): The current device does not support indirect tessellated drawing.");
	}

	return VK_SUCCESS;
}

VkResult MVKCmdDrawIndirect::setContent(MVKCommandBuffer* cmdBuff,
											VkBuffer buffer,
											VkDeviceSize offset,
											VkBuffer countBuffer,
											VkDeviceSize countBufferOffset,
											uint32_t maxDrawCount,
											uint32_t stride) {
	VkResult result = setContent(cmdBuff, buffer, offset, maxDrawCount, stride);
	if (result != VK_SUCCESS) {
		return result;
	}
	MVKBuffer* mvkCountBuffer = (MVKBuffer*)countBuffer;
	_mtlCountBuffer = mvkCountBuffer->getMTLBuffer();
	_mtlCountBufferOffset = mvkCountBuffer->getMTLBufferOffset() + countBufferOffset;
	return VK_SUCCESS;
}

// Populates and encodes a MVKCmdDrawIndexedIndirect command, after populating indexed indirect buffers.
void MVKCmdDrawIndirect::encodeIndexedIndirect(MVKCommandEncoder* cmdEncoder,
														 id<MTLBuffer> indirectBuffer,
														 VkDeviceSize indirectBufferOffset,
														 uint32_t indirectBufferStride) {

	// Create an indexed indirect buffer to be populated from the non-indexed indirect buffer.
	uint32_t indirectIdxBuffStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	auto* indirectIdxBuff = cmdEncoder->getTempMTLBuffer(indirectIdxBuffStride * _drawCount, true);

	// Create an index buffer to be populated with synthetic indexes.
	MTLIndexType mtlIdxType = MTLIndexTypeUInt32;
	auto* vtxIdxBuff = cmdEncoder->getTempMTLBuffer(mvkMTLIndexTypeSizeInBytes(mtlIdxType) * kMVKMaxDrawIndirectVertexCount, true);
	MVKIndexMTLBufferBinding ibb;
	ibb.mtlIndexType = mtlIdxType;
	ibb.mtlBuffer = vtxIdxBuff->_mtlBuffer;
	ibb.offset = vtxIdxBuff->_offset;
	ibb.size = vtxIdxBuff->_length;

	// Schedule a compute action to populate indexed buffers from non-indexed buffers.
	cmdEncoder->encodeStoreActions(true);
	id<MTLComputeCommandEncoder> mtlConvertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectPopulateIndexesMTLComputePipelineState();
	state.bindPipeline(mtlConvertEncoder, mtlConvertState);
	state.bindBuffer(mtlConvertEncoder, indirectBuffer,              indirectBufferOffset,      0);
	state.bindBuffer(mtlConvertEncoder, indirectIdxBuff->_mtlBuffer, indirectIdxBuff->_offset, 1);
	state.bindStructBytes(mtlConvertEncoder, &indirectBufferStride,     2);
	state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
	state.bindBuffer(mtlConvertEncoder, ibb.mtlBuffer, ibb.offset, 4);
	if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
		[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
					 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
	} else {
		[mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
						  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
	}
	// Switch back to rendering now.
	cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);

	MVKCmdDrawIndexedIndirect diiCmd;
	diiCmd.setContent(cmdEncoder->_cmdBuffer,
					  indirectIdxBuff->_mtlBuffer,
					  indirectIdxBuff->_offset,
					  _drawCount,
					  indirectIdxBuffStride);
	diiCmd.encode(cmdEncoder, ibb);
}

void MVKCmdDrawIndirect::encode(MVKCommandEncoder* cmdEncoder) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) {
		encodeMetal4Indirect(cmdEncoder, _mtlIndirectBuffer, _mtlIndirectBufferOffset, _mtlIndirectBufferStride, _drawCount, _mtlCountBuffer, nullptr);
		return;
	}
#endif

	cmdEncoder->restartMetalRenderPassIfNeeded();
	id<MTLBuffer> indirectBuffer = _mtlIndirectBuffer;
	VkDeviceSize indirectBufferOffset = _mtlIndirectBufferOffset;
	uint32_t indirectBufferStride = _mtlIndirectBufferStride;

	if (_mtlCountBuffer && _drawCount > 0) {
		auto* convertedBuffer = encodeIndirectCountConversion(cmdEncoder,
				indirectBuffer,
				indirectBufferOffset,
				indirectBufferStride,
				_mtlCountBuffer,
				_mtlCountBufferOffset,
				_drawCount,
				false);
		indirectBuffer = convertedBuffer->_mtlBuffer;
		indirectBufferOffset = convertedBuffer->_offset;
		indirectBufferStride = sizeof(MTLDrawPrimitivesIndirectArguments);
	}

	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;
	// Metal doesn't support triangle fans, so encode it as indexed indirect triangles instead.
	if (cmdEncoder->getState().vkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN) {
		encodeIndexedIndirect(cmdEncoder, indirectBuffer, indirectBufferOffset, indirectBufferStride);
		return;
	}

	auto zeroDivisorBuffers = encodeIndirectZeroDivisorVertexBufferCopies(cmdEncoder,
			pipeline,
			indirectBuffer,
			indirectBufferOffset,
			indirectBufferStride,
			_drawCount,
			false);

    cmdEncoder->_isIndexedDraw = false;

    bool needsInstanceAdjustment = cmdEncoder->getSubpass()->isMultiview() &&
                                   cmdEncoder->getPhysicalDevice()->canUseInstancingForMultiview();
    // The indirect calls for dispatchThreadgroups:... and drawPatches:... have different formats.
    // We have to convert from the drawPrimitives:... format to them.
    // While we're at it, we can create the temporary output buffers once and reuse them
    // for each draw.
    const MVKMTLBufferAllocation* tempIndirectBuff = nullptr;
	const MVKMTLBufferAllocation* tcParamsBuff = nullptr;
    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
	VkDeviceSize paramsIncr = 0;

    id<MTLBuffer> mtlIndBuff = indirectBuffer;
    VkDeviceSize mtlIndBuffOfst = indirectBufferOffset;
    VkDeviceSize mtlParmBuffOfst = 0;
    NSUInteger vtxThreadExecWidth = 0;
    NSUInteger tcWorkgroupSize = 0;

    if (pipeline->isTessellationPipeline()) {
        // We can't read the indirect buffer CPU-side, since it may change between
        // encoding and execution. So we don't know how big to make the buffers.
        // We must assume an arbitrarily large number of vertices may be submitted.
        // But not too many, or we'll exhaust available VRAM.
        inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        vertexCount = kMVKMaxDrawIndirectVertexCount;
        patchCount = mvkCeilingDivide(vertexCount, inControlPointCount);
        VkDeviceSize indirectSize = (2 * sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments) + sizeof(MTLStageInRegionIndirectArguments)) * _drawCount;
		paramsIncr = 256;
		VkDeviceSize paramsSize = paramsIncr * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlIndBuffOfst = tempIndirectBuff->_offset;
		tcParamsBuff = cmdEncoder->getTempMTLBuffer(paramsSize, true);
        mtlParmBuffOfst = tcParamsBuff->_offset;
        if (pipeline->needsVertexOutputBuffer()) {
            vtxOutBuff = cmdEncoder->getTempMTLBuffer(vertexCount * 4 * dvcLimits.maxVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlOutputBuffer()) {
            tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlPatchOutputBuffer()) {
            tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
        }
        tcLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);

        vtxThreadExecWidth = pipeline->getTessVertexStageState().threadExecutionWidth;
        NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
        tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        while (tcWorkgroupSize > dvcLimits.maxComputeWorkGroupSize[0]) {
            sgSize >>= 1;
            tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        }
    } else if (needsInstanceAdjustment) {
        // In this case, we need to adjust the instance count for the views being drawn.
        VkDeviceSize indirectSize = sizeof(MTLDrawPrimitivesIndirectArguments) * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlIndBuffOfst = tempIndirectBuff->_offset;
    }

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(_drawCount * sizeof(uint32_t));

        auto* drawIDs = (uint32_t*)((char*)[tempDrawIDBuff->_mtlBuffer contents] + tempDrawIDBuff->_offset);
        for (uint32_t i = 0; i < _drawCount; i++) {
            drawIDs[i] = i;
        }
    }
    for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
        for (uint32_t s : stages) {
            auto stage = MVKGraphicsStage(s);
            id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
            if (drawIdx == 0 && stage == kMVKGraphicsStageVertex && pipeline->isTessellationPipeline()) {
                // We need the indirect buffers now. This must be done before finalizing
                // draw state, or the pipeline will get overridden. This is a good time
                // to do it, since it will require switching to compute anyway. Do it all
                // at once to get it over with.
				cmdEncoder->encodeStoreActions(true);
				mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
				id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectTessConvertBuffersMTLComputePipelineState(false);
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
				state.bindPipeline(mtlTessCtlEncoder, mtlConvertState);
				state.bindBuffer(mtlTessCtlEncoder, indirectBuffer,                indirectBufferOffset,      0);
				state.bindBuffer(mtlTessCtlEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer,     tcParamsBuff->_offset,     2);
				state.bindStructBytes(mtlTessCtlEncoder, &indirectBufferStride,     3);
				state.bindStructBytes(mtlTessCtlEncoder, &inControlPointCount,      4);
				state.bindStructBytes(mtlTessCtlEncoder, &outControlPointCount,     5);
				state.bindStructBytes(mtlTessCtlEncoder, &_drawCount,               6);
				state.bindStructBytes(mtlTessCtlEncoder, &vtxThreadExecWidth,       7);
				state.bindStructBytes(mtlTessCtlEncoder, &tcWorkgroupSize,          8);
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlTessCtlEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				}
            } else if (drawIdx == 0 && needsInstanceAdjustment) {
                // Similarly, for multiview, we need to adjust the instance count now.
                // Unfortunately, this requires switching to compute.
                // TODO: Consider using tile shaders to avoid this cost.
				cmdEncoder->encodeStoreActions(true);
				id<MTLComputeCommandEncoder> mtlConvertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
				id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectConvertBuffersMTLComputePipelineState(false);
				uint32_t viewCount = cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex());
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
				state.bindPipeline(mtlConvertEncoder, mtlConvertState);
				state.bindBuffer(mtlConvertEncoder, indirectBuffer,                indirectBufferOffset,      0);
				state.bindBuffer(mtlConvertEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindStructBytes(mtlConvertEncoder, &indirectBufferStride,     2);
				state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
				state.bindStructBytes(mtlConvertEncoder, &viewCount,                4);
                if (mtlFeats.nonUniformThreadgroups) {
					[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
					             threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                } else {
                    [mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                }
                // Switch back to rendering now, since we don't have compute stages to run anyway.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
            }

            if (drawIdx == 0 || pipeline->isTessellationPipeline() || needsInstanceAdjustment) {
                cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal
            }

			if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
					bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsDrawIdBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                              offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
					// We must assume we can read up to the maximum number of vertices.
					[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(0, 0, vertexCount, vertexCount)];
					[mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: mtlIndBuff
						                             indirectBufferOffset: mtlIndBuffOfst];
					mtlIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
					[mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
														 indirectBufferOffset: mtlIndBuffOfst
														threadsPerThreadgroup: MTLSizeMake(vtxThreadExecWidth, 1, 1)];
					mtlIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    break;
                case kMVKGraphicsStageTessControl:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                              offset: tcOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                              offset: tcPatchOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                    }
                    [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                          offset: tcLevelBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
					[mtlTessCtlEncoder setBuffer: tcParamsBuff->_mtlBuffer
										  offset: mtlParmBuffOfst
										 atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]];
					mtlParmBuffOfst += paramsIncr;
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                    }
                    [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
                                                         indirectBufferOffset: mtlIndBuffOfst
                                                        threadsPerThreadgroup: MTLSizeMake(tcWorkgroupSize, 1, 1)];
                    mtlIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    // Running this stage prematurely ended the render pass, so we have to start it up again.
                    // TODO: On iOS, maybe we could use a tile shader to avoid this.
                    cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                    break;
                case kMVKGraphicsStageRasterization:
					bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
                    if (pipeline->isTessellationPipeline()) {
						if (mtlFeats.indirectTessellationDrawing) {
							if (pipeline->needsTessCtlOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
																		offset: tcOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
							}
							if (pipeline->needsTessCtlPatchOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
																		offset: tcPatchOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
							}
							[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
																	offset: tcLevelBuff->_offset
																   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
							[cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
																				offset: tcLevelBuff->_offset
																		instanceStride: 0];
							[cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
													  patchIndexBuffer: nil
												patchIndexBufferOffset: 0
														indirectBuffer: mtlIndBuff
												  indirectBufferOffset: mtlIndBuffOfst];
						}

						mtlIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                    } else {
                        if (pipeline->needsDrawIdBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                    offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                                                   atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                        }
                        [cmdEncoder->_mtlRenderEncoder drawPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                       indirectBuffer: mtlIndBuff
                                                 indirectBufferOffset: mtlIndBuffOfst];
                        mtlIndBuffOfst += needsInstanceAdjustment ? sizeof(MTLDrawPrimitivesIndirectArguments) : indirectBufferStride;
                    }
                    break;
            }
        }
    }
}


#pragma mark -
#pragma mark MVKCmdDrawIndexedIndirect

typedef struct MVKVertexAdjustments {
	uint8_t mtlIndexType = MTLIndexTypeUInt16;	// Enum must match enum in shader
	bool isMultiView = false;
	bool isTriangleFan = false;
	bool isPrimRestart = true;
	bool isUint8Index = false;
	bool isProvokingVertexLast = false;

	bool needsAdjustment() { return isMultiView || isTriangleFan; }
} MVKVertexAdjustments;

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
											   VkBuffer buffer,
											   VkDeviceSize offset,
											   uint32_t drawCount,
											   uint32_t stride) {
	auto* mvkBuff = (MVKBuffer*)buffer;
	VkResult result = setContent(cmdBuff,
					  mvkBuff->getMTLBuffer(),
					  mvkBuff->getMTLBufferOffset() + offset,
					  drawCount,
					  stride);
#if MVK_BUILD_METAL4_FOUNDATION
    _metal4IndirectSourceBuffer = mvkBuff;
#endif
    return result;
}

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
										   id<MTLBuffer> indirectMTLBuff,
										   VkDeviceSize indirectMTLBuffOffset,
										   uint32_t drawCount,
										   uint32_t stride) {
#if MVK_BUILD_METAL4_FOUNDATION
    _metal4IndirectSourceBuffer = nullptr;  // Internal Metal-only buffers lack allocation proof.
#endif
	_mtlIndirectBuffer = indirectMTLBuff;
	_mtlIndirectBufferOffset = indirectMTLBuffOffset;
	_mtlIndirectBufferStride = stride;
	_drawCount = drawCount;
	_mtlCountBuffer = nil;
	_mtlCountBufferOffset = 0;

	// Validate
	auto& mtlFeats = cmdBuff->getMetalFeatures();
	if ( !mtlFeats.indirectDrawing ) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexedIndirect(): The current device does not support indirect drawing.");
	}
	if (cmdBuff->_lastTessellationPipeline && !mtlFeats.indirectTessellationDrawing) {
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdDrawIndexedIndirect(): The current device does not support indirect tessellated drawing.");
	}

	return VK_SUCCESS;
}

VkResult MVKCmdDrawIndexedIndirect::setContent(MVKCommandBuffer* cmdBuff,
													   VkBuffer buffer,
													   VkDeviceSize offset,
													   VkBuffer countBuffer,
													   VkDeviceSize countBufferOffset,
													   uint32_t maxDrawCount,
													   uint32_t stride) {
	VkResult result = setContent(cmdBuff, buffer, offset, maxDrawCount, stride);
	if (result != VK_SUCCESS) {
		return result;
	}
	MVKBuffer* mvkCountBuffer = (MVKBuffer*)countBuffer;
	_mtlCountBuffer = mvkCountBuffer->getMTLBuffer();
	_mtlCountBufferOffset = mvkCountBuffer->getMTLBufferOffset() + countBufferOffset;
	return VK_SUCCESS;
}

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4()) {
		encodeMetal4Indirect(cmdEncoder, _mtlIndirectBuffer, _mtlIndirectBufferOffset, _mtlIndirectBufferStride, _drawCount, _mtlCountBuffer, &cmdEncoder->getVkGraphics()._indexBuffer, _metal4IndirectSourceBuffer);
		return;
	}
#endif
	cmdEncoder->restartMetalRenderPassIfNeeded();
	encode(cmdEncoder, cmdEncoder->getVkGraphics()._indexBuffer);
}

void MVKCmdDrawIndexedIndirect::encode(MVKCommandEncoder* cmdEncoder, const MVKIndexMTLBufferBinding& ibbOrig) {

	id<MTLBuffer> indirectBuffer = _mtlIndirectBuffer;
	VkDeviceSize indirectBufferOffset = _mtlIndirectBufferOffset;
	uint32_t indirectBufferStride = _mtlIndirectBufferStride;
	if (_mtlCountBuffer && _drawCount > 0) {
		auto* convertedBuffer = encodeIndirectCountConversion(cmdEncoder,
				indirectBuffer,
				indirectBufferOffset,
				indirectBufferStride,
				_mtlCountBuffer,
				_mtlCountBufferOffset,
				_drawCount,
				true);
		indirectBuffer = convertedBuffer->_mtlBuffer;
		indirectBufferOffset = convertedBuffer->_offset;
		indirectBufferStride = sizeof(MTLDrawIndexedPrimitivesIndirectArguments);
	}

    cmdEncoder->_isIndexedDraw = true;

    MVKIndexMTLBufferBinding ibb = ibbOrig;
    if (ibb.vkIndexType == VK_INDEX_TYPE_UINT8) {
        auto* converted = convertUint8IndexBuffer(cmdEncoder, ibb);
        ibb.mtlBuffer = converted->_mtlBuffer;
        ibb.offset = converted->_offset;
        ibb.size = converted->_length;
    }

	MVKIndexMTLBufferBinding ibbTriFan = ibb;
	auto* pipeline = cmdEncoder->getGraphicsPipeline();
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	auto& dvcLimits = cmdEncoder->getDeviceProperties().limits;
	auto zeroDivisorBuffers = encodeIndirectZeroDivisorVertexBufferCopies(cmdEncoder,
			pipeline,
			indirectBuffer,
			indirectBufferOffset,
			indirectBufferStride,
			_drawCount,
			true);

	MVKVertexAdjustments vtxAdjmts{};
	vtxAdjmts.mtlIndexType = ibb.mtlIndexType;
	vtxAdjmts.isMultiView = (cmdEncoder->getSubpass()->isMultiview() &&
							 cmdEncoder->getPhysicalDevice()->canUseInstancingForMultiview());
	vtxAdjmts.isTriangleFan = cmdEncoder->getState().vkGraphics().getPrimitiveTopology() == VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN;
#if MVK_USE_METAL_PRIVATE_API
	// With private APIs for primitive restart, we need to handle disabled restart and raw Uint8 indices.
	vtxAdjmts.isPrimRestart = cmdEncoder->getState().vkGraphics().isPrimitiveRestartEnabled();
	vtxAdjmts.isUint8Index = ibb.vkIndexType == VK_INDEX_TYPE_UINT8;
	vtxAdjmts.isProvokingVertexLast = cmdEncoder->getState().vkGraphics().getProvokingVertexMode() == MTLProvokingVertexModeLast;
#endif

	// The indirect calls for dispatchThreadgroups:... and drawPatches:... have different formats.
    // We have to convert from the drawIndexedPrimitives:... format to them.
    // While we're at it, we can create the temporary output buffers once and reuse them
    // for each draw.
    const MVKMTLBufferAllocation* tempIndirectBuff = nullptr;
    const MVKMTLBufferAllocation* tcParamsBuff = nullptr;
    const MVKMTLBufferAllocation* vtxOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcPatchOutBuff = nullptr;
    const MVKMTLBufferAllocation* tcLevelBuff = nullptr;
    const MVKMTLBufferAllocation* vtxIndexBuff = nullptr;
    const MVKMTLBufferAllocation* tempDrawIDBuff = nullptr;
    uint32_t patchCount = 0, vertexCount = 0;
    uint32_t inControlPointCount = 0, outControlPointCount = 0;
	VkDeviceSize paramsIncr = 0;

	id<MTLBuffer> mtlIndBuff = indirectBuffer;
    VkDeviceSize mtlIndBuffOfst = indirectBufferOffset;
    VkDeviceSize mtlTempIndBuffOfst = indirectBufferOffset;
    VkDeviceSize mtlParmBuffOfst = 0;
    NSUInteger vtxThreadExecWidth = 0;
    NSUInteger tcWorkgroupSize = 0;

    if (pipeline->isTessellationPipeline()) {
        // We can't read the indirect buffer CPU-side, since it may change between
        // encoding and execution. So we don't know how big to make the buffers.
        // We must assume an arbitrarily large number of vertices may be submitted.
        // But not too many, or we'll exhaust available VRAM.
        inControlPointCount = cmdEncoder->getVkGraphics().getPatchControlPoints();
        outControlPointCount = pipeline->getOutputControlPointCount();
        vertexCount = kMVKMaxDrawIndirectVertexCount;
        patchCount = mvkCeilingDivide(vertexCount, inControlPointCount);
        VkDeviceSize indirectSize = (2 * sizeof(MTLDispatchThreadgroupsIndirectArguments) + sizeof(MTLDrawPatchIndirectArguments) + sizeof(MTLStageInRegionIndirectArguments)) * _drawCount;
		paramsIncr = 256;
		VkDeviceSize paramsSize = paramsIncr * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlTempIndBuffOfst = tempIndirectBuff->_offset;
        tcParamsBuff = cmdEncoder->getTempMTLBuffer(paramsSize, true);
        mtlParmBuffOfst = tcParamsBuff->_offset;
        if (pipeline->needsVertexOutputBuffer()) {
            vtxOutBuff = cmdEncoder->getTempMTLBuffer(vertexCount * 4 * dvcLimits.maxVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlOutputBuffer()) {
            tcOutBuff = cmdEncoder->getTempMTLBuffer(outControlPointCount * patchCount * 4 * dvcLimits.maxTessellationControlPerVertexOutputComponents, true);
        }
        if (pipeline->needsTessCtlPatchOutputBuffer()) {
            tcPatchOutBuff = cmdEncoder->getTempMTLBuffer(patchCount * 4 * dvcLimits.maxTessellationControlPerPatchOutputComponents, true);
        }
        tcLevelBuff = cmdEncoder->getTempMTLBuffer(patchCount * sizeof(MTLQuadTessellationFactorsHalf), true);
        vtxIndexBuff = cmdEncoder->getTempMTLBuffer(ibb.size, true);

        id<MTLComputePipelineState> vtxState;
        vtxState = ibb.mtlIndexType == MTLIndexTypeUInt16 ? pipeline->getTessVertexStageIndex16State() : pipeline->getTessVertexStageIndex32State();
        vtxThreadExecWidth = vtxState.threadExecutionWidth;

        NSUInteger sgSize = pipeline->getTessControlStageState().threadExecutionWidth;
        tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        while (tcWorkgroupSize > dvcLimits.maxComputeWorkGroupSize[0]) {
            sgSize >>= 1;
            tcWorkgroupSize = mvkLeastCommonMultiple(outControlPointCount, sgSize);
        }
    } else if (vtxAdjmts.needsAdjustment()) {
        // In this case, we need to adjust the instance count for the views being drawn.
        VkDeviceSize indirectSize = sizeof(MTLDrawIndexedPrimitivesIndirectArguments) * _drawCount;
        tempIndirectBuff = cmdEncoder->getTempMTLBuffer(indirectSize, true);
        mtlIndBuff = tempIndirectBuff->_mtlBuffer;
        mtlTempIndBuffOfst = tempIndirectBuff->_offset;
		if (vtxAdjmts.isTriangleFan) {
			auto* triVtxBuff = cmdEncoder->getTempMTLBuffer(mvkMTLIndexTypeSizeInBytes((MTLIndexType)ibb.mtlIndexType) * kMVKMaxDrawIndirectVertexCount, true);
			ibb.mtlBuffer = triVtxBuff->_mtlBuffer;
			ibb.offset = triVtxBuff->_offset;
		}
    }

	MVKPiplineStages stages;
    pipeline->getStages(stages);

    if (pipeline->needsDrawIdBuffer()) {
        tempDrawIDBuff = cmdEncoder->getTempMTLBuffer(_drawCount * sizeof(uint32_t));

        auto* drawIDs = (uint32_t*)((char*)[tempDrawIDBuff->_mtlBuffer contents] + tempDrawIDBuff->_offset);
        for (uint32_t i = 0; i < _drawCount; i++) {
            drawIDs[i] = i;
        }
    }
    for (uint32_t drawIdx = 0; drawIdx < _drawCount; drawIdx++) {
        for (uint32_t s : stages) {
            auto stage = MVKGraphicsStage(s);
            id<MTLComputeCommandEncoder> mtlTessCtlEncoder = nil;
            if (stage == kMVKGraphicsStageVertex && pipeline->isTessellationPipeline()) {
				cmdEncoder->encodeStoreActions(true);
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
                mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                // We need the indirect buffers now. This must be done before finalizing
                // draw state, or the pipeline will get overridden. This is a good time
                // to do it, since it will require switching to compute anyway. Do it all
                // at once to get it over with.
                if (drawIdx == 0) {
                    id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectTessConvertBuffersMTLComputePipelineState(true);
                    state.bindPipeline(mtlTessCtlEncoder, mtlConvertState);
                    state.bindBuffer(mtlTessCtlEncoder, indirectBuffer,                indirectBufferOffset,      0);
                    state.bindBuffer(mtlTessCtlEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
                    state.bindBuffer(mtlTessCtlEncoder, tcParamsBuff->_mtlBuffer,     tcParamsBuff->_offset,     2);
                    state.bindStructBytes(mtlTessCtlEncoder, &indirectBufferStride,     3);
                    state.bindStructBytes(mtlTessCtlEncoder, &inControlPointCount,      4);
                    state.bindStructBytes(mtlTessCtlEncoder, &outControlPointCount,     5);
                    state.bindStructBytes(mtlTessCtlEncoder, &_drawCount,               6);
                    state.bindStructBytes(mtlTessCtlEncoder, &vtxThreadExecWidth,       7);
                    state.bindStructBytes(mtlTessCtlEncoder, &tcWorkgroupSize,          8);
                    [mtlTessCtlEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
                                      threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
                }
                // We actually need to make a copy of the index buffer, because there's no way to tell Metal to
                // offset an index buffer from a value in an indirect buffer. This also
                // means that, to make a copy, we have to use a compute shader.
                state.bindPipeline(mtlTessCtlEncoder, cmdEncoder->getCommandEncodingPool()->getCmdDrawIndexedCopyIndexBufferMTLComputePipelineState((MTLIndexType)ibb.mtlIndexType));
                state.bindBuffer(mtlTessCtlEncoder, ibb.mtlBuffer,            ibb.offset,            0);
                state.bindBuffer(mtlTessCtlEncoder, vtxIndexBuff->_mtlBuffer, vtxIndexBuff->_offset, 1);
                state.bindBuffer(mtlTessCtlEncoder, indirectBuffer,            mtlIndBuffOfst,        2);
                [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
													 indirectBufferOffset: mtlTempIndBuffOfst + sizeof(MTLStageInRegionIndirectArguments)
                                                    threadsPerThreadgroup: MTLSizeMake(vtxThreadExecWidth, 1, 1)];
				mtlIndBuffOfst += indirectBufferStride;
            } else if (drawIdx == 0 && vtxAdjmts.needsAdjustment()) {
                // Similarly, for multiview, we need to adjust the instance count now.
                // Unfortunately, this requires switching to compute. Luckily, we don't also
                // have to copy the index buffer.
                // TODO: Consider using tile shaders to avoid this cost.
				cmdEncoder->encodeStoreActions(true);
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
				id<MTLComputeCommandEncoder> mtlConvertEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDrawIndirectConvertBuffers);
				id<MTLComputePipelineState> mtlConvertState = cmdEncoder->getCommandEncodingPool()->getCmdDrawIndirectConvertBuffersMTLComputePipelineState(true);
				uint32_t viewCount = cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex());
				state.bindPipeline(mtlConvertEncoder, mtlConvertState);
				state.bindBuffer(mtlConvertEncoder, indirectBuffer,                indirectBufferOffset,      0);
				state.bindBuffer(mtlConvertEncoder, tempIndirectBuff->_mtlBuffer, tempIndirectBuff->_offset, 1);
				state.bindStructBytes(mtlConvertEncoder, &indirectBufferStride,     2);
				state.bindStructBytes(mtlConvertEncoder, &_drawCount,               3);
				state.bindStructBytes(mtlConvertEncoder, &viewCount,                4);
				state.bindStructBytes(mtlConvertEncoder, &vtxAdjmts,                5);
				state.bindBuffer(mtlConvertEncoder, ibb.mtlBuffer,       ibb.offset,       6);
				state.bindBuffer(mtlConvertEncoder, ibbTriFan.mtlBuffer, ibbTriFan.offset, 7);
				if (mtlFeats.nonUniformThreadgroups) {
					[mtlConvertEncoder dispatchThreads: MTLSizeMake(_drawCount, 1, 1)
								 threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				} else {
					[mtlConvertEncoder dispatchThreadgroups: MTLSizeMake(mvkCeilingDivide<NSUInteger>(_drawCount, mtlConvertState.threadExecutionWidth), 1, 1)
									  threadsPerThreadgroup: MTLSizeMake(mtlConvertState.threadExecutionWidth, 1, 1)];
				}
				// Switch back to rendering now, since we don't have compute stages to run anyway.
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
            }

			if (drawIdx == 0 || pipeline->isTessellationPipeline() || vtxAdjmts.needsAdjustment()) {
				cmdEncoder->finalizeDrawState(stage);	// Ensure all updated state has been submitted to Metal
			}
			if ( !pipeline->hasValidMTLPipelineStates() ) { return; }	// Abort if this pipeline stage could not be compiled.

            switch (stage) {
                case kMVKGraphicsStageVertex:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                             offset: vtxOutBuff->_offset
                                            atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsDrawIdBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tempDrawIDBuff->_mtlBuffer
                                              offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                    }
					[mtlTessCtlEncoder setBuffer: vtxIndexBuff->_mtlBuffer
										  offset: vtxIndexBuff->_offset
										 atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::Index]];
					[mtlTessCtlEncoder setStageInRegion: MTLRegionMake2D(0, 0, vertexCount, vertexCount)];
					[mtlTessCtlEncoder setStageInRegionWithIndirectBuffer: mtlIndBuff
						                             indirectBufferOffset: mtlTempIndBuffOfst];
					mtlTempIndBuffOfst += sizeof(MTLStageInRegionIndirectArguments);
					// Bind the copied zero-divisor vertex data for this indirect command.
					bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
					[mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
														 indirectBufferOffset: mtlTempIndBuffOfst
														threadsPerThreadgroup: MTLSizeMake(vtxThreadExecWidth, 1, 1)];
					mtlTempIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    break;
                case kMVKGraphicsStageTessControl:
                    mtlTessCtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
                    if (pipeline->needsTessCtlOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcOutBuff->_mtlBuffer
                                              offset: tcOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::Output]];
                    }
                    if (pipeline->needsTessCtlPatchOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: tcPatchOutBuff->_mtlBuffer
                                              offset: tcPatchOutBuff->_offset
                                             atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::PatchOutput]];
                    }
                    [mtlTessCtlEncoder setBuffer: tcLevelBuff->_mtlBuffer
                                          offset: tcLevelBuff->_offset
                                         atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::TessLevel]];
					[mtlTessCtlEncoder setBuffer: tcParamsBuff->_mtlBuffer
										  offset: mtlParmBuffOfst
										 atIndex: pipeline->getImplicitBuffers(kMVKShaderStageTessCtl).ids[MVKImplicitBuffer::IndirectParams]];
					mtlParmBuffOfst += paramsIncr;
                    if (pipeline->needsVertexOutputBuffer()) {
                        [mtlTessCtlEncoder setBuffer: vtxOutBuff->_mtlBuffer
                                              offset: vtxOutBuff->_offset
                                             atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessCtlInputBufferBinding)];
                    }
                    [mtlTessCtlEncoder dispatchThreadgroupsWithIndirectBuffer: mtlIndBuff
                                                         indirectBufferOffset: mtlTempIndBuffOfst
                                                        threadsPerThreadgroup: MTLSizeMake(tcWorkgroupSize, 1, 1)];
                    mtlTempIndBuffOfst += sizeof(MTLDispatchThreadgroupsIndirectArguments);
                    // Running this stage prematurely ended the render pass, so we have to start it up again.
                    // TODO: On iOS, maybe we could use a tile shader to avoid this.
                    cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
                    break;
                case kMVKGraphicsStageRasterization:
                    if (pipeline->isTessellationPipeline()) {
						if (mtlFeats.indirectTessellationDrawing) {
							if (pipeline->needsTessCtlOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcOutBuff->_mtlBuffer
																		offset: tcOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalInputBufferBinding)];
							}
							if (pipeline->needsTessCtlPatchOutputBuffer()) {
								[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcPatchOutBuff->_mtlBuffer
																		offset: tcPatchOutBuff->_offset
																	   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalPatchInputBufferBinding)];
							}
							[cmdEncoder->_mtlRenderEncoder setVertexBuffer: tcLevelBuff->_mtlBuffer
																	offset: tcLevelBuff->_offset
																   atIndex: cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKTessEvalLevelBufferBinding)];
							[cmdEncoder->_mtlRenderEncoder setTessellationFactorBuffer: tcLevelBuff->_mtlBuffer
																				offset: tcLevelBuff->_offset
																		instanceStride: 0];
							[cmdEncoder->_mtlRenderEncoder drawPatches: outControlPointCount
							                          patchIndexBuffer: nil
							                    patchIndexBufferOffset: 0
							                            indirectBuffer: mtlIndBuff
							                      indirectBufferOffset: mtlTempIndBuffOfst];
						}

						mtlTempIndBuffOfst += sizeof(MTLDrawPatchIndirectArguments);
                    } else {
						bindIndirectZeroDivisorVertexBuffers(cmdEncoder, stage, zeroDivisorBuffers, drawIdx);
                        if (pipeline->needsDrawIdBuffer()) {
                            [cmdEncoder->_mtlRenderEncoder setVertexBuffer: tempDrawIDBuff->_mtlBuffer
                                                                    offset: tempDrawIDBuff->_offset + drawIdx * sizeof(uint32_t)
                                                                   atIndex: pipeline->getImplicitBuffers(kMVKShaderStageVertex).ids[MVKImplicitBuffer::DrawId]];
                        }
                        [cmdEncoder->_mtlRenderEncoder drawIndexedPrimitives: cmdEncoder->getMtlGraphics().getPrimitiveType()
                                                                   indexType: (MTLIndexType)ibb.mtlIndexType
                                                                 indexBuffer: ibb.mtlBuffer
                                                           indexBufferOffset: ibb.offset
                                                              indirectBuffer: mtlIndBuff
                                                        indirectBufferOffset: mtlTempIndBuffOfst];
                        mtlTempIndBuffOfst += vtxAdjmts.needsAdjustment() ? sizeof(MTLDrawIndexedPrimitivesIndirectArguments) : indirectBufferStride;
                    }
                    break;
            }
        }
    }
}
