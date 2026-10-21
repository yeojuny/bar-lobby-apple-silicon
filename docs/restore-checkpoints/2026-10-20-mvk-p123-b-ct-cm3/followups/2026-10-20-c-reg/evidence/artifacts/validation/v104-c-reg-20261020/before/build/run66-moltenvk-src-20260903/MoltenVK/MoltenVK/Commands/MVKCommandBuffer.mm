/*
 * MVKCommandBuffer.mm
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

#include "MVKCommandBuffer.h"
#include "MVKBackendTimeline.h"
#include "MVKFramebuffer.h"
#include "MVKCommandPool.h"
#include "MVKQueue.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"
#include "MVKFoundation.h"
#include "MVKCmdDraw.h"
#include "MVKCmdRendering.h"
#include "MVKCmdQueries.h"
#include <sys/mman.h>

using namespace std;


#pragma mark -
#pragma mark MVKCommandEncodingContext

// Sets the rendering objects, releasing the old objects, and retaining the new objects.
// Retaining the new is performed first, in case the old and new are the same object.
// With dynamic rendering, the objects are transient and only live as long as the
// duration of the active renderpass. To make it transient, it is released by the calling
// code after it has been retained here, so that when it is released again here at the
// end of the renderpass, it will automatically be destroyed. App-created objects are
// not released by the calling code, and will not be destroyed by the release here.
void MVKCommandEncodingContext::setRenderingContext(MVKRenderPass* renderPass, MVKFramebuffer* framebuffer) {

	if (renderPass) { renderPass->retain(); }
	if (_renderPass) { _renderPass->release(); }
	_renderPass = renderPass;

	if (framebuffer) { framebuffer->retain(); }
	if (_framebuffer) { _framebuffer->release(); }
	_framebuffer = framebuffer;
}

void MVKCommandEncodingContext::syncFences(MVKDevice *device, id<MTLCommandBuffer> mtlCommandBuffer) {
	if (!device->hasResidencySet()) return;

	// Synchronize all stages to their fences at index 0, which will be waited on in the next command buffer.
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = fenceSlots.update[i];
		if (!fenceIndex) continue;

		auto encoder = [mtlCommandBuffer blitCommandEncoder];
		[encoder waitForFence:device->getFence((MVKBarrierStage)i, fenceIndex)];
		[encoder updateFence:device->getFence((MVKBarrierStage)i, 0)];
		[encoder endEncoding];
	}
}

// Release rendering objects in case this instance is destroyed before ending the current renderpass.
MVKCommandEncodingContext::~MVKCommandEncodingContext() {
	setRenderingContext(nullptr, nullptr);
}


#pragma mark -
#pragma mark MVKCurrentSubpassInfo

void MVKCurrentSubpassInfo::beginRenderpass(MVKRenderPass* rp) {
	renderpass = rp;
	subpassIndex = 0;
	updateViewMask();
}
void MVKCurrentSubpassInfo::nextSubpass() {
	subpassIndex++;
	updateViewMask();
}
void MVKCurrentSubpassInfo::beginRendering(uint32_t viewMask) {
	renderpass = nullptr;
	subpassIndex = 0;
	subpassViewMask = viewMask;
}
void MVKCurrentSubpassInfo::updateViewMask() {
	subpassViewMask = renderpass ? renderpass->getSubpass(subpassIndex)->getViewMask() : 0;
}


#pragma mark -
#pragma mark MVKCommandBuffer

VkResult MVKCommandBuffer::begin(const VkCommandBufferBeginInfo* pBeginInfo) {
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
    auto* cost = mvkBackendCostTimeline();
    double recordStart = cost ? cost->clock() : 0;
#endif

	reset(0);
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
    if (cost) { cost->recordingBegin(this, recordStart, _isSecondary ? MVKCostSecondary : 0u); }
#endif

	clearConfigurationResult();
	_canAcceptCommands = true;

	VkCommandBufferUsageFlags usage = pBeginInfo->flags;
	_isReusable = !mvkAreAllFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
	_supportsConcurrentExecution = mvkAreAllFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT);
#if MVK_BUILD_METAL4_FOUNDATION
	_metal4EarlyRecording = mvkUseMetal4() && !_isSecondary && !_isReusable && !_supportsConcurrentExecution;
#endif

	// If this is a secondary command buffer, and contains inheritance info, set the inheritance info and determine
	// whether it contains render pass continuation info. Otherwise, clear the inheritance info, and ignore it.
	// Also check for and set any dynamic rendering inheritance info. The color format array must be copied locally.
	const VkCommandBufferInheritanceInfo* pInheritInfo = (_isSecondary ? pBeginInfo->pInheritanceInfo : nullptr);
	const VkCommandBufferInheritanceRenderingInfo* pInheritRendInfo = nullptr;
	const VkRenderingAttachmentLocationInfo* pInheritAttLocInfo = nullptr;
	const VkRenderingInputAttachmentIndexInfo* pInheritInpAttIdxInfo = nullptr;
	_hasSecondaryInheritanceInfo = mvkSetOrClear(&_secondaryInheritanceInfo, pInheritInfo);
	if (_hasSecondaryInheritanceInfo) {
		for (const auto* next = (VkBaseInStructure*)_secondaryInheritanceInfo.pNext; next; next = next->pNext) {
			switch (next->sType) {
				case VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO:
					pInheritRendInfo = (VkCommandBufferInheritanceRenderingInfo*)next;
					break;
				case VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_LOCATION_INFO:
					pInheritAttLocInfo = (VkRenderingAttachmentLocationInfo*)next;
					break;
				case VK_STRUCTURE_TYPE_RENDERING_INPUT_ATTACHMENT_INDEX_INFO:
					pInheritInpAttIdxInfo = (VkRenderingInputAttachmentIndexInfo*)next;
					break;
				default:
					break;
			}
		}
	}

	_doesContinueRenderPass = mvkAreAllFlagsEnabled(usage, VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT) && _hasSecondaryInheritanceInfo;

	_hasSecondaryInheritanceRenderingInfo = mvkSetOrClear(&_secondaryInheritanceRenderingInfo, pInheritRendInfo);
	if (_hasSecondaryInheritanceRenderingInfo) {
		_secondaryInheritanceColorAttachmentFormats.assign(_secondaryInheritanceRenderingInfo.pColorAttachmentFormats,
														   _secondaryInheritanceRenderingInfo.pColorAttachmentFormats + _secondaryInheritanceRenderingInfo.colorAttachmentCount);
		_secondaryInheritanceRenderingInfo.pColorAttachmentFormats = _secondaryInheritanceColorAttachmentFormats.data();
	}

	if (pInheritAttLocInfo) {
		_secondaryInheritanceColorAttachmentLocations.assign(pInheritAttLocInfo->pColorAttachmentLocations,
															 pInheritAttLocInfo->pColorAttachmentLocations + pInheritAttLocInfo->colorAttachmentCount);
		_hasSecondaryInheritanceColorAttachmentLocations = true;
	}

	if (pInheritInpAttIdxInfo) {
		if (pInheritInpAttIdxInfo->pColorAttachmentInputIndices) {
			_secondaryInheritanceColorAttachmentInputIndices.assign(pInheritInpAttIdxInfo->pColorAttachmentInputIndices,
																	pInheritInpAttIdxInfo->pColorAttachmentInputIndices + pInheritInpAttIdxInfo->colorAttachmentCount);
			_hasSecondaryInheritanceColorAttachmentInputIndices = true;
		}

		if (pInheritInpAttIdxInfo->pDepthInputAttachmentIndex) {
			_secondaryInheritanceDepthAttachmentInputIndex = *pInheritInpAttIdxInfo->pDepthInputAttachmentIndex;
			_hasSecondaryInheritanceDepthAttachmentInputIndex = true;
		}

		if (pInheritInpAttIdxInfo->pStencilInputAttachmentIndex) {
			_secondaryInheritanceStencilAttachmentInputIndex = *pInheritInpAttIdxInfo->pStencilInputAttachmentIndex;
			_hasSecondaryInheritanceStencilAttachmentInputIndex = true;
		}
	}

    if(_device->shouldPrefillMTLCommandBuffers() && !(_isSecondary || _supportsConcurrentExecution)
#if MVK_BUILD_METAL4_FOUNDATION
		&& !mvkUseMetal4()
#endif
	) {
		@autoreleasepool {
			_prefilledMTLCmdBuffer = [_commandPool->getMTLCommandBuffer(kMVKCommandUseBeginCommandBuffer, 0) retain];    // retained
			auto prefillStyle = getMVKConfig().prefillMetalCommandBuffers;
			if (prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING ||
				prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING_NO_AUTORELEASE ) {
				_immediateCmdEncodingContext = new MVKCommandEncodingContext;
				_immediateCmdEncoder = new MVKCommandEncoder(this, prefillStyle);
				_immediateCmdEncoder->beginEncoding(_prefilledMTLCmdBuffer, _immediateCmdEncodingContext);
			}
		}
    }

    VkResult result = getConfigurationResult();
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
    if (cost && result != VK_SUCCESS) { cost->recordingEnd(this, result, true); }
#endif
    return result;
}

void MVKCommandBuffer::beginSecondaryEncoding(MVKCommandEncoder* cmdEncoder) {
	if ( !_isSecondary ) { return; }

	if (_hasSecondaryInheritanceColorAttachmentLocations) {
		cmdEncoder->updateColorAttachmentLocations(_secondaryInheritanceColorAttachmentLocations.contents());
	}
}

void MVKCommandBuffer::releaseCommands(MVKCommand* command, bool asyncReturn) {
    while(command) {
        MVKCommand* nextCommand = command->_next; // Establish next before returning current to pool.
#if MVK_BUILD_METAL4_FOUNDATION
        if (_metal4RetainPreparedReplay) {
            command->_next = nullptr;
            _metal4PreparedReplay.push_back(command);
            command = nextCommand;
            continue;
        }
#endif
        auto* pool = command->getTypePool(getCommandPool());
        if (asyncReturn) { pool->returnObjectAsync(command); }
        else { pool->returnObject(command); }
        command = nextCommand;
    }
}

void MVKCommandBuffer::releaseRecordedCommands(bool asyncReturn) {
    releaseCommands(_head, asyncReturn);
	_head = nullptr;
	_tail = nullptr;
}

void MVKCommandBuffer::flushImmediateCmdEncoder() {
    if(_immediateCmdEncoder) {
        _immediateCmdEncoder->endEncoding();
        delete _immediateCmdEncoder;
        _immediateCmdEncoder = nullptr;
        
        delete _immediateCmdEncodingContext;
        _immediateCmdEncodingContext = nullptr;
    }
}

VkResult MVKCommandBuffer::reset(VkCommandBufferResetFlags flags) {
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
    if (auto* cost = mvkBackendCostTimeline()) { cost->recordingReset(this); }
#endif
#if MVK_BUILD_METAL4_FOUNDATION
	clearMetal4PreparedRecording();
#endif
    flushImmediateCmdEncoder();
	clearPrefilledMTLCommandBuffer();
	releaseRecordedCommands();
	_secondaryInheritanceInfo = {};
	_hasSecondaryInheritanceInfo = false;
	_secondaryInheritanceRenderingInfo = {};
	_hasSecondaryInheritanceRenderingInfo = false;
	_secondaryInheritanceColorAttachmentFormats.clear();
	_secondaryInheritanceColorAttachmentLocations.clear();
	_hasSecondaryInheritanceColorAttachmentLocations = false;
	_secondaryInheritanceColorAttachmentInputIndices.clear();
	_hasSecondaryInheritanceColorAttachmentInputIndices = false;
	_secondaryInheritanceDepthAttachmentInputIndex = 0;
	_hasSecondaryInheritanceDepthAttachmentInputIndex = false;
	_secondaryInheritanceStencilAttachmentInputIndex = 0;
	_hasSecondaryInheritanceStencilAttachmentInputIndex = false;
	_doesContinueRenderPass = false;
	_canAcceptCommands = false;
	_isReusable = false;
	_supportsConcurrentExecution = false;
	_wasExecuted = false;
	_isExecutingNonConcurrently.clear();
	_commandCount = 0;
	_currentSubpassInfo = {};
	_needsVisibilityResultMTLBuffer = false;
	_hasStageCounterTimestampCommand = false;
	_lastTessellationPipeline = nullptr;
	setConfigurationResult(VK_NOT_READY);

	if (mvkAreAllFlagsEnabled(flags, VK_COMMAND_BUFFER_RESET_RELEASE_RESOURCES_BIT)) {
		// TODO: what are we releasing or returning here?
	}

	return VK_SUCCESS;
}

VkResult MVKCommandBuffer::end() {
	_canAcceptCommands = false;
#if MVK_BUILD_METAL4_FOUNDATION
	// A leading timestamp followed only by CPU state stays on the ordinary
	// replay list. It never acquired native storage or needs early activation.
	if (!_metal4PreparedEncoder) { _metal4PreparedTimestamp = nullptr; }
	pauseMetal4PreparedRecording();
	if (_metal4PreparedEncoder && !_head && !_metal4PreparedTimestamp && wasConfigurationSuccessful()) {
		_metal4PreparedEncoder->finishMetal4Recording();
		NSError* error = nil;
		if (!_metal4PreparedSubmission->end(&error)) {
			setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not end prepared Metal 4 recording."));
		}
		delete _metal4PreparedEncoder; _metal4PreparedEncoder = nullptr;
		_metal4PreparedContext.reset();
	}
#endif
    
    flushImmediateCmdEncoder();
	checkDeferredEncoding();

    VkResult result = getConfigurationResult();
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
    if (auto* cost = mvkBackendCostTimeline()) { cost->recordingEnd(this, result); }
#endif
    return result;
}

void MVKCommandBuffer::checkDeferredEncoding() {
	if ( !_prefilledMTLCmdBuffer ) { return; }

	if (getMVKConfig().prefillMetalCommandBuffers == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_DEFERRED_ENCODING) {
		@autoreleasepool {
			MVKCommandEncodingContext encodingContext;
			MVKCommandEncoder encoder(this);
			encoder.encode(_prefilledMTLCmdBuffer, &encodingContext);
			if (isUsingMetalArgumentBuffers()) {
				encodingContext.syncFences(getDevice(), _prefilledMTLCmdBuffer);
			}

			// Once encoded onto Metal, if this command buffer is not reusable, we don't need the
			// MVKCommand instances anymore, so release them in order to reduce memory pressure.
			if ( !_isReusable ) { releaseRecordedCommands(); }
		}
	}
}

void MVKCommandBuffer::addCommand(MVKCommand* command) {
    if ( !_canAcceptCommands ) {
        setConfigurationResult(reportError(VK_NOT_READY, "Command buffer cannot accept commands before vkBeginCommandBuffer() is called."));
        return;
    }

	_commandCount++;
#if MVK_BUILD_METAL4_FOUNDATION
    if (_metal4EarlyRecording) {
        auto policy = command->getMetal4RecordPolicy();
        if (policy == MVKMetal4RecordPolicy::LeadingTimestamp) {
            // Stage the first timestamp until ordinary work warrants native
            // preparation. A timestamp-only prefix before a Deferred command
            // otherwise allocates a pack and bridge that submit may not need.
            if (_commandCount == 1 && !_metal4PreparedEncoder) {
                _metal4PreparedTimestamp = static_cast<MVKCmdWriteTimestamp*>(command);
                command->_next = nullptr;
                _head = _tail = command;
                return;
            }
            policy = MVKMetal4RecordPolicy::Deferred;
        }
        if (policy == MVKMetal4RecordPolicy::Deferred ||
            (policy == MVKMetal4RecordPolicy::Draw && !_metal4StagingPass)) {
            if (!_metal4PreparedEncoder) { _metal4PreparedTimestamp = nullptr; }
            pauseMetal4PreparedRecording();
            _metal4EarlyRecording = false;
        } else {
            command->_next = nullptr;
            bool stage = _metal4StagingPass || policy == MVKMetal4RecordPolicy::BeginRenderPass ||
                (policy == MVKMetal4RecordPolicy::State && !_metal4PreparedEncoder);
            if (stage) {
                if (_tail) { _tail->_next = command; } else { _head = command; }
                _tail = command;
                if (policy == MVKMetal4RecordPolicy::BeginRenderPass) { _metal4StagingPass = true; }
                if (policy == MVKMetal4RecordPolicy::EndRenderPass) {
                    _metal4StagingPass = false;
                    if (beginMetal4PreparedRecording()) {
                        @autoreleasepool {
                            _metal4PreparedEncoder->encodeCommands(_head);
                            _metal4PreparedEncoder->pauseMetal4Recording();
                        }
                        if (wasConfigurationSuccessful()) { releaseRecordedCommands(); }
                    } else { _metal4EarlyRecording = false; }
                }
                return;
            }
            if (beginMetal4PreparedRecording()) {
                if (_head) {
                    _tail->_next = command;
                    _tail = command;
                    @autoreleasepool { _metal4PreparedEncoder->encodeCommands(_head); }
                    releaseRecordedCommands();
                } else {
                    @autoreleasepool { _metal4PreparedEncoder->encodeCommands(command); }
                    releaseCommands(command);
                }
                return;
            }
            _metal4EarlyRecording = false;
        }
    }
#endif

    if(_immediateCmdEncoder) {
        _immediateCmdEncoder->encodeCommands(command);
        if( !_isReusable ) {
            releaseCommands(command);
            return;
        }
    }

    if (_tail) { _tail->_next = command; }
    command->_next = nullptr;
    _tail = command;
    if ( !_head ) { _head = command; }
}

#if MVK_BUILD_METAL4_FOUNDATION
bool MVKCommandBuffer::beginMetal4PreparedRecording() {
    if (_metal4PreparedSubmission) { return wasConfigurationSuccessful(); }
    auto pool = _device->getMetal4RecordingPool();
    if (!pool) { return false; }
    NSError* error = nil;
    _metal4PreparedSubmission = pool->begin(&error);
    if (!_metal4PreparedSubmission) {
        setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not begin prepared Metal 4 recording."));
        return false;
    }
    _metal4PreparedContext = std::make_unique<MVKCommandEncodingContext>();
    _metal4PreparedEncoder = new MVKCommandEncoder(this);
    _metal4PreparedEncoder->beginMetal4Recording(*_metal4PreparedSubmission, _metal4PreparedContext.get(), true);
    if (_metal4PreparedTimestamp) {
        // The staged timestamp is always the first original command. Encode
        // it once, before the state/work that triggered preparation, without
        // publishing query availability until actual submission order is known.
        assert(_head == _metal4PreparedTimestamp);
        _head = _head->_next;
        if (!_head) { _tail = nullptr; }
        _metal4PreparedTimestamp->_next = nullptr;
        _metal4RetainPreparedReplay = true;
        _metal4PreparedEncoder->setPreparingMetal4Timestamp(true);
        @autoreleasepool { _metal4PreparedEncoder->encodeCommands(_metal4PreparedTimestamp); }
        _metal4PreparedEncoder->setPreparingMetal4Timestamp(false);
        releaseCommands(_metal4PreparedTimestamp);
    }
    return true;
}
void MVKCommandBuffer::pauseMetal4PreparedRecording() {
    if (!_metal4PreparedEncoder || _metal4PrefixPaused) { return; }
    @autoreleasepool { _metal4PreparedEncoder->pauseMetal4Recording(); }
    _metal4PreparedSummary = _metal4PreparedEncoder->preparedDependencySummary();
    _metal4PreparedLocalOutput = _metal4PreparedEncoder->recordingDependencies();
    _metal4PrefixPaused = true;
}
void MVKCommandBuffer::clearMetal4PreparedRecording() {
    if (_metal4PreparedEncoder) {
        @autoreleasepool { _metal4PreparedEncoder->pauseMetal4Recording(); }
        delete _metal4PreparedEncoder; _metal4PreparedEncoder = nullptr;
    }
    _metal4PreparedContext.reset();
    _metal4PreparedSubmission.reset();
    _metal4PreparedSummary = {};
    _metal4EarlyRecording = _metal4StagingPass = _metal4PrefixPaused = false;
    releaseMetal4PreparedReplay();
}
void MVKCommandBuffer::releaseMetal4PreparedReplay(bool asyncReturn) {
    _metal4RetainPreparedReplay = false;
    _metal4PreparedTimestamp = nullptr;
    for (auto* command : _metal4PreparedReplay) { releaseCommands(command, asyncReturn); }
    _metal4PreparedReplay.clear();
}
void MVKCommandBuffer::restoreMetal4PreparedReplay() {
    // Restore the exact original prefix before the unencoded suffix. Nothing
    // has been published by the prepared timestamp when activation rejects it.
    _metal4RetainPreparedReplay = false;
    _metal4PreparedTimestamp = nullptr;
    for (size_t i = 1; i < _metal4PreparedReplay.size(); ++i) {
        _metal4PreparedReplay[i - 1]->_next = _metal4PreparedReplay[i];
    }
    if (!_metal4PreparedReplay.empty()) {
        _metal4PreparedReplay.back()->_next = _head;
        if (!_tail) { _tail = _metal4PreparedReplay.back(); }
        _head = _metal4PreparedReplay.front();
        _metal4PreparedReplay.clear();
    }
    clearMetal4PreparedRecording();
}
#endif

void MVKCommandBuffer::submit(MVKQueueCommandBufferSubmission* cmdBuffSubmit,
							  MVKCommandEncodingContext* pEncodingContext) {
	if ( !canExecute() ) { return; }

#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdBuffSubmit->isUsingMetal4()) {
        if (_commandPool->getQueueFamilyIndex() == cmdBuffSubmit->_queue->getQueueFamilyIndex() &&
            _metal4PreparedTimestamp && wasConfigurationSuccessful()) {
            if (_metal4PreparedTimestamp->activateMetal4PreparedTimestamp(_metal4PreparedEncoder)) {
                _metal4RetainPreparedReplay = false;
                _metal4PreparedTimestamp = nullptr;
            } else {
                restoreMetal4PreparedReplay();
            }
        }
        if (_commandPool->getQueueFamilyIndex() != cmdBuffSubmit->_queue->getQueueFamilyIndex()) {
            setConfigurationResult(reportError(VK_ERROR_INITIALIZATION_FAILED, "Prepared command buffer queue family differs from its destination."));
        } else if (_metal4PreparedSubmission) {
            pauseMetal4PreparedRecording();
            if (cmdBuffSubmit->closeActiveMetal4Recording()) {
                const auto incoming = cmdBuffSubmit->_metal4Dependencies;
                if (cmdBuffSubmit->appendMetal4Boundary(_metal4PreparedSummary.resolveEntry(incoming))) {
                    auto output = _metal4PreparedSummary.resolveExit(incoming, _metal4PreparedLocalOutput);
                    auto prepared = _metal4PreparedSubmission;
                    if (_metal4PreparedEncoder) {
                        _metal4PreparedEncoder->resumeMetal4Recording(output, pEncodingContext);
                        @autoreleasepool {
                            _metal4PreparedEncoder->encodeCommands(_head);
                            _metal4PreparedEncoder->finishMetal4Recording();
                        }
                        output = prepared->dependencyScopes();
                        NSError* error = nil;
                        if (wasConfigurationSuccessful() && !prepared->end(&error)) {
                            setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "Could not finish prepared Metal 4 suffix."));
                        }
                        delete _metal4PreparedEncoder; _metal4PreparedEncoder = nullptr;
                        _metal4PreparedContext.reset();
                    }
                    if (wasConfigurationSuccessful()) {
                        cmdBuffSubmit->_metal4Dependencies = output;
                        cmdBuffSubmit->_metal4Records.push_back(std::move(prepared));
                        _metal4PreparedSubmission.reset();
                        releaseMetal4PreparedReplay(true);
                        releaseRecordedCommands(true);
                    }
                }
            }
        } else if (auto* submission = cmdBuffSubmit->getActiveMetal4Submission()) {
            if (cmdBuffSubmit->_metal4Records.empty() && cmdBuffSubmit->_queue->metal4CounterEntryNeedsFullWait()) {
                submission->requireFullCounterEntry();
            }
            submission->dependencyScopes() = cmdBuffSubmit->_metal4Dependencies;
            { MVKCommandEncoder encoder(this); encoder.encode(*submission, pEncodingContext); }
            cmdBuffSubmit->_metal4Dependencies = submission->dependencyScopes();
            cmdBuffSubmit->_activeMetal4HasCommands = true;
            if (!_isReusable && wasConfigurationSuccessful()) { releaseRecordedCommands(true); }
        }
		if (!_supportsConcurrentExecution) { _isExecutingNonConcurrently.clear(); }
		return;
	}
#endif

	if (_prefilledMTLCmdBuffer) {
		cmdBuffSubmit->setActiveMTLCommandBuffer(_prefilledMTLCmdBuffer);
		clearPrefilledMTLCommandBuffer();
	} else {
		MVKCommandEncoder encoder(this);
		encoder.encode(cmdBuffSubmit->getActiveMTLCommandBuffer(), pEncodingContext);
	}

    if (!_isReusable && wasConfigurationSuccessful()) { releaseRecordedCommands(true); }
	if ( !_supportsConcurrentExecution ) { _isExecutingNonConcurrently.clear(); }
}

bool MVKCommandBuffer::canExecute() {
	if (_isSecondary) {
		setConfigurationResult(reportError(VK_NOT_READY, "Secondary command buffers may not be submitted directly to a queue."));
		return false;
	}
	if ( !_isReusable && _wasExecuted ) {
		setConfigurationResult(reportError(VK_NOT_READY, "Command buffer does not support execution more that once."));
		return false;
	}

	// Do this test last so that _isExecutingNonConcurrently is only set if everything else passes
	if ( !_supportsConcurrentExecution && _isExecutingNonConcurrently.test_and_set()) {
		setConfigurationResult(reportError(VK_NOT_READY, "Command buffer does not support concurrent execution."));
		return false;
	}

	_wasExecuted = true;
	return wasConfigurationSuccessful();
}

// Return the number of bits set in the view mask, with a minimum value of 1.
uint32_t MVKCommandBuffer::getViewCount() const {
	uint32_t viewMask = 0;
	if (_doesContinueRenderPass) {
		MVKRenderPass* inheritedRenderPass = (MVKRenderPass*)_secondaryInheritanceInfo.renderPass;
		if (inheritedRenderPass) {
			viewMask = inheritedRenderPass->getSubpass(_secondaryInheritanceInfo.subpass)->getViewMask();
		} else {
			viewMask = _secondaryInheritanceRenderingInfo.viewMask;
		}
	} else {
		viewMask = _currentSubpassInfo.subpassViewMask;
	}
	return max(__builtin_popcount(viewMask), 1);
}

void MVKCommandBuffer::clearPrefilledMTLCommandBuffer() {

	// Metal command buffers do not return to their pool on release, nor do they support the
	// concept of a reset. In order to become available again in their pool, they must pass
	// through the commit step. This is unfortunate because if the app adds commands to this
	// command buffer and then chooses to reset it instead of submit it, we risk committing
	// a prefilled Metal command buffer that the app did not intend to submit, potentially
	// causing unexpected side effects. But unfortunately there is nothing else we can do.
	if (_prefilledMTLCmdBuffer && _prefilledMTLCmdBuffer.status == MTLCommandBufferStatusNotEnqueued) {
		[_prefilledMTLCmdBuffer commit];
	}

	[_prefilledMTLCmdBuffer release];
	_prefilledMTLCmdBuffer = nil;
}

#pragma mark Construction

// Initializes this instance after it has been created or retrieved from a pool.
void MVKCommandBuffer::init(const VkCommandBufferAllocateInfo* pAllocateInfo) {
	_commandPool = (MVKCommandPool*)pAllocateInfo->commandPool;
	_isSecondary = (pAllocateInfo->level == VK_COMMAND_BUFFER_LEVEL_SECONDARY);

	reset(0);
}

MVKCommandBuffer::~MVKCommandBuffer() {
	reset(0);
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
    if (auto* cost = mvkBackendCostTimeline()) { cost->forget(this, MVKBackendCostObjectKind::CommandBuffer); }
#endif
}

// Promote the initial visibility buffer and indication of timestamp use from the secondary buffers.
void MVKCommandBuffer::recordExecuteCommands(MVKArrayRef<MVKCommandBuffer*const> secondaryCommandBuffers) {
	for (MVKCommandBuffer* cmdBuff : secondaryCommandBuffers) {
		if (cmdBuff->_needsVisibilityResultMTLBuffer) { _needsVisibilityResultMTLBuffer = true; }
		if (cmdBuff->_hasStageCounterTimestampCommand) { _hasStageCounterTimestampCommand = true; }
	}
}

// Track whether a stage-based timestamp command has been added, so we know
// to update the timestamp command fence when ending a Metal command encoder.
void MVKCommandBuffer::recordTimestampCommand() {
	_hasStageCounterTimestampCommand = mvkIsAnyFlagEnabled(getMetalFeatures().counterSamplingPoints, MVK_COUNTER_SAMPLING_AT_PIPELINE_STAGE);
}


#pragma mark -
#pragma mark Tessellation constituent command management

void MVKCommandBuffer::recordBindPipeline(MVKCmdBindPipeline* mvkBindPipeline) {
	_lastTessellationPipeline = mvkBindPipeline->isTessellationPipeline() ? mvkBindPipeline : nullptr;
}


#pragma mark -
#pragma mark MVKCommandEncoder

#if MVK_BUILD_METAL4_FOUNDATION
void MVKCommandEncoder::failMetal4Encoding(const char* reason) {
	if (_metal4EncodingFailed) { return; }
	invalidateMetal4PrepassHandoff();
	_metal4EncodingFailed = true;
	_cmdBuffer->setConfigurationResult(reportError(VK_ERROR_FEATURE_NOT_PRESENT,
		"Experimental native Metal 4 encoding failed: %s", reason));
}

void MVKCommandEncoder::encode(MVKMetal4Submission& submission, MVKCommandEncodingContext* context) {
    uint64_t startTime = getPerformanceTimestamp();
    beginMetal4Recording(submission, context);
    encodeCommands(_cmdBuffer->_head);
    finishMetal4Recording();
    addPerformanceInterval(getPerformanceStats().queue.commandBufferEncoding, startTime);
}

void MVKCommandEncoder::beginMetal4Recording(MVKMetal4Submission& submission, MVKCommandEncodingContext* context, bool independent) {
    _metal4PreparedRecording = independent;
    _metal4CollectPreparedDependencies = independent;
    _metal4PreparedSummary = {};
	_metal4Submission = &submission;
	_metal4Tables = nullptr;
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
	_metal4StatsEnabled = mvkMetal4StatsEnabled();
	_metal4Stats = {};
#endif
	_metal4ComputeHelperTables.clear();
    _metal4PreconvertedDraws.clear();
    _metal4IndependentConversions = false;
	_metal4Dependencies = submission.dependencyScopes();
	if (independent) { _metal4Dependencies.satisfy(_metal4Dependencies.all, _metal4Dependencies.all); }
	_metal4EncoderDependencies = {};
	_metal4EncoderDependencies.satisfy(_metal4EncoderDependencies.all, _metal4EncoderDependencies.all);
	_metal4ComputeQueueDependencies = {};
	_metal4ComputeQueueDependencies.satisfy(_metal4ComputeQueueDependencies.all, _metal4ComputeQueueDependencies.all);
	_metal4ComputeEncodedStages = 0;
	_metal4EncodingEpoch = 0;
	_metal4PrepassProducer = nil;
	_metal4PrepassProducerEpoch = _metal4PrepassLeadingDraws = 0;
	_metal4DeferredPrepassRender = nil;
	_metal4DeferredPrepassEpoch = 0;
	beginEncoding(nil, context);
}

void MVKCommandEncoder::pauseMetal4Recording() {
    endCurrentMetalEncoding();
    _metal4PreconvertedDraws.clear();
    _lastMultiviewPassCmd = nullptr;
}
void MVKCommandEncoder::resumeMetal4Recording(const MVKMetal4RecordingDependencies& dependencies, MVKCommandEncodingContext* context) {
    _metal4CollectPreparedDependencies = false;
    _metal4Dependencies = dependencies;
    _pEncodingContext = context;
}
void MVKCommandEncoder::retainMetal4VulkanState(MVKVulkanAPIObject* object) {
    if (_metal4PreparedRecording && object && _metal4VulkanStateOwners.insert(object).second) { object->retain(); }
}
bool MVKCommandEncoder::activateMetal4PreparedTimestamp(MVKQueryPool* pool, uint32_t query) {
    if (!pool->tryActivateMetal4PreparedTimestamp(query)) { return false; }
    addActivatedQueries(pool, query, 1);
    return true;
}
void MVKCommandEncoder::finishMetal4Recording() {
    endEncoding();
    auto& submission = *_metal4Submission;
	// endEncoding has published current-pass helper obligations. Even an empty
	// Vulkan command buffer must carry the recording's unresolved destinations.
	submission.dependencyScopes() = _metal4Dependencies;
	// Each native draw/dispatch has captured its table entries. The next
	// sequential Vulkan encoder may reuse the primary tables after all current
	// encoders end; uploads and referenced resources remain owned by this batch.
	if (_metal4Tables && !_metal4EncodingFailed) {
		NSError* error = nil;
		if (!submission.releaseArgumentTables(_metal4Tables, &error)) {
			failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Could not return native primary argument tables.");
		}
		_metal4Tables = nullptr;
	}
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
	if (_metal4StatsEnabled) { submission.addEncodingStats(_metal4Stats); }
#endif
}

bool MVKCommandEncoder::ensureMetal4ArgumentTables() {
	if (_metal4EncodingFailed) { return false; }
	if (_metal4Tables) { return true; }
	NSError* error = nil;
	MVKMetal4ArgumentTables::Limits limits;
	// Transfer-only and internal-helper recordings need no primary stage tables.
	// A lease lasts through this encoder; its storage stays owned until retirement.
	_metal4Tables = _metal4Submission->acquireArgumentTables(limits.bufferCount, limits.textureCount, limits.samplerCount, false, &error);
	if (!_metal4Tables) {
		failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Could not lease native argument tables.");
		return false;
	}
	return true;
}

static constexpr MTLStages kMVKMetal4AllStages = MTLStageVertex | MTLStageFragment | MTLStageDispatch | MTLStageBlit;
using MVKMetal4QueryPolicy = MVKMetal4QueryDependencies<MTLStageVertex, MTLStageFragment, MTLStageDispatch, MTLStageBlit>;

// Vulkan stages describe API operations, not just the Metal encoder that
// implements them. Primitive preparation executes in Dispatch, and transfers
// can use blit, compute, or render helpers. Preserve all of those producers and
// consumers; an unrecognized extension stage retains the conservative scope.
static MTLStages mvkMetal4Stages(VkPipelineStageFlags2 stages, bool source) {
	stages = mvkMetal4NormalizePipelineStages(stages, VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, source);
	constexpr VkPipelineStageFlags2 vertex = VK_PIPELINE_STAGE_2_VERTEX_INPUT_BIT |
		VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT | VK_PIPELINE_STAGE_2_INDEX_INPUT_BIT |
		VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT | VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT |
		VK_PIPELINE_STAGE_2_PRE_RASTERIZATION_SHADERS_BIT |
		VK_PIPELINE_STAGE_2_TESSELLATION_CONTROL_SHADER_BIT |
		VK_PIPELINE_STAGE_2_TESSELLATION_EVALUATION_SHADER_BIT | VK_PIPELINE_STAGE_2_GEOMETRY_SHADER_BIT;
	constexpr VkPipelineStageFlags2 fragment = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT |
		VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT |
		VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
	constexpr VkPipelineStageFlags2 transfer = VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT |
		VK_PIPELINE_STAGE_2_COPY_BIT | VK_PIPELINE_STAGE_2_BLIT_BIT |
		VK_PIPELINE_STAGE_2_RESOLVE_BIT | VK_PIPELINE_STAGE_2_CLEAR_BIT;
	constexpr VkPipelineStageFlags2 broad = transfer | VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT |
		VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT | VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT |
		VK_PIPELINE_STAGE_2_HOST_BIT;
	constexpr VkPipelineStageFlags2 known = vertex | fragment | broad |
		VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT | VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
	if ((stages & ~known) || (stages & broad)) { return kMVKMetal4AllStages; }
	MTLStages result = 0;
	if (stages & (vertex | VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT)) { result |= MTLStageVertex | MTLStageDispatch; }
	if (stages & (fragment | VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT)) { result |= MTLStageFragment; }
	if (stages & VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT) { result |= MTLStageDispatch; }
	return result;
}

void MVKCommandEncoder::encodeMetal4PendingDependencies(id<MTL4CommandEncoder> encoder,
        MTLStages destinations, MTLStages conservativeSources) {
    if (_metal4CollectPreparedDependencies) { _metal4PreparedSummary.recordConsumption(destinations); }
    _metal4Dependencies.add(conservativeSources, destinations, true);
    _metal4Dependencies.encode(destinations, [&](uint64_t sources, uint64_t consumers, bool visible) {
        auto visibility = visible ? MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias
                                  : MTL4VisibilityOptionNone;
        [encoder barrierAfterQueueStages:sources beforeStages:consumers visibilityOptions:visibility];
        if (encoder == _mtl4ComputeEncoder) {
            _metal4ComputeQueueDependencies.add(sources, consumers, visible);
        }
    });
}

void MVKCommandEncoder::recordMetal4VisibilityWrite() {
    if (!_mtl4RenderEncoder) {
        failMetal4Encoding("Native visibility writes require an active render encoder."); return;
    }
    MVKMetal4QueryPolicy::addOutputs(_metal4EncoderDependencies, MVKMetal4QueryOperation::VisibilityWrite);
}

void MVKCommandEncoder::recordMetal4CounterResolve() {
    if (_mtl4RenderEncoder || _mtl4ComputeEncoder) {
        failMetal4Encoding("Native counter resolve requires ended encoders."); return;
    }
    // Command-buffer-level Blit work is already a prior producer for the next encoder.
    MVKMetal4QueryPolicy::addOutputs(_metal4Dependencies, MVKMetal4QueryOperation::CounterResolve);
}

void MVKCommandEncoder::setMetal4Barrier(VkPipelineStageFlags2 sources, VkPipelineStageFlags2 destinations,
		bool memoryDependency, bool imageDependency) {
	invalidateMetal4PrepassHandoff();
	const MTLStages sourceStages = mvkMetal4Stages(sources, true), destinationStages = mvkMetal4Stages(destinations, false);
	const MTL4VisibilityOptions visibility = memoryDependency
		? MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias : MTL4VisibilityOptionNone;
	// Keep destination-specific obligations until an actual consumer barrier.
	// An empty intervening encoder is never treated as a dependency bridge.
	_metal4Dependencies.add(sourceStages, destinationStages, memoryDependency);
	if (_mtl4ComputeEncoder) {
		const MTLStages local = MTLStageDispatch | MTLStageBlit;
		encodeMetal4PendingDependencies(_mtl4ComputeEncoder, destinationStages & local);
		// Queue scope excludes this encoder. Preserve local work separately,
		// and retain its sources for all future consumer stages.
		_metal4EncoderDependencies.add(sourceStages & local, destinationStages, memoryDependency);
		if ((sourceStages & local) && (destinationStages & local)) {
			[_mtl4ComputeEncoder barrierAfterEncoderStages:(sourceStages & local)
				beforeEncoderStages:(destinationStages & local) visibilityOptions:visibility];
		}
		if (auto* stats = getMetal4EncodingStats()) { ++stats->computeBarrierContinuations; }
		return;
	}
	if (_mtl4RenderEncoder && !imageDependency && !(sourceStages & MTLStageFragment)) {
		// Apple silicon supports a Vertex producer inside the same render pass.
		// Fragment/tile producers and image layout dependencies still require
		// a stored pass boundary. Prior passes require their own queue scope.
		const MTLStages local = MTLStageVertex | MTLStageFragment;
		encodeMetal4PendingDependencies(_mtl4RenderEncoder, destinationStages & local);
		_metal4EncoderDependencies.add(sourceStages & MTLStageVertex, destinationStages, memoryDependency);
		if ((sourceStages & MTLStageVertex) && (destinationStages & local)) {
			[_mtl4RenderEncoder barrierAfterEncoderStages:MTLStageVertex
				beforeEncoderStages:(destinationStages & local) visibilityOptions:visibility];
		}
		return;
	}
	if (_mtl4RenderEncoder) { encodeStoreActions(true); }
	endCurrentMetalEncoding();
}

void MVKCommandEncoder::invalidateMetal4PrepassHandoff() {
	if (_metal4PrepassProducer || _metal4DeferredPrepassRender) {
		// If the exact render pass is still open, restore the ordinary queue
		// dependency now. A replacement encoder consumes its pending scopes.
		if (_metal4DeferredPrepassRender && _metal4DeferredPrepassRender == _mtl4RenderEncoder &&
		    _metal4DeferredPrepassEpoch == _metal4EncodingEpoch) {
			[_mtl4RenderEncoder barrierAfterQueueStages:kMVKMetal4AllStages
				beforeStages:(MTLStageVertex | MTLStageFragment)
				visibilityOptions:(MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias)];
		}
		if (auto* stats = getMetal4EncodingStats()) { ++stats->prepassHandoffFallbacks; }
	}
	_metal4PrepassProducer = nil;
	_metal4PrepassProducerEpoch = _metal4PrepassLeadingDraws = 0;
	_metal4DeferredPrepassRender = nil;
	_metal4DeferredPrepassEpoch = 0;
}

bool MVKCommandEncoder::waitForMetal4PreconvertedDraw(id<MTL4RenderCommandEncoder> encoder) {
	if (_metal4EncodingFailed) { return false; }
	if (!encoder || encoder != _mtl4RenderEncoder) {
		failMetal4Encoding("Prepared primitive draw lost its native render encoder."); return false;
	}
	if (_metal4DeferredPrepassRender == encoder && _metal4DeferredPrepassEpoch == _metal4EncodingEpoch) {
		// Earlier-queue obligations were captured before the dedicated prepass.
		// Its scratch indices and indirect records become visible at this first
		// real consumer, after any graphics/helper preparation has completed.
		[encoder barrierAfterQueueStages:MTLStageDispatch beforeStages:MTLStageVertex
			visibilityOptions:(MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias)];
		_metal4DeferredPrepassRender = nil;
		_metal4DeferredPrepassEpoch = 0;
		if (auto* stats = getMetal4EncodingStats()) { ++stats->prepassDeferredWaits; }
	} else if (_metal4PrepassProducer || _metal4DeferredPrepassRender) {
		invalidateMetal4PrepassHandoff();
		[encoder barrierAfterQueueStages:kMVKMetal4AllStages beforeStages:(MTLStageVertex | MTLStageFragment)
			visibilityOptions:(MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias)];
	}
	return true;
}

MVKMetal4ArgumentTables* MVKCommandEncoder::getMetal4ComputeHelperArgumentTables(const MVKMetal4ArgumentTables::Limits& limits) {
	return acquireMetal4ComputeHelperArgumentTables(limits, false);
}

MVKMetal4ArgumentTables* MVKCommandEncoder::getMetal4PrimitiveConversionArgumentTables() {
	return acquireMetal4ComputeHelperArgumentTables({5, 0, 0}, true);
}

MVKMetal4ArgumentTables* MVKCommandEncoder::acquireMetal4ComputeHelperArgumentTables(
		const MVKMetal4ArgumentTables::Limits& limits, bool completeOverwrite) {
	invalidateMetal4PrepassHandoff();
	getState().invalidateMetal4ComputeBindings();
	if (!isUsingMetal4() || _metal4EncodingFailed) { return nullptr; }
	NSError* error = nil;
	for (auto& tables : _metal4ComputeHelperTables) {
		const auto& allocated = tables->getLimits();
		if (allocated.bufferCount != limits.bufferCount || allocated.textureCount != limits.textureCount ||
			allocated.samplerCount != limits.samplerCount) { continue; }
		if (!completeOverwrite && !tables->clearBindings(MVKMetal4ArgumentTables::Stage::Compute, &error)) {
			failMetal4Encoding(error.localizedDescription.UTF8String);
			return nullptr;
		}
		return tables;
	}
    auto* tables = _metal4Submission->acquireArgumentTables(limits.bufferCount, limits.textureCount, limits.samplerCount, true, &error);
    if (!tables) {
        failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Could not lease native helper argument table.");
        return nullptr;
    }
    _metal4ComputeHelperTables.push_back(tables);
    return tables;
}

id<MTL4ComputeCommandEncoder> MVKCommandEncoder::getMetal4ComputeEncoder(MVKCommandUse cmdUse, bool independentConversion, bool captureFollowingRender, MTLStages operationStages, MVKMetal4QueryOperation queryOperation) {
	if (!isUsingMetal4() || _metal4EncodingFailed) { return nil; }
	const bool primitiveConversion = cmdUse == kMVKCommandUseDrawIndirectConvertBuffers;
	const bool queryHelper = queryOperation != MVKMetal4QueryOperation::None;
	const MTLStages queryStages = MVKMetal4QueryPolicy::stages(queryOperation);
	if (queryHelper && (!queryStages || (operationStages && operationStages != queryStages) ||
	                   independentConversion || captureFollowingRender)) {
		failMetal4Encoding("Native query helper has an invalid operation scope."); return nil;
	}
	const MTLStages requiredStages = queryHelper ? queryStages : operationStages ? operationStages :
		(cmdUse == kMVKCommandUseDispatch || primitiveConversion || cmdUse == kMVKCommandUseAccumOcclusionQuery
		 ? MTLStageDispatch : (MTLStageDispatch | MTLStageBlit));
	invalidateMetal4PrepassHandoff();
	if (captureFollowingRender && (_mtl4ComputeEncoder || _mtl4RenderEncoder)) {
		failMetal4Encoding("Prepass queue capture requires a fresh dedicated compute encoder."); return nil;
	}
	if (!_mtl4ComputeEncoder) {
		if (_mtl4RenderEncoder) { encodeStoreActions(true); }
		endCurrentMetalEncoding();
		_mtl4ComputeEncoder = [[_metal4Submission->commandBuffer() computeCommandEncoder] retain];
		if (!_mtl4ComputeEncoder) { failMetal4Encoding("Could not begin native compute encoder"); return nil; }
		++_metal4EncodingEpoch;
		if (auto* stats = getMetal4EncodingStats()) { ++stats->computePasses; }
		beginMetalComputeEncoding(cmdUse);
	} else if (!(cmdUse == kMVKCommandUseDispatch && _mtlComputeEncoderUse == kMVKCommandUseDispatch) &&
		!independentConversion && !_metal4IndependentConversions) {
		// Consecutive application dispatches use Vulkan's explicit dependencies,
		// encoded by setMetal4Barrier; submission order alone requires no barrier.
		// Keep implementation ordering when either operation is an internal helper.
		// A ready destination alone does not prove the source of a helper's
		// private scratch dependency (e.g. explicit Vertex -> Dispatch). Keep
		// helper ordering unless the independent-conversion proof permits reuse.
		[_mtl4ComputeEncoder barrierAfterEncoderStages:_metal4ComputeEncodedStages
			beforeEncoderStages:requiredStages visibilityOptions:(MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias)];
	}
	// A new Blit/Dispatch consumer can first appear in an already open pass.
	// Consume its prior-pass obligations as well as those of the first command.
	const bool conservative = !queryHelper && ((cmdUse != kMVKCommandUseDispatch && !primitiveConversion) || captureFollowingRender);
	const MTLStages querySources = MVKMetal4QueryPolicy::priorStages(queryOperation);
	for (unsigned i = 0; i < 4; ++i) {
		const MTLStages destination = _metal4ComputeQueueDependencies.stages[i];
		if (!(requiredStages & destination)) { continue; }
		if (conservative) {
			_metal4Dependencies.add(kMVKMetal4AllStages & ~_metal4ComputeQueueDependencies.memory[i], destination, true);
		} else if (querySources) {
			_metal4Dependencies.add(querySources & ~_metal4ComputeQueueDependencies.memory[i], destination, true);
		} else if (primitiveConversion) {
			_metal4Dependencies.add(MTLStageVertex & ~_metal4ComputeQueueDependencies.sources[i], destination, false);
		}
	}
	MTLStages destinations = requiredStages;
	if (captureFollowingRender) {
		destinations |= MTLStageVertex | MTLStageFragment;
		_metal4Dependencies.add(kMVKMetal4AllStages, MTLStageVertex | MTLStageFragment, true);
	}
	encodeMetal4PendingDependencies(_mtl4ComputeEncoder, destinations);
	_metal4ComputeEncodedStages |= requiredStages;
	if (queryHelper) {
		MVKMetal4QueryPolicy::addOutputs(_metal4EncoderDependencies, queryOperation);
	} else if (cmdUse != kMVKCommandUseDispatch) {
		// Conversion outputs are private indices/indirect records read by Vertex.
		// Other helpers retain their general implementation consumer contract.
		_metal4EncoderDependencies.add(requiredStages, primitiveConversion ? MTLStageVertex : kMVKMetal4AllStages, true);
	}
	_mtl4ComputeEncoder.label = mvkMTLComputeCommandEncoderLabel(cmdUse);
	_mtlComputeEncoderUse = cmdUse;
	return _mtl4ComputeEncoder;
}

void MVKCommandEncoder::beginMetal4RenderPass(MTLRenderPassDescriptor* source, MVKCommandUse cmdUse,
		uint64_t capturedEpoch, uint64_t leadingOrdinaryDraws) {
	if (_metal4EncodingFailed) { return; }
	MTL4RenderPassDescriptor* desc = [[MTL4RenderPassDescriptor new] autorelease];
	for (NSUInteger i = 0; i < 8; ++i) { desc.colorAttachments[i] = source.colorAttachments[i]; }
	desc.depthAttachment = source.depthAttachment;
	desc.stencilAttachment = source.stencilAttachment;
	desc.renderTargetWidth = source.renderTargetWidth;
	desc.renderTargetHeight = source.renderTargetHeight;
	desc.renderTargetArrayLength = source.renderTargetArrayLength;
	desc.defaultRasterSampleCount = source.defaultRasterSampleCount;
	desc.visibilityResultBuffer = source.visibilityResultBuffer;
	desc.visibilityResultType = source.visibilityResultType;
	desc.rasterizationRateMap = source.rasterizationRateMap;
	desc.imageblockSampleLength = source.imageblockSampleLength;
	desc.threadgroupMemoryLength = source.threadgroupMemoryLength;
	desc.tileWidth = source.tileWidth;
	desc.tileHeight = source.tileHeight;
	if (getMetalFeatures().programmableSamplePositions) {
		auto positions = _state.updateSamplePositions();
		[desc setSamplePositions:positions.data() count:positions.size()];
	}
	auto keepAttachment = [&](MTLRenderPassAttachmentDescriptor* att) {
		for (id<MTLTexture> texture : {att.texture, att.resolveTexture}) {
			if (texture && !_metal4Submission->addResource(texture)) {
				failMetal4Encoding("Could not make native render attachment resident");
			}
		}
	};
	for (NSUInteger i = 0; i < 8; ++i) { keepAttachment(desc.colorAttachments[i]); }
	keepAttachment(desc.depthAttachment);
	keepAttachment(desc.stencilAttachment);
	if (desc.visibilityResultBuffer && !_metal4Submission->addResource(desc.visibilityResultBuffer)) {
		failMetal4Encoding("Could not retain native visibility buffer");
	}
	if (desc.rasterizationRateMap && !_metal4Submission->retainObject(desc.rasterizationRateMap)) {
		failMetal4Encoding("Could not retain rasterization rate map");
	}
	if (_metal4EncodingFailed) { return; }
	bool handoff = capturedEpoch && capturedEpoch == _metal4EncodingEpoch &&
		!_mtl4ComputeEncoder && !_mtl4RenderEncoder && cmdUse != kMVKCommandUseRestartSubpass;
	_mtl4RenderEncoder = [[_metal4Submission->commandBuffer() renderCommandEncoderWithDescriptor:desc] retain];
	_metal4StoreActionsSet = false;
	if (!_mtl4RenderEncoder) { failMetal4Encoding("Could not begin native render encoder"); return; }
	++_metal4EncodingEpoch;
	_mtl4RenderEncoder.label = getMTLRenderCommandEncoderName(cmdUse);
    if (auto* stats = getMetal4EncodingStats()) { ++stats->renderPasses; }
	if (handoff) {
		_metal4DeferredPrepassRender = _mtl4RenderEncoder;
		_metal4DeferredPrepassEpoch = _metal4EncodingEpoch;
		if (auto* stats = getMetal4EncodingStats()) {
			++stats->prepassHandoffBatches;
			stats->prepassLeadingOrdinaryDraws += leadingOrdinaryDraws;
		}
	} else {
		if (capturedEpoch) { if (auto* stats = getMetal4EncodingStats()) { ++stats->prepassHandoffFallbacks; } }
		// Preserve attachment/load/store ordering independently of shader-resource
		// Vulkan barriers. Helpers add Dispatch/Blit obligations when they end.
		const bool conservative = capturedEpoch || cmdUse == kMVKCommandUseRestartSubpass;
		if (conservative) {
			encodeMetal4PendingDependencies(_mtl4RenderEncoder, MTLStageVertex | MTLStageFragment, kMVKMetal4AllStages);
		} else {
			// Attachment load/store/resolve runs in Fragment. Explicit shader and
			// helper dependencies independently retain any required Vertex waits.
			_metal4Dependencies.add(MTLStageFragment, MTLStageFragment, true);
			encodeMetal4PendingDependencies(_mtl4RenderEncoder, MTLStageVertex | MTLStageFragment);
		}
	}
}
#endif

// Activity performance tracking is put here to deliberately exclude when
// MVKConfiguration::prefillMetalCommandBuffers is set to immediate prefilling,
// because that would include app time between command submissions.
void MVKCommandEncoder::encode(id<MTLCommandBuffer> mtlCmdBuff,
							   MVKCommandEncodingContext* pEncodingContext) {
	uint64_t startTime = getPerformanceTimestamp();

    beginEncoding(mtlCmdBuff, pEncodingContext);
    encodeCommands(_cmdBuffer->_head);
    endEncoding();

	addPerformanceInterval(getPerformanceStats().queue.commandBufferEncoding, startTime);
}

void MVKCommandEncoder::beginEncoding(id<MTLCommandBuffer> mtlCmdBuff, MVKCommandEncodingContext* pEncodingContext) {
	_pEncodingContext = pEncodingContext;

    _subpassContents = VK_SUBPASS_CONTENTS_INLINE;
    _renderSubpassIndex = 0;
    _multiviewPassIndex = 0;
    _canUseLayeredRendering = false;

    _mtlCmdBuffer = mtlCmdBuff;        // not retained

	_cmdBuffer->setMetalObjectLabel(_mtlCmdBuffer, _cmdBuffer->_debugName);
}

// Multithread autorelease prefill style uses a dedicated autorelease pool when encoding each command.
void MVKCommandEncoder::encodeCommands(MVKCommand* command) {
	if (_prefillStyle == MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS_STYLE_IMMEDIATE_ENCODING) {
		@autoreleasepool {
			encodeCommandsImpl(command);
		}
	} else {
		encodeCommandsImpl(command);
	}
}

void MVKCommandEncoder::encodeCommandsImpl(MVKCommand* command) {
    while(command) {
		if (_attachmentBackingFailed || _visibilityResultBufferFailed) { break; }
#if MVK_BUILD_METAL4_FOUNDATION
		if (_metal4EncodingFailed) { break; }
#endif
        uint32_t prevMVPassIdx = _multiviewPassIndex;
        command->encode(this);

        if(_multiviewPassIndex > prevMVPassIdx) {
            // This means we're in a multiview render pass, and we moved on to the
            // next view group. Re-encode all commands in the subpass again for this group.
            
            command = _lastMultiviewPassCmd->_next;
        } else {
            command = command->_next;
        }
    }
}

void MVKCommandEncoder::endEncoding() {
	endCurrentMetalEncoding();
	finishQueries();
}

void MVKCommandEncoder::encodeSecondary(MVKCommandBuffer* secondaryCmdBuffer) {
	secondaryCmdBuffer->beginSecondaryEncoding(this);
	MVKCommand* cmd = secondaryCmdBuffer->_head;
	while (cmd) {
		if (_attachmentBackingFailed || _visibilityResultBufferFailed) { break; }
#if MVK_BUILD_METAL4_FOUNDATION
		if (_metal4EncodingFailed) { break; }
#endif
		cmd->encode(this);
		cmd = cmd->_next;
	}
}

void MVKCommandEncoder::beginRendering(MVKCommand* rendCmd, const VkRenderingInfo* pRenderingInfo) {

	VkSubpassContents contents = (mvkIsAnyFlagEnabled(pRenderingInfo->flags, VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT)
								  ? VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS
								  : VK_SUBPASS_CONTENTS_INLINE);

	// Track both rendering and resolve attachments, alternating a rendering attachment, then its corresponding resolve attachment.
	uint32_t maxAttCnt = (pRenderingInfo->colorAttachmentCount + 2) * 2;
	MVKImageView* imageViews[maxAttCnt];
	VkClearValue clearValues[maxAttCnt];

	// Assemble the list of attachments and clear values. This must be done identically to how the dynamic renderpass assembles attachments.
	uint32_t attCnt = 0;
	MVKRenderingAttachmentIterator attIter(pRenderingInfo);
	attIter.iterate([&](const VkRenderingAttachmentInfo* pAttInfo, VkImageAspectFlagBits aspect, MVKImageView* imgView, bool isResolveAttachment)->void {
		imageViews[attCnt] = imgView;
		clearValues[attCnt] = pAttInfo->clearValue;
		attCnt++;
	});

	// If we're resuming a suspended renderpass, continue to use the existing renderpass
	// (with updated rendering flags) and framebuffer. Otherwise, create new transient
	// renderpass and framebuffer objects from the pRenderingInfo, and retain them until
	// the renderpass is completely finished, which may span multiple command encoders.
	MVKRenderPass* mvkRP;
	MVKFramebuffer* mvkFB;
	bool isResumingSuspended = (mvkIsAnyFlagEnabled(_pEncodingContext->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT) &&
								mvkIsAnyFlagEnabled(pRenderingInfo->flags, VK_RENDERING_RESUMING_BIT));
	if (isResumingSuspended) {
		mvkRP = _pEncodingContext->getRenderPass();
		mvkRP->setRenderingFlags(pRenderingInfo->flags);
		mvkFB = _pEncodingContext->getFramebuffer();
	} else {
		auto* mvkDev = getDevice();
		mvkRP = mvkDev->createRenderPass(pRenderingInfo, nullptr);
		mvkFB = mvkDev->createFramebuffer(pRenderingInfo, nullptr);
	}
	beginRenderpass(rendCmd, contents, mvkRP, mvkFB,
					pRenderingInfo->renderArea,
					MVKArrayRef(clearValues, attCnt),
					MVKArrayRef(imageViews, attCnt),
					kMVKCommandUseBeginRendering);

	// If we've just created new transient objects, once retained by this encoder,
	// mark the objects as transient by releasing them from their initial creation
	// retain, so they will be destroyed when released at the end of the renderpass,
	// which may span multiple command encoders.
	if ( !isResumingSuspended ) {
		mvkRP->release();
		mvkFB->release();
	}
}

bool MVKCommandEncoder::isDynamicRendering() {
	MVKRenderSubpass* mvkRSP = getSubpass();
	return mvkRSP && mvkRSP->isDynamicRendering();
}

void MVKCommandEncoder::beginRenderpass(MVKCommand* passCmd,
										VkSubpassContents subpassContents,
										MVKRenderPass* renderPass,
										MVKFramebuffer* framebuffer,
										const VkRect2D& renderArea,
										MVKArrayRef<VkClearValue> clearValues,
										MVKArrayRef<MVKImageView*> attachments,
										MVKCommandUse cmdUse) {
	_pEncodingContext->setRenderingContext(renderPass, framebuffer);
	_renderArea = renderArea;
	_isRenderingEntireAttachment = (mvkVkOffset2DsAreEqual(_renderArea.offset, {0,0}) &&
									mvkVkExtent2DsAreEqual(_renderArea.extent, getFramebufferExtent()));
	_clearValues.assign(clearValues.begin(), clearValues.end());
	_attachments.assign(attachments.begin(), attachments.end());
	if (!prepareRenderPassAttachmentBackings()) { return; }

	setSubpass(passCmd, subpassContents, 0, cmdUse);
}

id<MTLTexture> MVKCommandEncoder::getRenderPassAttachmentOverride(MVKImageView* view) {
	for (auto& backing : _attachmentBackings) {
		if (backing.view == view) { return backing.texture; }
	}
	return nil;
}

id<MTLTexture> MVKCommandEncoder::getRenderPassAttachmentTexture(MVKImageView* view) {
	auto texture = getRenderPassAttachmentOverride(view);
	return texture ? texture : view->getMTLTexture();
}

bool MVKCommandEncoder::prepareRenderPassAttachmentBackings() {
	_attachmentBackings.clear();
	if (_attachmentBackingFailed || _visibilityResultBufferFailed) { return false; }
	// Immediate recording has not seen future queries. Suspended rendering must
	// select storage in the first part, including across separately prefilled CBs.
	bool needsPreservation = _cmdBuffer->_needsVisibilityResultMTLBuffer ||
		_cmdBuffer->_immediateCmdEncoder ||
		mvkIsAnyFlagEnabled(_pEncodingContext->getRenderingFlags(),
			VK_RENDERING_SUSPENDING_BIT | VK_RENDERING_RESUMING_BIT);
	if (!needsPreservation) { return true; }
	for (auto* view : _attachments) {
		// Avoid acquiring drawable or ordinary texture identities in this check.
		if (!view || view->getImage()->getMTLStorageMode() != MTLStorageModeMemoryless ||
			getRenderPassAttachmentOverride(view)) { continue; }
		id<MTLTexture> texture = nil;
		VkResult result = view->getAttachmentBackingMTLTexture(texture);
		if (result != VK_SUCCESS) {
			_attachmentBackingFailed = true;
			_cmdBuffer->setConfigurationResult(reportError(result,
				"Could not allocate transient render attachment preservation storage."));
#if MVK_BUILD_METAL4_FOUNDATION
			if (isUsingMetal4()) { failMetal4Encoding("Transient attachment preservation allocation failed."); }
#endif
			return false;
		}
		if (texture) { _attachmentBackings.push_back({view, texture}); }
	}
	return true;
}

void MVKCommandEncoder::beginNextSubpass(MVKCommand* subpassCmd, VkSubpassContents contents) {
	if (hasMoreMultiviewPasses()) {
		beginNextMultiviewPass();
	} else {
		setSubpass(subpassCmd, contents, _renderSubpassIndex + 1, kMVKCommandUseNextSubpass);
	}
}

// Sets the current render subpass to the subpass with the specified index.
// End any active Metal encoder before capturing dependency fences and updating the subpass index.
void MVKCommandEncoder::setSubpass(MVKCommand* subpassCmd,
								   VkSubpassContents subpassContents,
								   uint32_t subpassIndex,
								   MVKCommandUse cmdUse) {
	encodeStoreActions();
	endCurrentMetalEncoding();

	MVKRenderPass* renderPass = _pEncodingContext->getRenderPass();
	if (renderPass) { renderPass->encodeSubpassDependencyBarriers(this, subpassIndex); }

	_lastMultiviewPassCmd = subpassCmd;
	_subpassContents = subpassContents;
	_renderSubpassIndex = subpassIndex;
	_multiviewPassIndex = 0;

	auto& mtlFeats = getMetalFeatures();
	_canUseLayeredRendering = mtlFeats.layeredRendering && (mtlFeats.multisampleLayeredRendering || getSubpass()->getSampleCount() == VK_SAMPLE_COUNT_1_BIT);

#if MVK_BUILD_METAL4_FOUNDATION
    if (isUsingMetal4()) {
        _metal4PreconvertedDraws.clear();
        if (!_cmdBuffer->_isSecondary && subpassContents == VK_SUBPASS_CONTENTS_INLINE && subpassIndex == 0 &&
            renderPass->getSubpassCount() == 1 && !getSubpass()->isMultiview() &&
            !(renderPass->getRenderingFlags() & (VK_RENDERING_SUSPENDING_BIT | VK_RENDERING_RESUMING_BIT))) {
            preconvertMetal4Draws(subpassCmd ? subpassCmd->_next : nullptr);
        }
    }
#endif
	beginMetalRenderPass(cmdUse);
}

bool MVKCommandEncoder::hasMoreMultiviewPasses() { return _multiviewPassIndex + 1 < getSubpass()->getMultiviewMetalPassCount(); }

void MVKCommandEncoder::beginNextMultiviewPass() {
	encodeStoreActions();
	_multiviewPassIndex++;
	beginMetalRenderPass(kMVKCommandUseNextSubpass);
}

// Retain encoders when prefilling, because prefilling may span multiple autorelease pools.
template<typename T>
void MVKCommandEncoder::retainIfImmediatelyEncoding(T& mtlEnc) {
	if (_cmdBuffer->_immediateCmdEncoder) { [mtlEnc retain]; }
}

// End Metal encoder and release retained encoders when immediately encoding.
template<typename T>
void MVKCommandEncoder::endMetalEncoding(T& mtlEnc) {
	[mtlEnc endEncoding];
	if (_cmdBuffer->_immediateCmdEncoder) { [mtlEnc release]; }
	mtlEnc = nil;
}

static MVKBarrierStage commandUseToBarrierStage(MVKCommandUse use) {
	switch (use) {
	case kMVKCommandUseNone:                         return kMVKBarrierStageNone; /**< No use defined. */
	case kMVKCommandUseBeginCommandBuffer:           return kMVKBarrierStageNone; /**< vkBeginCommandBuffer (prefilled VkCommandBuffer). */
	case kMVKCommandUseQueueSubmit:                  return kMVKBarrierStageNone; /**< vkQueueSubmit. */
	case kMVKCommandUseAcquireNextImage:             return kMVKBarrierStageNone; /**< vkAcquireNextImageKHR. */
	case kMVKCommandUseQueuePresent:                 return kMVKBarrierStageNone; /**< vkQueuePresentKHR. */
	case kMVKCommandUseQueueWaitIdle:                return kMVKBarrierStageNone; /**< vkQueueWaitIdle. */
	case kMVKCommandUseDeviceWaitIdle:               return kMVKBarrierStageNone; /**< vkDeviceWaitIdle. */
	case kMVKCommandUseInvalidateMappedMemoryRanges: return kMVKBarrierStageNone; /**< vkInvalidateMappedMemoryRanges. */
	case kMVKCommandUseBeginRendering:               return kMVKBarrierStageNone; /**< vkCmdBeginRendering. */
	case kMVKCommandUseBeginRenderPass:              return kMVKBarrierStageNone; /**< vkCmdBeginRenderPass. */
	case kMVKCommandUseNextSubpass:                  return kMVKBarrierStageNone; /**< vkCmdNextSubpass. */
	case kMVKCommandUseRestartSubpass:               return kMVKBarrierStageNone; /**< Create a new Metal renderpass due to Metal requirements. */
	case kMVKCommandUsePipelineBarrier:              return kMVKBarrierStageNone; /**< vkCmdPipelineBarrier. */
	case kMVKCommandUseBlitImage:                    return kMVKBarrierStageCopy; /**< vkCmdBlitImage. */
	case kMVKCommandUseCopyImage:                    return kMVKBarrierStageCopy; /**< vkCmdCopyImage. */
	case kMVKCommandUseResolveImage:                 return kMVKBarrierStageCopy; /**< vkCmdResolveImage - resolve stage. */
    case kMVKCommandUseResolveSubpassAttachment:     return kMVKBarrierStageFragment; /**< Resolve subpass attachment. */
	case kMVKCommandUseResolveExpandImage:           return kMVKBarrierStageCopy; /**< vkCmdResolveImage - expand stage. */
	case kMVKCommandUseResolveCopyImage:             return kMVKBarrierStageCopy; /**< vkCmdResolveImage - copy stage. */
	case kMVKCommandUseCopyImageToMemory:            return kMVKBarrierStageCopy; /**< vkCopyImageToMemory host sync. */
	case kMVKCommandUseCopyBuffer:                   return kMVKBarrierStageCopy; /**< vkCmdCopyBuffer. */
	case kMVKCommandUseCopyBufferToImage:            return kMVKBarrierStageCopy; /**< vkCmdCopyBufferToImage. */
	case kMVKCommandUseCopyImageToBuffer:            return kMVKBarrierStageCopy; /**< vkCmdCopyImageToBuffer. */
	case kMVKCommandUseFillBuffer:                   return kMVKBarrierStageCopy; /**< vkCmdFillBuffer. */
	case kMVKCommandUseUpdateBuffer:                 return kMVKBarrierStageCopy; /**< vkCmdUpdateBuffer. */
	case kMVKCommandUseClearAttachments:             return kMVKBarrierStageNone; /**< vkCmdClearAttachments. */
	case kMVKCommandUseClearColorImage:              return kMVKBarrierStageCopy; /**< vkCmdClearColorImage. */
	case kMVKCommandUseClearDepthStencilImage:       return kMVKBarrierStageCopy; /**< vkCmdClearDepthStencilImage. */
	case kMVKCommandUseResetQueryPool:               return kMVKBarrierStageCopy; /**< vkCmdResetQueryPool. */
	case kMVKCommandUseDispatch:                     return kMVKBarrierStageCompute; /**< vkCmdDispatch. */
	case kMVKCommandUseTessellationVertexTessCtl:    return kMVKBarrierStageVertex; /**< vkCmdDraw* - vertex and tessellation control stages. */
	case kMVKCommandUseDrawIndirectConvertBuffers:   return kMVKBarrierStageVertex; /**< vkCmdDrawIndirect* convert indirect buffers. */
	case kMVKCommandUseCopyQueryPoolResults:         return kMVKBarrierStageCopy; /**< vkCmdCopyQueryPoolResults. */
	case kMVKCommandUseAccumOcclusionQuery:          return kMVKBarrierStageNone; /**< Any command terminating a Metal render pass with active visibility buffer. */
	case kMVKCommandConvertUint8Indices:             return kMVKBarrierStageCopy; /**< Converting a Uint8 index buffer to Uint16. */
	case kMVKCommandUseRecordGPUCounterSample:       return kMVKBarrierStageNone; /**< Any command triggering the recording of a GPU counter sample. */
	}
}



