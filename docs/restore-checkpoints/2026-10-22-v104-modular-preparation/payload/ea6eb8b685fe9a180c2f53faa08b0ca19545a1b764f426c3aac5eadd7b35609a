/*
 * MVKCommandBuffer.h
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

#pragma once

#include "MVKDevice.h"
#include "MVKCommand.h"
#include "MVKCommandEncoderState.h"
#include "MVKMTLBufferAllocation.h"
#include "MVKRenderPass.h"
#include "MVKCmdPipeline.h"
#include "MVKQueryPool.h"
#include "MVKSmallVector.h"
#include <unordered_map>
#include <unordered_set>
#if MVK_BUILD_METAL4_FOUNDATION
#include "MVKMetal4Submission.h"
#include "MVKMetal4ArgumentTable.h"
#include "MVKMetal4DrawPlan.h"
#include "MVKMetal4DependencyScopes.h"
#include "MVKMetal4QueryDependencies.h"
#endif

#if MVK_BUILD_METAL4_FOUNDATION
using MVKMetal4PreparedDependencies = MVKMetal4PreparedDependencySummary<
    MTLStageVertex, MTLStageFragment, MTLStageDispatch, MTLStageBlit>;
#endif

class MVKCommandPool;
class MVKQueueCommandBufferSubmission;
class MVKCommandEncoder;
class MVKCmdWriteTimestamp;
class MVKCommandEncodingPool;
class MVKRenderPass;
class MVKFramebuffer;
class MVKRenderSubpass;
class MVKQueryPool;
class MVKPipeline;
class MVKGraphicsPipeline;
class MVKComputePipeline;

typedef uint64_t MVKMTLCommandBufferID;


#pragma mark -
#pragma mark MVKCommandEncodingContext

struct BarrierFenceSlots {
	uint32_t updateDirtyBits = ~0;
	int update[kMVKBarrierStageCount] = {};
	int wait[kMVKBarrierStageCount][kMVKBarrierStageCount] = {};
};

/** Context for tracking information across multiple encodings. */
typedef struct MVKCommandEncodingContext {
	MVKVisibilityBuffer visibilityResultBuffer;
	BarrierFenceSlots fenceSlots;

	void syncFences(MVKDevice *device, id<MTLCommandBuffer> mtlCommandBuffer);
	MVKRenderPass* getRenderPass() { return _renderPass; }
	MVKFramebuffer* getFramebuffer() { return _framebuffer; }
	void setRenderingContext(MVKRenderPass* renderPass, MVKFramebuffer* framebuffer);
	VkRenderingFlags getRenderingFlags() { return _renderPass ? _renderPass->getRenderingFlags() : 0; }
	~MVKCommandEncodingContext();

private:
	MVKRenderPass* _renderPass = nullptr;
	MVKFramebuffer* _framebuffer = nullptr;
} MVKCommandEncodingContext;


#pragma mark -
#pragma mark MVKCurrentSubpassInfo

/** Tracks current render subpass information. */
typedef struct MVKCurrentSubpassInfo {
	MVKRenderPass* renderpass;
	uint32_t subpassIndex;
	uint32_t subpassViewMask;

	void beginRenderpass(MVKRenderPass* rp);
	void nextSubpass();
	void beginRendering(uint32_t viewMask);

private:
	void updateViewMask();
} MVKCurrentSubpassInfo;


#pragma mark -
#pragma mark MVKCommandBuffer