void MVKCommandEncoder::barrierWait(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages beforeStages) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = _pEncodingContext->fenceSlots.wait[stage][i];
		auto fence = _device->getFence((MVKBarrierStage)i, fenceIndex);
		[mtlEncoder waitForFence:fence beforeStages:beforeStages];
	}
}

void MVKCommandEncoder::barrierWait(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = _pEncodingContext->fenceSlots.wait[stage][i];
		auto fence = _device->getFence((MVKBarrierStage)i, fenceIndex);
		[mtlEncoder waitForFence:fence];
	}
}

void MVKCommandEncoder::barrierWait(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
		auto fenceIndex = _pEncodingContext->fenceSlots.wait[stage][i];
		auto fence = _device->getFence((MVKBarrierStage)i, fenceIndex);
		[mtlEncoder waitForFence:fence];
	}
}

void MVKCommandEncoder::barrierUpdate(MVKBarrierStage stage, id<MTLRenderCommandEncoder> mtlEncoder, MTLRenderStages afterStages) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	auto fence = getBarrierStageFence(stage);
	[mtlEncoder updateFence:fence afterStages:afterStages];
}

void MVKCommandEncoder::barrierUpdate(MVKBarrierStage stage, id<MTLBlitCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	auto fence = getBarrierStageFence(stage);
	[mtlEncoder updateFence:fence];
}