/** Represents a Vulkan command pool. */
class MVKCommandBuffer : public MVKDispatchableVulkanAPIObject,
						 public MVKDeviceTrackingMixin,
						 public MVKLinkableMixin<MVKCommandBuffer> {
public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_COMMAND_BUFFER; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_COMMAND_BUFFER_EXT; }

	/** Returns a pointer to the Vulkan instance. */
	MVKInstance* getInstance() override { return _device->getInstance(); }

	/** Prepares this instance to receive commands. */
	VkResult begin(const VkCommandBufferBeginInfo* pBeginInfo);

	/** Resets this instance to allow it to receive new commands. */
	VkResult reset(VkCommandBufferResetFlags flags);

	/** Closes this buffer from receiving commands and prepares for submission to a queue. */
	VkResult end();

	/** Adds the specified execution command at the end of this command buffer. */
	void addCommand(MVKCommand* command);

	/** Returns the number of commands currently in this command buffer. */
	uint32_t getCommandCount() { return _commandCount; }

	/** Returns the command pool backing this command buffer. */
	MVKCommandPool* getCommandPool() { return _commandPool; }

	/** Submit the commands in this buffer as part of the queue submission. */
	void submit(MVKQueueCommandBufferSubmission* cmdBuffSubmit, MVKCommandEncodingContext* pEncodingContext);

    /** Returns whether this command buffer can be submitted to a queue more than once. */
    bool getIsReusable() { return _isReusable; }

	/**
	 * If this is a secondary command buffer, returns the number of views inherited
	 * from the primary command buffer. If this is a primary command buffer, returns 1.
	 */
	uint32_t getViewCount() const;

	/** Updated as renderpass commands are added. */
	MVKCurrentSubpassInfo _currentSubpassInfo;

    /**
     * Metal requires that a visibility buffer is established when a render pass is created, 
     * but Vulkan permits it to be set during a render pass. When the first occlusion query
     * command is added, it sets this value so that it can be applied when the first renderpass
     * is begun.
     */
    bool _needsVisibilityResultMTLBuffer;

	/** Called when a MVKCmdExecuteCommands is added to this command buffer. */
	void recordExecuteCommands(MVKArrayRef<MVKCommandBuffer*const> secondaryCommandBuffers);

	/** Called when a timestamp command is added. */
	void recordTimestampCommand();


#pragma mark Tessellation constituent command management

	/** Update the last recorded pipeline with tessellation shaders */
	void recordBindPipeline(MVKCmdBindPipeline* mvkBindPipeline);

	/** The most recent recorded tessellation pipeline */
	MVKCmdBindPipeline* _lastTessellationPipeline;


#pragma mark Construction

	MVKCommandBuffer(MVKDevice* device) : MVKDeviceTrackingMixin(device) {}

	~MVKCommandBuffer() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKCommandBuffer() method.
     */
	VkCommandBuffer getVkCommandBuffer() { return (VkCommandBuffer)getVkHandle(); }

    /**
     * Retrieves the MVKCommandBuffer instance referenced by the VkCommandBuffer handle.
     * This is the compliment of the getVkCommandBuffer() method.
     */
    static MVKCommandBuffer* getMVKCommandBuffer(VkCommandBuffer vkCommandBuffer) {
        return (MVKCommandBuffer*)getDispatchableObject(vkCommandBuffer);
    }

protected:
	friend class MVKCommandEncoder;
	friend class MVKCommandPool;

	void propagateDebugName() override {}
	void init(const VkCommandBufferAllocateInfo* pAllocateInfo);
	bool canExecute();
	void clearPrefilledMTLCommandBuffer();
    void releaseCommands(MVKCommand* command, bool asyncReturn = false);
	void releaseRecordedCommands(bool asyncReturn = false);
	void flushImmediateCmdEncoder();
	void checkDeferredEncoding();
#if MVK_BUILD_METAL4_FOUNDATION
	bool beginMetal4PreparedRecording();
	void pauseMetal4PreparedRecording();
	void clearMetal4PreparedRecording();
    void releaseMetal4PreparedReplay(bool asyncReturn = false);
    void restoreMetal4PreparedReplay();
	std::shared_ptr<MVKMetal4Submission> _metal4PreparedSubmission;
	MVKCommandEncoder* _metal4PreparedEncoder = nullptr;
	std::unique_ptr<MVKCommandEncodingContext> _metal4PreparedContext;
	MVKMetal4PreparedDependencies _metal4PreparedSummary;
	MVKMetal4RecordingDependencies _metal4PreparedLocalOutput;
	bool _metal4EarlyRecording = false, _metal4StagingPass = false, _metal4PrefixPaused = false;
    MVKCmdWriteTimestamp* _metal4PreparedTimestamp = nullptr;
    std::vector<MVKCommand*> _metal4PreparedReplay;
    bool _metal4RetainPreparedReplay = false;
#endif
	void beginSecondaryEncoding(MVKCommandEncoder* cmdEncoder);

	MVKCommand* _head = nullptr;
	MVKCommand* _tail = nullptr;
	MVKSmallVector<VkFormat, kMVKDefaultAttachmentCount> _secondaryInheritanceColorAttachmentFormats;
	MVKSmallVector<uint32_t, kMVKDefaultAttachmentCount> _secondaryInheritanceColorAttachmentLocations;
	MVKSmallVector<uint32_t, kMVKDefaultAttachmentCount> _secondaryInheritanceColorAttachmentInputIndices;
	MVKCommandPool* _commandPool;
	VkCommandBufferInheritanceInfo _secondaryInheritanceInfo;
	VkCommandBufferInheritanceRenderingInfo _secondaryInheritanceRenderingInfo;
	VkRenderingAttachmentLocationInfo _secondaryInheritanceRenderingAttachmentLocationInfo;
	VkRenderingInputAttachmentIndexInfo _secondaryInheritanceRenderingInputAttachmentIndexInfo;
	id<MTLCommandBuffer> _prefilledMTLCmdBuffer = nil;
    MVKCommandEncodingContext* _immediateCmdEncodingContext = nullptr;
    MVKCommandEncoder* _immediateCmdEncoder = nullptr;
	uint32_t _commandCount;
	uint32_t _secondaryInheritanceDepthAttachmentInputIndex;
	uint32_t _secondaryInheritanceStencilAttachmentInputIndex;
	std::atomic_flag _isExecutingNonConcurrently;
	bool _isSecondary;
	bool _doesContinueRenderPass;
	bool _canAcceptCommands;
	bool _isReusable;
	bool _supportsConcurrentExecution;
	bool _wasExecuted;
	bool _hasStageCounterTimestampCommand;
	bool _hasSecondaryInheritanceInfo;
	bool _hasSecondaryInheritanceRenderingInfo;
	bool _hasSecondaryInheritanceColorAttachmentLocations;
	bool _hasSecondaryInheritanceColorAttachmentInputIndices;
	bool _hasSecondaryInheritanceDepthAttachmentInputIndex;
	bool _hasSecondaryInheritanceStencilAttachmentInputIndex;
};


#pragma mark -
#pragma mark MVKCommandEncoder

/*** Holds a collection of active queries for each query pool. */
typedef std::unordered_map<MVKQueryPool*, MVKSmallVector<uint32_t, kMVKDefaultQueryCount>> MVKActivatedQueries;

/** 
 * MVKCommandEncoder uses a visitor design pattern iterate the commands in a MVKCommandBuffer, 
 * tracking and caching dynamic encoding state, and encoding the commands onto Metal MTLCommandBuffers.
 *
 * Much of the dynamic cached encoding state has public access and is accessed directly
 * from the commands in the command buffer.
 */
class MVKCommandEncoder : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _cmdBuffer->getVulkanAPIObject(); };

	/** Encode commands from the command buffer onto the Metal command buffer. */
	void encode(id<MTLCommandBuffer> mtlCmdBuff, MVKCommandEncodingContext* pEncodingContext);
	bool isUsingMetal4() const {
#if MVK_BUILD_METAL4_FOUNDATION
		return _metal4Submission != nullptr;
#else
		return false;
#endif
	}