void MVKCommandEncoder::barrierUpdate(MVKBarrierStage stage, id<MTLComputeCommandEncoder> mtlEncoder) {
	if (!isUsingMetalArgumentBuffers() || !getDevice()->hasResidencySet()) return;
	auto fence = getBarrierStageFence(stage);
	[mtlEncoder updateFence:fence];
}

id<MTLFence> MVKCommandEncoder::getBarrierStageFence(MVKBarrierStage stage) {
	auto &fenceSlots = _pEncodingContext->fenceSlots;
	if (mvkAreAllFlagsEnabled(fenceSlots.updateDirtyBits, 1 << stage)) {
		mvkDisableFlags(fenceSlots.updateDirtyBits, 1 << stage);

		fenceSlots.update[stage] = (fenceSlots.update[stage] + 1) % kMVKBarrierFenceCount;
		if (fenceSlots.update[stage] == 0) fenceSlots.update[stage] = 1;
	}

	return _device->getFence(stage, fenceSlots.update[stage]);
}

void MVKCommandEncoder::setBarrier(uint64_t sourceStageMask, uint64_t destStageMask) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		invalidateMetal4PrepassHandoff();
		_metal4Dependencies.add(kMVKMetal4AllStages, kMVKMetal4AllStages, true);
		if (_mtl4ComputeEncoder) {
			encodeMetal4PendingDependencies(_mtl4ComputeEncoder, MTLStageDispatch | MTLStageBlit);
			_metal4EncoderDependencies.add(MTLStageDispatch | MTLStageBlit, kMVKMetal4AllStages, true);
			// The explicit queue barrier covers earlier encoders; this barrier
			// separately covers work in the current pass. Legacy subpass scopes
			// conservatively retain full compute/blit visibility.
			[_mtl4ComputeEncoder barrierAfterEncoderStages:(MTLStageDispatch | MTLStageBlit)
				beforeEncoderStages:(MTLStageDispatch | MTLStageBlit)
				visibilityOptions:(MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias)];
			if (auto* stats = getMetal4EncodingStats()) { ++stats->computeBarrierContinuations; }
			return;
		}
		// Conservatively end the pass. Pending all-stage obligations make the
		// following consumers wait, including cross-command-buffer work.
		// Splitting also handles fragment dependencies on tile-based GPUs.
		if (_mtl4RenderEncoder) { encodeStoreActions(true); }
		endCurrentMetalEncoding();
		return;
	}