#if MVK_BUILD_METAL4_FOUNDATION
	void encode(MVKMetal4Submission& submission, MVKCommandEncodingContext* context);
	void beginMetal4Recording(MVKMetal4Submission& submission, MVKCommandEncodingContext* context, bool independent = false);
	void pauseMetal4Recording();
	void finishMetal4Recording();
	void resumeMetal4Recording(const MVKMetal4RecordingDependencies& dependencies, MVKCommandEncodingContext* context);
	const MVKMetal4PreparedDependencies& preparedDependencySummary() const { return _metal4PreparedSummary; }
	const MVKMetal4RecordingDependencies& recordingDependencies() const { return _metal4Dependencies; }
	void retainMetal4VulkanState(MVKVulkanAPIObject* object);
    bool isPreparingMetal4Timestamp() const { return _metal4PreparingTimestamp; }
    void setPreparingMetal4Timestamp(bool preparing) { _metal4PreparingTimestamp = preparing; }
    bool activateMetal4PreparedTimestamp(MVKQueryPool* pool, uint32_t query);
	MVKMetal4Submission* getMetal4Submission() { return _metal4Submission; }
	// Ordinary draw/dispatch preparation must succeed before accessing primary tables.
	bool ensureMetal4ArgumentTables();
	MVKMetal4ArgumentTables* getMetal4ArgumentTables() { return _metal4Tables; }
	/**
	 * Borrows a cleared Compute-only helper table of exactly the requested size.
	 * Encode its dispatches before requesting another helper table: Metal snapshots
	 * entries at dispatch, while this encoder's submission owns table/resource lifetime.
	 * Does not modify the application's primary Vertex/Fragment/Compute tables.
	 */
	MVKMetal4ArgumentTables* getMetal4ComputeHelperArgumentTables(const MVKMetal4ArgumentTables::Limits& limits);
	/**
	 * Primitive-conversion-only {5,0,0} helper. Reuse preserves its cached slots:
	 * the caller must successfully set all five buffers and bind before dispatch.
	 * It still invalidates application Compute bindings and has the same encoder-
	 * local lease and submission lifetime as the ordinary cleared helper above.
	 */
	MVKMetal4ArgumentTables* getMetal4PrimitiveConversionArgumentTables();
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
	MVKMetal4EncodingStats* getMetal4EncodingStats() { return _metal4StatsEnabled ? &_metal4Stats : nullptr; }
#else
	MVKMetal4EncodingStats* getMetal4EncodingStats() { return nullptr; }
#endif
	id<MTL4RenderCommandEncoder> getMetal4RenderEncoder() { return _mtl4RenderEncoder; }
	id<MTL4ComputeCommandEncoder> getMetal4ComputeEncoder(MVKCommandUse cmdUse, bool independentConversion = false,
	                                                    bool captureFollowingRender = false, MTLStages operationStages = 0,
	                                                    MVKMetal4QueryOperation queryOperation = MVKMetal4QueryOperation::None);
	void recordMetal4VisibilityWrite();
	void recordMetal4CounterResolve();
	void failMetal4Encoding(const char* reason);
	void setMetal4Barrier(VkPipelineStageFlags2 sources, VkPipelineStageFlags2 destinations,
	                     bool memoryDependency, bool imageDependency);
	bool hasMetal4EncodingFailed() const { return _metal4EncodingFailed; }
    bool metal4CanPreconvertBuffer(MVKBuffer* buffer);
    bool metal4CanPreconvertIndices(const MVKIndexMTLBufferBinding& binding);
    const MVKMetal4ConvertedDraw* getMetal4PreconvertedDraw(const MVKCommand* command) const;
    bool waitForMetal4PreconvertedDraw(id<MTL4RenderCommandEncoder> encoder);
    void preconvertMetal4Draws(MVKCommand* firstCommand);
#endif
    
    void beginEncoding(id<MTLCommandBuffer> mtlCmdBuff, MVKCommandEncodingContext* pEncodingContext);
    void encodeCommands(MVKCommand* command);
    void endEncoding();

	/** Encode commands from the specified secondary command buffer onto the Metal command buffer. */
	void encodeSecondary(MVKCommandBuffer* secondaryCmdBuffer);

	/** Begins a render pass and establishes initial draw state. */
	void beginRenderpass(MVKCommand* passCmd,
						 VkSubpassContents subpassContents,
						 MVKRenderPass* renderPass,
						 MVKFramebuffer* framebuffer,
						 const VkRect2D& renderArea,
						 MVKArrayRef<VkClearValue> clearValues,
						 MVKArrayRef<MVKImageView*> attachments,
						 MVKCommandUse cmdUse);

	/** Begins the next render subpass. */
	void beginNextSubpass(MVKCommand* subpassCmd, VkSubpassContents renderpassContents);

	/** Begins dynamic rendering. */
	void beginRendering(MVKCommand* rendCmd, const VkRenderingInfo* pRenderingInfo);

	/** Returns whether dynamic rendering is active. */
	bool isDynamicRendering();

	/** Begins a Metal render pass for the current render subpass. */
	void beginMetalRenderPass(MVKCommandUse cmdUse);

	/** 
	 * If a Metal render pass has started, and it needs to be restarted,
	 * then end the existing Metal render pass, and start a new one.
	 */
	void restartMetalRenderPassIfNeeded();

	/** If a render encoder is active, encodes store actions for all attachments to it. */
	void encodeStoreActions(bool storeOverride = false);

	/** Returns whether or not we are presently in a render pass. */
	bool isInRenderPass() { return _pEncodingContext->getRenderPass() != nullptr; }

	/** Returns the render subpass that is currently active. */
	MVKRenderSubpass* getSubpass();

	// A non-nil override is selected once, before the logical pass's first draw.
	id<MTLTexture> getRenderPassAttachmentOverride(MVKImageView* view);
	id<MTLTexture> getRenderPassAttachmentTexture(MVKImageView* view);

	/** Returns the sample count of the current render subpass. */
	VkSampleCountFlagBits getSampleCount() { return getSubpass()->getSampleCount(); }

	/** The extent of current framebuffer.*/
	VkExtent2D getFramebufferExtent();

	/** The layer count of current framebuffer.*/
	uint32_t getFramebufferLayerCount();

	/** Returns the index of the currently active multiview subpass, or zero if the current render pass is not multiview. */
	uint32_t getMultiviewPassIndex() { return _multiviewPassIndex; }

	/** Begins a Metal compute encoding. */
	void beginMetalComputeEncoding(MVKCommandUse cmdUse);

    /** Binds a pipeline to a bind point. */
    void bindPipeline(VkPipelineBindPoint pipelineBindPoint, MVKPipeline* pipeline);

	/** Encodes an operation to signal an event to a status. */
	void signalEvent(MVKEvent* mvkEvent, bool status);

	/** Clips the rect to ensure it fits inside the render area.  */
	VkRect2D clipToRenderArea(VkRect2D rect);

	/** Clips the scissor to ensure it fits inside the render area.  */
	MTLScissorRect clipToRenderArea(MTLScissorRect scissor);

	/** Updates the color attachment locations. */
	void updateColorAttachmentLocations(const MVKArrayRef<uint32_t> colorAttLocs);

	/** Updates the list of input attachments. */
	void updateAttachmentInputIndices(const MVKArrayRef<uint32_t> colorAttIdxs,
									  const uint32_t* pDepthInputAttachmentIndex,
									  const uint32_t* pStencilInputAttachmentIndex);

	/** Called by each graphics draw command to establish any outstanding state just prior to performing the draw. */
	void finalizeDrawState(MVKGraphicsStage stage);

    /** Called by each compute dispatch command to establish any outstanding state just prior to performing the dispatch. */
    void finalizeDispatchState();

	/** Ends the current renderpass. */
	void endRenderpass();

	/** Ends the current dymamic rendering. */
	void endRendering();

	/** 
	 * Ends all encoding operations on the current Metal command encoder.
	 *
	 * This must be called once all encoding is complete, and prior 
	 * to each switch between render, compute, and BLIT encoding.
	 */
	void endCurrentMetalEncoding();

	/** Ends encoding operations on the current Metal command encoder if it is a rendering encoder. */
	void endMetalRenderEncoding();

	/** 
	 * Returns the current Metal compute encoder for the specified use,
	 * which determines the label assigned to the returned encoder.
	 *
	 * If the current encoder is a compute encoder, the compute state being tracked can
	 * optionally be marked dirty. Otherwise, if the current encoder is not a compute
	 * encoder, this function ends the current encoder before beginning compute encoding.
	 */
	id<MTLComputeCommandEncoder> getMTLComputeEncoder(MVKCommandUse cmdUse);

	/**
	 * Returns the current Metal BLIT encoder for the specified use,
     * which determines the label assigned to the returned encoder.
	 *
	 * If the current encoder is not a BLIT encoder, this function ends 
     * the current encoder before beginning BLIT encoding.
	 */
	id<MTLBlitCommandEncoder> getMTLBlitEncoder(MVKCommandUse cmdUse);

	/**
	 * Returns the current Metal encoder, which may be any of the Metal render,
	 * compute, or Blit encoders, or nil if no encoding is currently occurring.
	 */
	id<MTLCommandEncoder> getMTLEncoder();

	/** Returns the command encoder state. */
	MVKCommandEncoderState& getState() { return _state; }

	/** Returns the Vulkan graphics encoder state. */
	const MVKVulkanGraphicsCommandEncoderState& getVkGraphics() const { return _state.vkGraphics(); }

	/** Returns the Metal graphics encoder state. */
	MVKMetalGraphicsCommandEncoderState& getMtlGraphics() { return _state.mtlGraphics(); }

	/** Returns the Vulkan compute encoder state. */
	const MVKVulkanComputeCommandEncoderState& getVkCompute() const { return _state.vkCompute(); }

	/** Returns the Metal compute encoder state. */
	MVKMetalComputeCommandEncoderState& getMtlCompute() { return _state.mtlCompute(); }

	/** Prepares state for a rasterization pipeline draw. */
	void prepareDraw() { _state.prepareDraw(_mtlRenderEncoder, *this); }

	/** Prepares the Metal compute pipeline state to dispatch the given stage of the Vulkan render pipeline. */
	void prepareRenderDispatch(MVKGraphicsStage stage) { _state.prepareRenderDispatch(_mtlComputeEncoder, *this, stage); }

	/** Prepares the Metal compute pipeline state to dispatch the given stage of the Vulkan render pipeline. */
	void prepareComputeDispatch() { _state.prepareComputeDispatch(_mtlComputeEncoder, *this); }

	/** Returns the graphics pipeline. */
	MVKGraphicsPipeline* getGraphicsPipeline() { return getVkGraphics()._pipeline; }

	/** Returns the compute pipeline. */
	MVKComputePipeline* getComputePipeline() { return getVkCompute()._pipeline; }

    /**
	 * Copy bytes into the Metal encoder at a Metal vertex buffer index, and optionally indicate
	 * that this binding might override a desriptor binding. If so, the descriptor binding will
	 * be marked dirty so that it will rebind before the next usage.
	 */
	void setVertexBytes(id<MTLRenderCommandEncoder> mtlEncoder, const void* bytes,
	                    NSUInteger length, uint32_t mtlBuffIndex);

	/**
	 * Copy bytes into the Metal encoder at a Metal fragment buffer index, and optionally indicate
	 * that this binding might override a desriptor binding. If so, the descriptor binding will
	 * be marked dirty so that it will rebind before the next usage.
	 */
	void setFragmentBytes(id<MTLRenderCommandEncoder> mtlEncoder, const void* bytes,
	                      NSUInteger length, uint32_t mtlBuffIndex);

	/**
	 * Copy bytes into the Metal encoder at a Metal compute buffer index, and optionally indicate
	 * that this binding might override a desriptor binding. If so, the descriptor binding will
	 * be marked dirty so that it will rebind before the next usage.
	 */
	void setComputeBytes(id<MTLComputeCommandEncoder> mtlEncoder, const void* bytes,
	                     NSUInteger length, uint32_t mtlBuffIndex);

    /** Get a temporary MTLBuffer that will be returned to a pool after the command buffer is finished. */
    const MVKMTLBufferAllocation* getTempMTLBuffer(NSUInteger length, bool isPrivate = false, bool isDedicated = false);

	/** Copy the bytes to a temporary MTLBuffer that will be returned to a pool after the command buffer is finished. */
	const MVKMTLBufferAllocation* copyToTempMTLBufferAllocation(const void* bytes, NSUInteger length, bool isDedicated = false);

    /** Returns the command encoding pool. */
    MVKCommandEncodingPool* getCommandEncodingPool();

	#pragma mark Barriers

	/** Encode waits in the current command encoder for the stage that corresponds to given use. */
	void encodeBarrierWaits(MVKCommandUse use);

	/** Update fences for the currently executing pipeline stage. */
	void encodeBarrierUpdates();

	/** Insert a new execution barrier */
	void setBarrier(uint64_t sourceStageMask, uint64_t destStageMask);

	/** Encode waits for a specific stage in given encoder. */
	void barrierWait(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages beforeStages);
	void barrierWait(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder);
	void barrierWait(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder);

	/** Encode update for a specific stage in given encoder. */
	void barrierUpdate(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages afterStages);
	void barrierUpdate(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder);
	void barrierUpdate(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder);