#endif
	auto &fenceSlots = _pEncodingContext->fenceSlots;
	for (int i = 0; i < kMVKBarrierStageCount; ++i) {
	   if (!mvkIsAnyFlagEnabled(sourceStageMask, 1ull << i)) continue;

		for (int j = 0; j < kMVKBarrierStageCount; ++j) {
			if (!mvkIsAnyFlagEnabled(destStageMask, 1ull << j)) continue;

			fenceSlots.wait[j][i] = fenceSlots.update[i];
		}

		fenceSlots.wait[i][i] = fenceSlots.update[i];
		mvkEnableFlags(fenceSlots.updateDirtyBits, 1 << i);
	}
}


void MVKCommandEncoder::encodeBarrierWaits(MVKCommandUse use) {
	if (_mtlRenderEncoder) {
		[_mtlRenderEncoder insertDebugSignpost:@"Encoding waits"];
		barrierWait(kMVKBarrierStageVertex, _mtlRenderEncoder, MTLRenderStageVertex);
		barrierWait(kMVKBarrierStageFragment, _mtlRenderEncoder, MTLRenderStageFragment);
	}
	if (_mtlComputeEncoder) {
		auto stage = commandUseToBarrierStage(use);
		if (stage != kMVKBarrierStageNone) {
			barrierWait(stage, _mtlComputeEncoder);
		}
	}
	if (_mtlBlitEncoder) {
		auto stage = commandUseToBarrierStage(use);
		if (stage != kMVKBarrierStageNone) {
			barrierWait(stage, _mtlBlitEncoder);
		}
	}
}