#pragma mark Queries

    /** Begins an occlusion query. */
    void beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags);

    /** Ends the current occlusion query. */
    void endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query);

    /** Marks a timestamp for the specified query. */
    void markTimestamp(MVKTimestampQueryPool* pQueryPool, uint32_t query,
                       VkPipelineStageFlags2 stage = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT);

    /** Reset a range of queries. */
    void resetQueries(MVKQueryPool* pQueryPool, uint32_t firstQuery, uint32_t queryCount);

#pragma mark Dynamic encoding state accessed directly

	/** Context for tracking information across multiple encodings. */
	MVKCommandEncodingContext* _pEncodingContext;

	/** The command buffer whose commands are being encoded. */
	MVKCommandBuffer* _cmdBuffer;

	/** The current Metal command buffer. */
	id<MTLCommandBuffer> _mtlCmdBuffer;

	/** The current Metal render encoder. */
	id<MTLRenderCommandEncoder> _mtlRenderEncoder;

	/** Tracks the state of command encoding. */
	MVKCommandEncoderState _state;

	/** Tracks the occlusion query state of the encoder. */
	MVKOcclusionQueryCommandEncoderState _occlusionQueryState;

    /** The size of the threadgroup for the compute shader. */
    MTLSize _mtlThreadgroupSize;

	/** Indicates whether the current render subpass is able to render to an array (layered) framebuffer. */
	bool _canUseLayeredRendering;

	/** Indicates whether the current draw is an indexed draw. */
	bool _isIndexedDraw;