void MVKCommandEncoder::encodeBarrierUpdates() {
	if (_mtlRenderEncoder) {
		barrierUpdate(kMVKBarrierStageVertex, _mtlRenderEncoder, MTLRenderStageVertex);
		barrierUpdate(kMVKBarrierStageFragment, _mtlRenderEncoder, MTLRenderStageFragment);
	}

	if (_mtlComputeEncoder) {
		for (int stage = 0; stage < kMVKBarrierStageCount; ++stage) {
			if (mvkIsAnyFlagEnabled(_mtlComputeEncoderStages, 1 << stage)) {
				barrierUpdate((MVKBarrierStage)stage, _mtlComputeEncoder);
			}
		}
	}

	if (_mtlBlitEncoder) {
		MVKBarrierStage stage = commandUseToBarrierStage(_mtlBlitEncoderUse);
		if (stage != kMVKBarrierStageNone) {
			barrierUpdate(stage, _mtlBlitEncoder);
		}
	}
}


bool MVKCommandEncoder::prepareVisibilityResultBuffer(MTLRenderPassDescriptor* descriptor) {
	auto fail = [&]() {
		_visibilityResultBufferFailed = true;
		_cmdBuffer->setConfigurationResult(reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY,
			"Could not prepare native visibility result storage."));
#if MVK_BUILD_METAL4_FOUNDATION
		if (isUsingMetal4()) { failMetal4Encoding("Native visibility initialization failed."); }
#endif
		return false;
	};
	auto& visibility = _pEncodingContext->visibilityResultBuffer;
	if (!visibility.buffer()) { visibility = _device->getVisibilityBuffer(); }
	if (!visibility.buffer()) { return fail(); }
	descriptor.visibilityResultBuffer = visibility.buffer();