#pragma mark Construction

	MVKCommandEncoder(MVKCommandBuffer* cmdBuffer,
					  MVKPrefillMetalCommandBuffersStyle prefillStyle = MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_NO_PREFILL);

	~MVKCommandEncoder() override;

protected:
#if MVK_BUILD_METAL4_FOUNDATION
	MVKMetal4ArgumentTables* acquireMetal4ComputeHelperArgumentTables(
		const MVKMetal4ArgumentTables::Limits& limits, bool completeOverwrite);
	void invalidateMetal4PrepassHandoff();
	void encodeMetal4TimestampSamples();
	void encodeMetal4PendingDependencies(id<MTL4CommandEncoder> encoder, MTLStages destinations, MTLStages conservativeSources = 0);
	MVKMetal4DependencyScopes<MTLStageVertex, MTLStageFragment, MTLStageDispatch, MTLStageBlit> _metal4Dependencies;
	// Current-pass producers cannot be satisfied by a prior-pass queue barrier.
	MVKMetal4DependencyScopes<MTLStageVertex, MTLStageFragment, MTLStageDispatch, MTLStageBlit> _metal4EncoderDependencies;
	// Prefix coverage actually encoded on this compute pass, rather than merely
	// the stages of operations it happens to contain.
	MVKMetal4DependencyScopes<MTLStageVertex, MTLStageFragment, MTLStageDispatch, MTLStageBlit> _metal4ComputeQueueDependencies;
	MTLStages _metal4ComputeEncodedStages = 0;
	uint64_t _metal4EncodingEpoch = 0;
	id<MTL4ComputeCommandEncoder> _metal4PrepassProducer = nil;
	uint64_t _metal4PrepassProducerEpoch = 0, _metal4PrepassLeadingDraws = 0;
	id<MTL4RenderCommandEncoder> _metal4DeferredPrepassRender = nil;
	uint64_t _metal4DeferredPrepassEpoch = 0;
	MVKMetal4Submission* _metal4Submission = nullptr;
	MVKMetal4PreparedDependencies _metal4PreparedSummary;
	bool _metal4CollectPreparedDependencies = false, _metal4PreparedRecording = false;
    bool _metal4PreparingTimestamp = false;
	std::unordered_set<MVKVulkanAPIObject*> _metal4VulkanStateOwners;
	MVKMetal4ArgumentTables* _metal4Tables = nullptr; // Borrowed submission-owned lease.
	std::vector<MVKMetal4ArgumentTables*> _metal4ComputeHelperTables;
	id<MTL4RenderCommandEncoder> _mtl4RenderEncoder = nil;
	id<MTL4ComputeCommandEncoder> _mtl4ComputeEncoder = nil;
	bool _metal4EncodingFailed = false;
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
	bool _metal4StatsEnabled = false;
	MVKMetal4EncodingStats _metal4Stats;
#endif
	bool _metal4StoreActionsSet = false;
	bool _metal4EndingRenderEncoding = false;
    std::unordered_map<const MVKCommand*, MVKMetal4ConvertedDraw> _metal4PreconvertedDraws;
    bool _metal4IndependentConversions = false;
	std::vector<std::pair<MVKMTLBufferAllocation*, std::shared_ptr<void>>> _metal4CancelledAllocations;
	std::vector<std::function<void()>> _metal4QueryCompletions;
	void beginMetal4RenderPass(MTLRenderPassDescriptor* descriptor, MVKCommandUse cmdUse,
	                           uint64_t capturedEpoch = 0, uint64_t leadingOrdinaryDraws = 0);
#endif
    void addActivatedQueries(MVKQueryPool* pQueryPool, uint32_t query, uint32_t queryCount);
    void finishQueries();
	void setSubpass(MVKCommand* passCmd, VkSubpassContents subpassContents, uint32_t subpassIndex, MVKCommandUse cmdUse);
	void clearRenderArea(MVKCommandUse cmdUse);
	bool hasMoreMultiviewPasses();
	void beginNextMultiviewPass();
	void encodeCommandsImpl(MVKCommand* command);
	bool prepareRenderPassAttachmentBackings();
	bool prepareVisibilityResultBuffer(MTLRenderPassDescriptor* descriptor);
	void encodeGPUCounterSample(MVKGPUCounterQueryPool* mvkQryPool, uint32_t sampleIndex, MVKCounterSamplingFlags samplingPoints);
	void encodeTimestampStageCounterSamples();
	id<MTLFence> getStageCountersMTLFence();
	NSString* getMTLRenderCommandEncoderName(MVKCommandUse cmdUse);
	template<typename T> void retainIfImmediatelyEncoding(T& mtlEnc);
	template<typename T> void endMetalEncoding(T& mtlEnc);
	id<MTLFence> getBarrierStageFence(MVKBarrierStage stage);

	typedef struct GPUCounterQuery {
		MVKGPUCounterQueryPool* queryPool = nullptr;
		uint32_t query = 0;
	} GPUCounterQuery;

	VkRect2D _renderArea;
	MVKCommand* _lastMultiviewPassCmd;
    MVKActivatedQueries* _pActivatedQueries;
	MVKSmallVector<GPUCounterQuery, 16> _timestampStageCounterQueries;
	MVKSmallVector<VkClearValue, kMVKDefaultAttachmentCount> _clearValues;
	MVKSmallVector<MVKImageView*, kMVKDefaultAttachmentCount> _attachments;
	struct AttachmentBacking { MVKImageView* view; id<MTLTexture> texture; };
	MVKSmallVector<AttachmentBacking, kMVKDefaultAttachmentCount> _attachmentBackings;
	bool _attachmentBackingFailed = false;
	bool _visibilityResultBufferFailed = false;
	id<MTLComputeCommandEncoder> _mtlComputeEncoder;
	id<MTLBlitCommandEncoder> _mtlBlitEncoder;
	id<MTLFence> _stageCountersMTLFence;
	MVKPrefillMetalCommandBuffersStyle _prefillStyle;
	VkSubpassContents _subpassContents;
	uint32_t _renderSubpassIndex;
	uint32_t _multiviewPassIndex;
    uint32_t _flushCount;
	MVKCommandUse _mtlComputeEncoderUse;
	uint32_t _mtlComputeEncoderStages;
	MVKCommandUse _mtlBlitEncoderUse;
	bool _isRenderingEntireAttachment;
	bool _hasMTLRenderEncoderVisibilityResultBuffer;
};


#pragma mark -
#pragma mark Support functions

/** Returns a name, suitable for use as a MTLRenderCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLRenderCommandEncoderLabel(MVKCommandUse cmdUse);

/** Returns a name, suitable for use as a MTLBlitCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLBlitCommandEncoderLabel(MVKCommandUse cmdUse);

/** Returns a name, suitable for use as a MTLComputeCommandEncoder label, based on the MVKCommandUse. */
NSString* mvkMTLComputeCommandEncoderLabel(MVKCommandUse cmdUse);