#if MVK_XCODE_26
	if (@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)) {
		// Own native slot initialization/recycling instead of relying on the
		// render-pass Reset path. The Vulkan query pool is reset independently.
		descriptor.visibilityResultType = MTLVisibilityResultTypeAccumulate;
		if (visibility.needsInitialClear()) {
#if MVK_BUILD_METAL4_FOUNDATION
			if (isUsingMetal4()) {
				auto encoder = getMetal4ComputeEncoder(kMVKCommandUseResetQueryPool, false, false, 0,
					MVKMetal4QueryOperation::VisibilityInitialize);
				if (!encoder || !_metal4Submission->addResource(visibility.buffer())) { return fail(); }
				[encoder fillBuffer:visibility.buffer() range:NSMakeRange(0, visibility.size()) value:0];
			} else
#endif
			{
				if (!visibility.initialClearFence(0) || !visibility.initialClearFence(1)) { return fail(); }
				auto encoder = getMTLBlitEncoder(kMVKCommandUseResetQueryPool);
				if (!encoder) { return fail(); }
				[encoder fillBuffer:visibility.buffer() range:NSMakeRange(0, visibility.size()) value:0];
				// Both halves start at zero. Their first Fragment writers already
				// wait on these fences; later rotations wait on accumulation/clear.
				[encoder updateFence:visibility.initialClearFence(0)];
				[encoder updateFence:visibility.initialClearFence(1)];
			}
			endCurrentMetalEncoding();
			// This is recording state, not a CPU claim that the GPU has finished.
			// It moves with the exclusive buffer lease. A cancelled local context
			// destroys the buffer; an encoded lease keeps the existing GPU fences.
			visibility.markInitialClearEncoded();
		}
	}
#endif
	return true;
}

// Creates _mtlRenderEncoder and marks cached render state as dirty so it will be set into the _mtlRenderEncoder.
void MVKCommandEncoder::beginMetalRenderPass(MVKCommandUse cmdUse) {
	if (_attachmentBackingFailed || _visibilityResultBufferFailed) { return; }

#if MVK_BUILD_METAL4_FOUNDATION
	bool handoff = isUsingMetal4() && cmdUse != kMVKCommandUseRestartSubpass &&
		_metal4PrepassProducer && _metal4PrepassProducer == _mtl4ComputeEncoder &&
		_metal4PrepassProducerEpoch == _metal4EncodingEpoch && !_mtl4RenderEncoder;
	uint64_t leadingOrdinaryDraws = handoff ? _metal4PrepassLeadingDraws : 0;
	if (handoff) {
		// Consume only the exact immediately preceding producer. All other
		// encoder endings discard the token and restore the full dependency.
		_metal4PrepassProducer = nil;
		_metal4PrepassProducerEpoch = _metal4PrepassLeadingDraws = 0;
	}
#endif
    endCurrentMetalEncoding();
#if MVK_BUILD_METAL4_FOUNDATION
	uint64_t capturedEpoch = handoff ? _metal4EncodingEpoch : 0;
#endif

	bool isRestart = cmdUse == kMVKCommandUseRestartSubpass;
    MTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];
	getSubpass()->populateMTLRenderPassDescriptor(this, mtlRPDesc,
												  _multiviewPassIndex,
												  _pEncodingContext->getFramebuffer(),
												  _attachments.contents(),
												  _clearValues.contents(),
												  _isRenderingEntireAttachment,
												  isRestart);
	if (_cmdBuffer->_needsVisibilityResultMTLBuffer) {
		if (!prepareVisibilityResultBuffer(mtlRPDesc)) { return; }
	}
	_hasMTLRenderEncoderVisibilityResultBuffer = (mtlRPDesc.visibilityResultBuffer != nil);

	// Metal uses MTLRenderPassDescriptor properties renderTargetWidth, renderTargetHeight,
	// and renderTargetArrayLength to preallocate tile memory storage on machines using tiled
	// rendering. This memory preallocation is not necessary if we are not rendering to
	// attachments, and some apps actively define extremely oversized framebuffers when they
	// know they are not rendering to actual attachments, making this internal tile memory
	// allocation even more wasteful, occasionally to the point of triggering OOM crashes.
	// On the other hand, if the framebuffer has no attachments and has zero extent,
	// we just set the render target extent to cover the render area.
	VkExtent2D fbExtent = getFramebufferExtent();
	VkExtent2D raFullExtent = { _renderArea.offset.x + _renderArea.extent.width, _renderArea.offset.y + _renderArea.extent.height };
    mtlRPDesc.renderTargetWidth = max(min(raFullExtent.width, (fbExtent.width ? fbExtent.width : raFullExtent.width)), 1u);
    mtlRPDesc.renderTargetHeight = max(min(raFullExtent.height, (fbExtent.height ? fbExtent.height : raFullExtent.height)), 1u);
    if (_canUseLayeredRendering) {
        uint32_t renderTargetArrayLength;
        bool found3D = false, found2D = false;
        for (uint32_t i = 0; i < 8; i++) {
            id<MTLTexture> mtlTex = mtlRPDesc.colorAttachments[i].texture;
            if (mtlTex == nil) { continue; }
            switch (mtlTex.textureType) {
                case MTLTextureType3D:
                    found3D = true;
                default:
                    found2D = true;
            }
        }

        if (getSubpass()->isMultiview()) {
            // In the case of a multiview pass, the framebuffer layer count will be one.
            // We need to use the view count for this multiview pass.
			renderTargetArrayLength = getSubpass()->getViewCountInMetalPass(_multiviewPassIndex);
        } else {
			renderTargetArrayLength = getFramebufferLayerCount();
        }
        // Metal does not allow layered render passes where some RTs are 3D and others are 2D.
        if (!(found3D && found2D) || renderTargetArrayLength > 1) {
            mtlRPDesc.renderTargetArrayLength = renderTargetArrayLength;
        }
    }

	// If programmable sample positions are supported, set them into the render pass descriptor.
	// If no custom sample positions are established, size will be zero,
	// and Metal will default to using default sample postions.
	if (getMetalFeatures().programmableSamplePositions) {
		auto sampPosns = _state.updateSamplePositions();
		[mtlRPDesc setSamplePositions: sampPosns.data() count: sampPosns.size()];
	}

#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		beginMetal4RenderPass(mtlRPDesc, cmdUse, capturedEpoch, leadingOrdinaryDraws);
		getState().beginGraphicsEncoding(getSampleCount());
		if (!isRestart && !_isRenderingEntireAttachment) {
			invalidateMetal4PrepassHandoff();
			clearRenderArea(cmdUse);
		}
		return;
	}
#endif
    _mtlRenderEncoder = [_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
	retainIfImmediatelyEncoding(_mtlRenderEncoder);
	_cmdBuffer->setMetalObjectLabel(_mtlRenderEncoder, getMTLRenderCommandEncoderName(cmdUse));
	getState().beginGraphicsEncoding(getSampleCount());

	encodeBarrierWaits(cmdUse);

	// We shouldn't clear the render area if we are restarting the Metal renderpass
	// separately from a Vulkan subpass, and we otherwise only need to clear render
	// area if we're not rendering to the entire attachment.
    if ( !isRestart && !_isRenderingEntireAttachment ) { clearRenderArea(cmdUse); }
}

void MVKCommandEncoder::restartMetalRenderPassIfNeeded() {
	bool hasEncoder = _mtlRenderEncoder != nil;
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) { hasEncoder = _mtl4RenderEncoder != nil; }
#endif
	if ( !hasEncoder || _state.needsMetalRenderPassRestart() ||
		(_cmdBuffer->_needsVisibilityResultMTLBuffer && !_hasMTLRenderEncoderVisibilityResultBuffer) ) {
		encodeStoreActions(true);
		beginMetalRenderPass(kMVKCommandUseRestartSubpass);
	}
}

void MVKCommandEncoder::encodeStoreActions(bool storeOverride) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) { _metal4StoreActionsSet = true; }
#endif
	getSubpass()->encodeStoreActions(this,
									 _isRenderingEntireAttachment,
									 _attachments.contents(),
									 storeOverride);
}

MVKRenderSubpass* MVKCommandEncoder::getSubpass() {
	MVKRenderPass* mvkRP = _pEncodingContext->getRenderPass();
	return mvkRP ? mvkRP->getSubpass(_renderSubpassIndex) : nullptr;
}

// Returns a name for use as a MTLRenderCommandEncoder label
NSString* MVKCommandEncoder::getMTLRenderCommandEncoderName(MVKCommandUse cmdUse) {
	NSString* rpName;

	rpName = _pEncodingContext->getRenderPass()->getDebugName();
	if (rpName) { return rpName; }

	rpName = _cmdBuffer->getDebugName();
	if (rpName) { return rpName; }

	return mvkMTLRenderCommandEncoderLabel(cmdUse);
}

VkExtent2D MVKCommandEncoder::getFramebufferExtent() {
	auto* mvkFB = _pEncodingContext->getFramebuffer();
	return mvkFB ? mvkFB->getExtent2D() : VkExtent2D{0,0};
}

uint32_t MVKCommandEncoder::getFramebufferLayerCount() {
	auto* mvkFB = _pEncodingContext->getFramebuffer();
	return mvkFB ? mvkFB->getLayerCount() : 0;
}

void MVKCommandEncoder::bindPipeline(VkPipelineBindPoint pipelineBindPoint, MVKPipeline* pipeline) {
    switch (pipelineBindPoint) {
        case VK_PIPELINE_BIND_POINT_GRAPHICS:
            _state.bindGraphicsPipeline(static_cast<MVKGraphicsPipeline*>(pipeline));
            static_cast<MVKGraphicsPipeline*>(pipeline)->wasBound(this);
            break;

        case VK_PIPELINE_BIND_POINT_COMPUTE:
            _state.bindComputePipeline(static_cast<MVKComputePipeline*>(pipeline));
            break;

        default:
            break;
    }
}

void MVKCommandEncoder::signalEvent(MVKEvent* mvkEvent, bool status) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) { failMetal4Encoding("Native Vulkan event encoding pending"); return; }
#endif
	endCurrentMetalEncoding();
	mvkEvent->encodeSignal(_mtlCmdBuffer, status);
}

VkRect2D MVKCommandEncoder::clipToRenderArea(VkRect2D rect) {

	uint32_t raLeft = max(_renderArea.offset.x, 0);
	uint32_t raRight = raLeft + _renderArea.extent.width;
	uint32_t raBottom = max(_renderArea.offset.y, 0);
	uint32_t raTop = raBottom + _renderArea.extent.height;

	rect.offset.x      = mvkClamp<uint32_t>(rect.offset.x, raLeft, max(raRight - 1, raLeft));
	rect.offset.y      = mvkClamp<uint32_t>(rect.offset.y, raBottom, max(raTop - 1, raBottom));
	rect.extent.width  = min<uint32_t>(rect.extent.width, raRight - rect.offset.x);
	rect.extent.height = min<uint32_t>(rect.extent.height, raTop - rect.offset.y);

	return rect;
}

MTLScissorRect MVKCommandEncoder::clipToRenderArea(MTLScissorRect scissor) {
	return mvkMTLScissorRectFromVkRect2D(clipToRenderArea(mvkVkRect2DFromMTLScissorRect(scissor)));
}

// Attachment locations are changing. Need to store attachments and begin another Metal renderpass.
void MVKCommandEncoder::updateColorAttachmentLocations(const MVKArrayRef<uint32_t> colorAttLocs) {
	if ((_mtlRenderEncoder
#if MVK_BUILD_METAL4_FOUNDATION
		 || _mtl4RenderEncoder
#endif
		) && isDynamicRendering()) {
		auto atts = _pEncodingContext->getFramebuffer()->getAttachments();
		auto* mvkSP = getSubpass();
		if (mvkSP && mvkSP->isChangingColorAttachmentLocations(colorAttLocs, atts)) {
			encodeStoreActions(true);
			endMetalRenderEncoding();
			mvkSP->updateColorAttachmentLocations(colorAttLocs, atts);
		}
	}
}

// Input attachments are changing. Need to store attachments and begin another Metal renderpass.
void MVKCommandEncoder::updateAttachmentInputIndices(const MVKArrayRef<uint32_t> colorAttIdxs,
													 const uint32_t* pDepthInputAttachmentIndex,
													 const uint32_t* pStencilInputAttachmentIndex) {
	if ((_mtlRenderEncoder
#if MVK_BUILD_METAL4_FOUNDATION
		 || _mtl4RenderEncoder
#endif
		) && isDynamicRendering()) {
		auto* mvkSP = getSubpass();
		if (mvkSP && mvkSP->isChangingAttachmentInputIndices(colorAttIdxs, pDepthInputAttachmentIndex, pStencilInputAttachmentIndex)) {
			encodeStoreActions(true);
			endMetalRenderEncoding();
			mvkSP->updateAttachmentInputIndices(colorAttIdxs, pDepthInputAttachmentIndex, pStencilInputAttachmentIndex);
		}
	}
}

void MVKCommandEncoder::finalizeDrawState(MVKGraphicsStage stage) {
    if (stage == kMVKGraphicsStageVertex) {
        // Must happen before switching encoders.
        encodeStoreActions(true);
    }
	if (stage == kMVKGraphicsStageRasterization) {
		prepareDraw();
		_occlusionQueryState.encode(_mtlRenderEncoder, this);
	} else {
		getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
		prepareRenderDispatch(stage);
	}
}

// Clears the render area of the framebuffer attachments.
void MVKCommandEncoder::clearRenderArea(MVKCommandUse cmdUse) {

	MVKClearAttachments clearAtts;
	getSubpass()->populateClearAttachments(clearAtts, _clearValues.contents());

	uint32_t clearAttCnt = (uint32_t)clearAtts.size();

	if (clearAttCnt == 0) { return; }

	if (!getSubpass()->isMultiview()) {
		VkClearRect clearRect;
		clearRect.rect = _renderArea;
		clearRect.baseArrayLayer = 0;
		clearRect.layerCount = getFramebufferLayerCount();

		// Create and execute a temporary clear attachments command.
		// To be threadsafe...do NOT acquire and return the command from the pool.
		MVKCmdClearMultiAttachments<1> cmd;
		cmd.setContent(_cmdBuffer, clearAttCnt, clearAtts.data(), 1, &clearRect, cmdUse);
		cmd.encode(this);
	} else {
		// For multiview, it is possible that some attachments need different layers cleared.
		// In that case, we'll have to clear them individually. :/
		for (auto& clearAtt : clearAtts) {
			MVKSmallVector<VkClearRect, 1> clearRects;
			getSubpass()->populateMultiviewClearRects(clearRects, this, clearAtt.colorAttachment, clearAtt.aspectMask);
			// Create and execute a temporary clear attachments command.
			// To be threadsafe...do NOT acquire and return the command from the pool.
			if (clearRects.size() == 1) {
				MVKCmdClearSingleAttachment<1> cmd;
				cmd.setContent(_cmdBuffer, 1, &clearAtt, (uint32_t)clearRects.size(), clearRects.data(), cmdUse);
				cmd.encode(this);
			} else {
				MVKCmdClearSingleAttachment<4> cmd;
				cmd.setContent(_cmdBuffer, 1, &clearAtt, (uint32_t)clearRects.size(), clearRects.data(), cmdUse);
				cmd.encode(this);
			}
		}
	}
}

void MVKCommandEncoder::beginMetalComputeEncoding(MVKCommandUse cmdUse) {
	getState().beginComputeEncoding();
}

void MVKCommandEncoder::finalizeDispatchState() {
	getMTLComputeEncoder(kMVKCommandUseDispatch);
	prepareComputeDispatch();
}

void MVKCommandEncoder::endRendering() {
	endRenderpass();
}

void MVKCommandEncoder::endRenderpass() {
#if MVK_BUILD_METAL4_FOUNDATION
    _metal4PreconvertedDraws.clear();
#endif
	if (hasMoreMultiviewPasses()) {
		beginNextMultiviewPass();
		return;
	}

	encodeStoreActions();
	endMetalRenderEncoding();
	MVKRenderPass *renderPass = _pEncodingContext->getRenderPass();
	if (renderPass) { renderPass->encodeSubpassDependencyBarriers(this, VK_SUBPASS_EXTERNAL); }
	if ( !mvkIsAnyFlagEnabled(_pEncodingContext->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT) ) {
		_pEncodingContext->setRenderingContext(nullptr, nullptr);
	}
	_attachments.clear();
	_attachmentBackings.clear();
	_renderSubpassIndex = 0;
}

void MVKCommandEncoder::endMetalRenderEncoding() {
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		if (!_mtl4RenderEncoder) { return; }
		_metal4EndingRenderEncoding = true;
		invalidateMetal4PrepassHandoff();
		// An unsupported command can stop traversal before vkCmdEndRenderPass.
		// End the encoder with valid store actions even when cancelling a batch.
		if (!_metal4StoreActionsSet) { encodeStoreActions(true); }
		[_mtl4RenderEncoder endEncoding];
        [_mtl4RenderEncoder release];
		_mtl4RenderEncoder = nil;
		_metal4Dependencies.merge(_metal4EncoderDependencies);
		_metal4EncoderDependencies.satisfy(kMVKMetal4AllStages, kMVKMetal4AllStages);
		getSubpass()->resolveUnresolvableAttachments(this, _attachments.contents());
		endCurrentMetalEncoding();
		_occlusionQueryState.endMetalRenderPass(this);
		_metal4EndingRenderEncoding = false;
		// Resolve/visibility helpers belong to the ended pass too. Nested
		// encoder boundaries above must not flush timestamps ahead of them.
		if (!_timestampStageCounterQueries.empty()) { endCurrentMetalEncoding(); }
		return;
	}
#endif
    if (_mtlRenderEncoder == nil) { return; }

	if (_cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlRenderEncoder updateFence: getStageCountersMTLFence() afterStages: MTLRenderStageFragment]; }
	encodeBarrierUpdates();
	endMetalEncoding(_mtlRenderEncoder);

	getSubpass()->resolveUnresolvableAttachments(this, _attachments.contents());
	endCurrentMetalEncoding();

    _occlusionQueryState.endMetalRenderPass(this);
}

void MVKCommandEncoder::endCurrentMetalEncoding() {
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		invalidateMetal4PrepassHandoff();
		++_metal4EncodingEpoch;
		endMetalRenderEncoding();
		if (_mtl4ComputeEncoder) {
			_metal4Dependencies.merge(_metal4EncoderDependencies);
		}
		[_mtl4ComputeEncoder endEncoding];
        [_mtl4ComputeEncoder release];
		_mtl4ComputeEncoder = nil;
		_metal4EncoderDependencies.satisfy(kMVKMetal4AllStages, kMVKMetal4AllStages);
		_metal4ComputeEncodedStages = 0;
		_metal4ComputeQueueDependencies.satisfy(kMVKMetal4AllStages, kMVKMetal4AllStages);
		_mtlComputeEncoderUse = kMVKCommandUseNone;
		encodeMetal4TimestampSamples();
		return;
	}
#endif
	endMetalRenderEncoding();
	encodeBarrierUpdates();

	if (_mtlComputeEncoder && _cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlComputeEncoder updateFence: getStageCountersMTLFence()]; }
	endMetalEncoding(_mtlComputeEncoder);
	_mtlComputeEncoderUse = kMVKCommandUseNone;
	_mtlComputeEncoderStages = 0;

	if (_mtlBlitEncoder && _cmdBuffer->_hasStageCounterTimestampCommand) { [_mtlBlitEncoder updateFence: getStageCountersMTLFence()]; }
	endMetalEncoding(_mtlBlitEncoder);
    _mtlBlitEncoderUse = kMVKCommandUseNone;

	encodeTimestampStageCounterSamples();
}

static MTLDispatchType getDispatchType(MVKCommandUse use) {
	switch (use) {
		case kMVKCommandUseAccumOcclusionQuery:
			return MTLDispatchTypeConcurrent;
		default:
			return MTLDispatchTypeSerial;
	}
}

static bool wantsSeparateComputeEncoder(MVKCommandUse use) {
	switch (use) {
		case kMVKCommandUseAccumOcclusionQuery:
			return true;
		default:
			return false;
	}
}

static bool shouldStartNewEncoder(MVKCommandUse prev, MVKCommandUse next) {
	if (prev == next)
		return false;
	if (getDispatchType(prev) != getDispatchType(next))
		return true;
	return wantsSeparateComputeEncoder(prev) || wantsSeparateComputeEncoder(next);
}

id<MTLComputeCommandEncoder> MVKCommandEncoder::getMTLComputeEncoder(MVKCommandUse cmdUse) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) { failMetal4Encoding("Unported legacy compute operation"); return nil; }
#endif
	bool needWaits = false;
	if (!_mtlComputeEncoder || shouldStartNewEncoder(_mtlComputeEncoderUse, cmdUse)) {
		needWaits = true;
		endCurrentMetalEncoding();
		_mtlComputeEncoder = [_mtlCmdBuffer computeCommandEncoderWithDispatchType:getDispatchType(cmdUse)];
		retainIfImmediatelyEncoding(_mtlComputeEncoder);
		beginMetalComputeEncoding(cmdUse);
	}
	if (_mtlComputeEncoderUse != cmdUse) {
		needWaits = true;
		_mtlComputeEncoderUse = cmdUse;
		MVKBarrierStage stage = commandUseToBarrierStage(cmdUse);
		if (stage != kMVKBarrierStageNone) {
			mvkEnableFlags(_mtlComputeEncoderStages, 1 << stage);
		}
		_cmdBuffer->setMetalObjectLabel(_mtlComputeEncoder, mvkMTLComputeCommandEncoderLabel(cmdUse));
	}
	if (needWaits) {
		encodeBarrierWaits(cmdUse);
	}
	return _mtlComputeEncoder;
}

id<MTLBlitCommandEncoder> MVKCommandEncoder::getMTLBlitEncoder(MVKCommandUse cmdUse) {
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) { failMetal4Encoding("Unported legacy blit operation"); return nil; }
#endif
	bool needWaits = false;
	if ( !_mtlBlitEncoder ) {
		needWaits = true;
		endCurrentMetalEncoding();
		_mtlBlitEncoder = [_mtlCmdBuffer blitCommandEncoder];
		retainIfImmediatelyEncoding(_mtlBlitEncoder);
	}
    if (_mtlBlitEncoderUse != cmdUse) {
		needWaits = true;
        _mtlBlitEncoderUse = cmdUse;
		_cmdBuffer->setMetalObjectLabel(_mtlBlitEncoder, mvkMTLBlitCommandEncoderLabel(cmdUse));
    }
	if (needWaits) {
		encodeBarrierWaits(cmdUse);
	}
	return _mtlBlitEncoder;
}

id<MTLCommandEncoder> MVKCommandEncoder::getMTLEncoder(){
	if (_mtlRenderEncoder) { return _mtlRenderEncoder; }
	if (_mtlComputeEncoder) { return _mtlComputeEncoder; }
	if (_mtlBlitEncoder) { return _mtlBlitEncoder; }
	return nil;
}

void MVKCommandEncoder::setVertexBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                       const void* bytes,
                                       NSUInteger length,
                                       uint32_t mtlBuffIndex) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
		getMtlGraphics().bindVertexBytes(mtlEncoder, bytes, length, mtlBuffIndex);
	} else {
		const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
		getMtlGraphics().bindVertexBuffer(mtlEncoder, mtlBuffAlloc->_mtlBuffer, mtlBuffAlloc->_offset, mtlBuffIndex);
	}
}

void MVKCommandEncoder::setFragmentBytes(id<MTLRenderCommandEncoder> mtlEncoder,
                                         const void* bytes,
                                         NSUInteger length,
                                         uint32_t mtlBuffIndex) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
		getMtlGraphics().bindFragmentBytes(mtlEncoder, bytes, length, mtlBuffIndex);
	} else {
		const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
		getMtlGraphics().bindFragmentBuffer(mtlEncoder, mtlBuffAlloc->_mtlBuffer, mtlBuffAlloc->_offset, mtlBuffIndex);
	}
}

void MVKCommandEncoder::setComputeBytes(id<MTLComputeCommandEncoder> mtlEncoder,
                                        const void* bytes,
                                        NSUInteger length,
                                        uint32_t mtlBuffIndex) {
	auto& mtlFeats = getMetalFeatures();
	if (mtlFeats.dynamicMTLBufferSize && length <= mtlFeats.dynamicMTLBufferSize) {
		getMtlCompute().bindBytes(mtlEncoder, bytes, length, mtlBuffIndex);
	} else {
		const MVKMTLBufferAllocation* mtlBuffAlloc = copyToTempMTLBufferAllocation(bytes, length);
		getMtlCompute().bindBuffer(mtlEncoder, mtlBuffAlloc->_mtlBuffer, mtlBuffAlloc->_offset, mtlBuffIndex);
	}
}

// Return the MTLBuffer allocation to the pool once the command buffer is done with it
const MVKMTLBufferAllocation* MVKCommandEncoder::getTempMTLBuffer(NSUInteger length, bool isPrivate, bool isDedicated) {
    MVKMTLBufferAllocation* mtlBuffAlloc = getCommandEncodingPool()->acquireMTLBufferAllocation(length, isPrivate, isDedicated);
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		auto storage = getCommandEncodingPool()->temporaryBufferStorage();
		if (!_metal4Submission->deferRelease([mtlBuffAlloc, storage] {
			mtlBuffAlloc->returnToPool();
		})) {
			// Keep the returned allocation valid until the current command exits.
			// Failed encoding is never submitted; destructor returns this lease.
			_metal4CancelledAllocations.emplace_back(mtlBuffAlloc, std::move(storage));
			failMetal4Encoding("Could not retain temporary allocation lifetime");
		}
		if (!_metal4Submission->addResource(mtlBuffAlloc->_mtlBuffer)) {
			failMetal4Encoding("Could not make temporary allocation resident");
		}
		return mtlBuffAlloc;
	}
#endif
    [_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) { mtlBuffAlloc->returnToPool(); }];
    return mtlBuffAlloc;
}

MVKCommandEncodingPool* MVKCommandEncoder::getCommandEncodingPool() {
	return _cmdBuffer->getCommandPool()->getCommandEncodingPool();
}

// Copies the specified bytes into a temporary allocation within a pooled MTLBuffer, and returns the MTLBuffer allocation.
const MVKMTLBufferAllocation* MVKCommandEncoder::copyToTempMTLBufferAllocation(const void* bytes, NSUInteger length, bool isDedicated) {
	const MVKMTLBufferAllocation* mtlBuffAlloc = getTempMTLBuffer(length, false, isDedicated);
    void* pBuffData = mtlBuffAlloc->getContents();
    memcpy(pBuffData, bytes, length);

    return mtlBuffAlloc;
}


#pragma mark Queries

// Only executes on immediate-mode GPUs. Encode a GPU counter sample command on whichever Metal
// encoder is currently in use, creating a temporary BLIT encoder if no encoder is currently active.
// We only encode the GPU sample if the platform allows encoding at the associated pipeline point.
void MVKCommandEncoder::encodeGPUCounterSample(MVKGPUCounterQueryPool* mvkQryPool, uint32_t sampleIndex, MVKCounterSamplingFlags samplingPoints){
	if (_mtlRenderEncoder) {
		if (mvkIsAnyFlagEnabled(samplingPoints, MVK_COUNTER_SAMPLING_AT_DRAW)) {
			[_mtlRenderEncoder sampleCountersInBuffer: mvkQryPool->getMTLCounterBuffer() atSampleIndex: sampleIndex withBarrier: YES];
		}
	} else if (_mtlComputeEncoder) {
		if (mvkIsAnyFlagEnabled(samplingPoints, MVK_COUNTER_SAMPLING_AT_DISPATCH)) {
			[_mtlComputeEncoder sampleCountersInBuffer: mvkQryPool->getMTLCounterBuffer() atSampleIndex: sampleIndex withBarrier: YES];
		}
	} else if (mvkIsAnyFlagEnabled(samplingPoints, MVK_COUNTER_SAMPLING_AT_BLIT)) {
		[getMTLBlitEncoder(kMVKCommandUseRecordGPUCounterSample) sampleCountersInBuffer: mvkQryPool->getMTLCounterBuffer() atSampleIndex: sampleIndex withBarrier: YES];
	}
}

void MVKCommandEncoder::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
    _occlusionQueryState.beginOcclusionQuery(this, pQueryPool, query, flags);
    uint32_t queryCount = 1;
    if (isInRenderPass() && getSubpass()->isMultiview()) {
        queryCount = getSubpass()->getViewCountInMetalPass(_multiviewPassIndex);
    }
    addActivatedQueries(pQueryPool, query, queryCount);
}

void MVKCommandEncoder::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
    _occlusionQueryState.endOcclusionQuery(this, pQueryPool, query);
}

void MVKCommandEncoder::markTimestamp(MVKTimestampQueryPool* pQueryPool, uint32_t query, VkPipelineStageFlags2 stage) {
	(void)stage; // Both paths conservatively sample at an existing encoding boundary.
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		auto heap = pQueryPool->getMetal4CounterHeap();
		if (!heap || !_metal4Submission->retainObject(heap)) { failMetal4Encoding("Native timestamp heap unavailable"); return; }
		uint32_t count = (isInRenderPass() && getSubpass()->isMultiview()) ? getSubpass()->getViewCountInMetalPass(_multiviewPassIndex) : 1;
		if (isPreparingMetal4Timestamp()) { retainMetal4VulkanState(pQueryPool); }
        else { addActivatedQueries(pQueryPool, query, count); }
		// The native command-buffer timestamp waits for all preceding work.
		// Vulkan permits sampling at a later stage than the requested stage.
		for (uint32_t i = 0; i < count; ++i) {
			_timestampStageCounterQueries.push_back({pQueryPool, query + i});
		}
		// Memoryless attachments cannot survive a native pass split. Sample at
		// its existing end, as the legacy stage-counter path does. This also
		// handles an empty pass without using an empty render stage as a bridge.
		// Pool/heap ownership and completion activation were acquired above.
		if (!_mtl4RenderEncoder) { endCurrentMetalEncoding(); }
		return;
	}
#endif
    uint32_t queryCount = 1;
    if (isInRenderPass() && getSubpass()->isMultiview()) {
        queryCount = getSubpass()->getViewCountInMetalPass(_multiviewPassIndex);
    }
	addActivatedQueries(pQueryPool, query, queryCount);

	if (pQueryPool->hasMTLCounterBuffer()) {
		MVKCounterSamplingFlags sampPts = getMetalFeatures().counterSamplingPoints;
		for (uint32_t qOfst = 0; qOfst < queryCount; qOfst++) {
			if (mvkIsAnyFlagEnabled(sampPts, MVK_COUNTER_SAMPLING_AT_PIPELINE_STAGE)) {
				_timestampStageCounterQueries.push_back({ pQueryPool, query + qOfst });
			} else {
				encodeGPUCounterSample(pQueryPool, query + qOfst, sampPts);
			}
		}
	}
}

#if MVK_BUILD_METAL4_FOUNDATION
void MVKCommandEncoder::encodeMetal4TimestampSamples() {
	if (_mtl4RenderEncoder || _metal4EndingRenderEncoding || _timestampStageCounterQueries.empty()) { return; }
	// Drain before submitting samples. Failure or encoder-boundary re-entry
	// must not replay a request; activation owns the pool through completion.
	MVKSmallVector<GPUCounterQuery, 16> pending;
	pending.swap(_timestampStageCounterQueries);
	if (_metal4EncodingFailed) { return; }
	for (const auto& sample : pending) {
		auto heap = static_cast<MVKTimestampQueryPool*>(sample.queryPool)->getMetal4CounterHeap();
		NSError* error = nil;
		if (!_metal4Submission->writeTimestamp(heap, sample.query, &error)) {
			failMetal4Encoding("Native timestamp completion boundary unavailable");
			return;
		}
	}
}
#endif

// Metal stage GPU counters need to be configured in a Metal render, compute, or BLIT encoder, meaning that the
// Metal encoder needs to know about any Vulkan timestamp commands that will be executed during the execution
// of a renderpass, or set of Vulkan dispatch or BLIT commands. In addition, there are a very small number of
// staged timestamps that can be tracked in any single render, compute, or BLIT pass, meaning a renderpass
// that timestamped after each of many draw calls, would not be trackable. Finally, stage counters are only
// available on tile-based GPU's, which means draw or dispatch calls cannot be individually timestamped.
// We avoid dealing with all this complexity and mismatch between how Vulkan and Metal stage counters operate
// by deferring all timestamps to the end of any batch of Metal encoding, and add a lightweight Metal encoder
// that does minimal work (it won't timestamp if completely empty), and timestamps that work into all of the
// Vulkan timestamp queries that have been executed during the execution of the previous Metal encoder.
void MVKCommandEncoder::encodeTimestampStageCounterSamples() {
	size_t qCnt = _timestampStageCounterQueries.size();
	uint32_t qIdx = 0;
	while (qIdx < qCnt) {

		// With each BLIT pass, consume as many outstanding timestamp queries as possible.
		// Attach an query result to each of the available sample buffer attachments in the BLIT pass descriptor.
		// MTLMaxBlitPassSampleBuffers was defined in the Metal API as 4, but according to Apple, will be removed
		// in Xcode 13 as inaccurate for all platforms. Leave this value at 1 until we can figure out how to
		// accurately determine the length of sampleBufferAttachments on each platform.
		uint32_t maxMTLBlitPassSampleBuffers = 1;		// Was MTLMaxBlitPassSampleBuffers API definition
		auto* bpDesc = [MTLBlitPassDescriptor new];		// temp retained
		for (uint32_t attIdx = 0; attIdx < maxMTLBlitPassSampleBuffers && qIdx < qCnt; attIdx++, qIdx++) {
			auto* sbAttDesc = bpDesc.sampleBufferAttachments[attIdx];
			auto& tsQry = _timestampStageCounterQueries[qIdx];

			// We actually only need to use startOfEncoderSampleIndex, but apparently,
			// and contradicting docs, Metal hits an unexpected validation error if
			// endOfEncoderSampleIndex is left at MTLCounterDontSample.
			sbAttDesc.startOfEncoderSampleIndex = tsQry.query;
			sbAttDesc.endOfEncoderSampleIndex = tsQry.query;
			sbAttDesc.sampleBuffer = tsQry.queryPool->getMTLCounterBuffer();
		}

		auto* mtlEnc = [_mtlCmdBuffer blitCommandEncoderWithDescriptor: bpDesc];
		_cmdBuffer->setMetalObjectLabel(mtlEnc, mvkMTLBlitCommandEncoderLabel(kMVKCommandUseRecordGPUCounterSample));
		[bpDesc release];		// Release temp object
		[mtlEnc waitForFence: getStageCountersMTLFence()];
		[mtlEnc fillBuffer: _device->getDummyBlitMTLBuffer() range: NSMakeRange(0, 1) value: 0];
		[mtlEnc endEncoding];
	}
	_timestampStageCounterQueries.clear();
}

id<MTLFence> MVKCommandEncoder::getStageCountersMTLFence() {
	if ( !_stageCountersMTLFence ) {
		// Create MTLFence as local ref and pass to completion handler
		// block to release once MTLCommandBuffer no longer needs it.
		id<MTLFence> mtlFence = [getMTLDevice() newFence];
		[_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) { [mtlFence release]; }];

		_stageCountersMTLFence = mtlFence;		// retained
	}
	return _stageCountersMTLFence;
}

void MVKCommandEncoder::resetQueries(MVKQueryPool* pQueryPool, uint32_t firstQuery, uint32_t queryCount) {
    addActivatedQueries(pQueryPool, firstQuery, queryCount);
}

// Marks the specified queries as activated
void MVKCommandEncoder::addActivatedQueries(MVKQueryPool* pQueryPool, uint32_t query, uint32_t queryCount) {
    if ( !_pActivatedQueries ) { _pActivatedQueries = new MVKActivatedQueries(); }
    // The Metal completion handler may run after the Vulkan submission signals.
    // Keep each pool alive until the handler has finished marking its queries.
    auto [it, inserted] = _pActivatedQueries->try_emplace(pQueryPool);
    if (inserted) {
        pQueryPool->retain();
    }
#if MVK_BUILD_METAL4_FOUNDATION
    size_t previousCount = it->second.size();
#endif
    uint32_t endQuery = query + queryCount;
    while (query < endQuery) {
        it->second.push_back(query++);
    }
#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		// Capture the reset generation at activation, not at command-buffer
		// completion registration where another queue may already have reset it.
		_metal4QueryCompletions.push_back(pQueryPool->captureMetal4Completion({it->second.data() + previousCount, queryCount}));
	}
#endif
}

// Register a command buffer completion handler that finishes each activated query.
// Ownership of the collection of activated queries is passed to the handler.
void MVKCommandEncoder::finishQueries() {
    if ( !_pActivatedQueries ) { return; }

#if MVK_BUILD_METAL4_FOUNDATION
	if (isUsingMetal4()) {
		// Callback ownership also releases pools when a recording batch is
		// cancelled, while availability is published only after GPU completion.
		auto queries = std::shared_ptr<MVKActivatedQueries>(_pActivatedQueries, [](MVKActivatedQueries* value) {
			for (auto& item : *value) { item.first->release(); }
			delete value;
		});
		_pActivatedQueries = nullptr;
		auto completions = std::move(_metal4QueryCompletions);
		if (!_metal4Submission->addCompletedHandler([queries, completions](NSError*) {
			for (const auto& complete : completions) { complete(); }
		})) { failMetal4Encoding("Could not register native query completion"); }
		return;
	}
#endif

    MVKActivatedQueries* pAQs = _pActivatedQueries;
    [_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mtlCmdBuff) {
        for (auto& qryPair : *pAQs) {
            qryPair.first->finishQueries(qryPair.second.contents());
            qryPair.first->release();
        }
        delete pAQs;
    }];
    _pActivatedQueries = nullptr;
}


#pragma mark Construction

MVKCommandEncoder::MVKCommandEncoder(MVKCommandBuffer* cmdBuffer, MVKPrefillMetalCommandBuffersStyle prefillStyle)
	: MVKBaseDeviceObject(cmdBuffer->getDevice())
	, _cmdBuffer(cmdBuffer)
	, _prefillStyle(prefillStyle) {
	_pActivatedQueries = nullptr;
	_mtlCmdBuffer = nil;
	_mtlRenderEncoder = nil;
	_hasMTLRenderEncoderVisibilityResultBuffer = false;
	_mtlComputeEncoder = nil;
	_mtlComputeEncoderUse = kMVKCommandUseNone;
	_mtlComputeEncoderStages = 0;
	_mtlBlitEncoder = nil;
	_mtlBlitEncoderUse = kMVKCommandUseNone;
	_pEncodingContext = nullptr;
	_stageCountersMTLFence = nil;
	_flushCount = 0;
}

MVKCommandEncoder::~MVKCommandEncoder() {
#if MVK_BUILD_METAL4_FOUNDATION
    // An activated prepared prefix can be cancelled before finishQueries moves
    // ownership to the submission callback. Release without publishing results.
    if (_metal4Submission && _pActivatedQueries) {
        for (auto& item : *_pActivatedQueries) { item.first->release(); }
        delete _pActivatedQueries; _pActivatedQueries = nullptr;
    }
    for (auto* object : _metal4VulkanStateOwners) { object->release(); }
    [_mtl4RenderEncoder release];
    [_mtl4ComputeEncoder release];
	for (auto& allocation : _metal4CancelledAllocations) {
		allocation.first->returnToPool();
		allocation.second.reset();
	}
#endif
	[_mtlRenderEncoder release];
	[_mtlComputeEncoder release];
	[_mtlBlitEncoder release];
	// _stageCountersMTLFence is released after Metal command buffer completion
}


#pragma mark -
#pragma mark Support functions

NSString* mvkMTLRenderCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
		case kMVKCommandUseBeginRendering:                  return @"vkCmdBeginRendering RenderEncoder";
        case kMVKCommandUseBeginRenderPass:                 return @"vkCmdBeginRenderPass RenderEncoder";
        case kMVKCommandUseNextSubpass:                     return @"vkCmdNextSubpass RenderEncoder";
		case kMVKCommandUseRestartSubpass:                  return @"Metal renderpass restart RenderEncoder";
        case kMVKCommandUseBlitImage:                       return @"vkCmdBlitImage RenderEncoder";
        case kMVKCommandUseResolveImage:                    return @"vkCmdResolveImage (resolve stage) RenderEncoder";
        case kMVKCommandUseResolveSubpassAttachment:        return @"Resolve Subpass Attachment RenderEncoder";
        case kMVKCommandUseResolveExpandImage:              return @"vkCmdResolveImage (expand stage) RenderEncoder";
        case kMVKCommandUseClearColorImage:                 return @"vkCmdClearColorImage RenderEncoder";
        case kMVKCommandUseClearDepthStencilImage:          return @"vkCmdClearDepthStencilImage RenderEncoder";
        default:                                            return @"Unknown Use RenderEncoder";
    }
}

NSString* mvkMTLBlitCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
        case kMVKCommandUsePipelineBarrier:                 return @"vkCmdPipelineBarrier BlitEncoder";
        case kMVKCommandUseCopyImage:                       return @"vkCmdCopyImage BlitEncoder";
        case kMVKCommandUseResolveCopyImage:                return @"vkCmdResolveImage (copy stage) RenderEncoder";
        case kMVKCommandUseCopyBuffer:                      return @"vkCmdCopyBuffer BlitEncoder";
        case kMVKCommandUseCopyBufferToImage:               return @"vkCmdCopyBufferToImage BlitEncoder";
        case kMVKCommandUseCopyImageToBuffer:               return @"vkCmdCopyImageToBuffer BlitEncoder";
        case kMVKCommandUseFillBuffer:                      return @"vkCmdFillBuffer BlitEncoder";
        case kMVKCommandUseUpdateBuffer:                    return @"vkCmdUpdateBuffer BlitEncoder";
        case kMVKCommandUseResetQueryPool:                  return @"vkCmdResetQueryPool BlitEncoder";
        case kMVKCommandUseCopyQueryPoolResults:            return @"vkCmdCopyQueryPoolResults BlitEncoder";
		case kMVKCommandUseRecordGPUCounterSample:          return @"Record GPU Counter Sample BlitEncoder";
        default:                                            return @"Unknown Use BlitEncoder";
    }
}

NSString* mvkMTLComputeCommandEncoderLabel(MVKCommandUse cmdUse) {
    switch (cmdUse) {
        case kMVKCommandUseDispatch:                        return @"vkCmdDispatch ComputeEncoder";
        case kMVKCommandUseCopyBuffer:                      return @"vkCmdCopyBuffer ComputeEncoder";
        case kMVKCommandUseCopyBufferToImage:               return @"vkCmdCopyBufferToImage ComputeEncoder";
        case kMVKCommandUseCopyImageToBuffer:               return @"vkCmdCopyImageToBuffer ComputeEncoder";
        case kMVKCommandUseFillBuffer:                      return @"vkCmdFillBuffer ComputeEncoder";
        case kMVKCommandUseClearColorImage:                 return @"vkCmdClearColorImage ComputeEncoder";
        case kMVKCommandUseResolveSubpassAttachment:        return @"Resolve Subpass Attachment ComputeEncoder";
        case kMVKCommandUseTessellationVertexTessCtl:       return @"vkCmdDraw (vertex and tess control stages) ComputeEncoder";
        case kMVKCommandUseDrawIndirectConvertBuffers:      return @"vkCmdDraw (convert indirect buffers) ComputeEncoder";
        case kMVKCommandUseCopyQueryPoolResults:            return @"vkCmdCopyQueryPoolResults ComputeEncoder";
        case kMVKCommandUseAccumOcclusionQuery:             return @"Post-render-pass occlusion query accumulation ComputeEncoder";
        case kMVKCommandConvertUint8Indices:                return @"Convert Uint8 indices to Uint16 ComputeEncoder";
        default:                                            return @"Unknown Use ComputeEncoder";
    }
}
