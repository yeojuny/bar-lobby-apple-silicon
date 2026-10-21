/*
 * MVKCmdTransfer.mm
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

#include "MVKCmdTransfer.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKCommandEncodingPool.h"
#include "MVKImage.h"
#include "MVKBuffer.h"
#include "MVKFramebuffer.h"
#include "MVKRenderPass.h"
#include "mvk_datatypes.hpp"
#include <algorithm>
#include <sys/mman.h>
#if MVK_BUILD_METAL4_FOUNDATION
#include "MVKMetal4Submission.h"
#include "MVKMetal4ArgumentTable.h"
#include "MVKCommandResourceFactory.h"
#include "MVKDeviceMemory.h"
#include <initializer_list>

static bool mvkMetal4TransferResource(MVKCommandEncoder* encoder, id<MTLResource> resource) {
    NSError* error = nil;
    if (!resource || !encoder->getMetal4Submission()->addResource(resource, &error)) {
        encoder->failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Missing Metal 4 transfer resource.");
        return false;
    }
    return true;
}

// Command-pool scratch caches can alias between independent Vulkan queues.
// Native transfer scratch belongs to this submission until GPU retirement.
static MVKBuffer* mvkNewMetal4TransferBuffer(MVKCommandEncoder* encoder, MVKBufferDescriptorData& description) {
    auto* device = encoder->getDevice();
    MVKDeviceMemory* memory = nullptr;
    MVKBuffer* buffer = device->getCommandResourceFactory()->newMVKBuffer(description, memory);
    auto release = [device, buffer, memory] {
        if (buffer) device->destroyBuffer(buffer, nullptr);
        if (memory) device->freeMemory(memory, nullptr);
    };
    NSError* error = nil;
    if (!buffer || !memory || buffer->getConfigurationResult() != VK_SUCCESS || !buffer->getMTLBuffer() ||
        !encoder->getMetal4Submission()->deferRelease(release, &error)) {
        release();
        encoder->failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Could not allocate native transfer scratch buffer.");
        return nullptr;
    }
    return buffer;
}

static MVKImage* mvkNewMetal4TransferImage(MVKCommandEncoder* encoder, MVKImageDescriptorData& description) {
    auto* device = encoder->getDevice();
    MVKImage* image = device->getCommandResourceFactory()->newMVKImage(description);
    auto release = [device, image] { if (image) device->destroyImage(image, nullptr); };
    NSError* error = nil;
    if (!image || image->getConfigurationResult() != VK_SUCCESS || !image->getMTLTexture() ||
        !encoder->getMetal4Submission()->deferRelease(release, &error)) {
        release();
        encoder->failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Could not allocate native transfer scratch image.");
        return nullptr;
    }
    return image;
}

// Helper kernels use their existing MSL ABI, with native root argument tables.
// A later application dispatch rebinds its pipeline and complete root table.
static bool mvkBindMetal4Transfer(MVKCommandEncoder* encoder,
                                id<MTL4ComputeCommandEncoder> compute,
                                id<MTLComputePipelineState> pipeline,
                                std::initializer_list<std::pair<id<MTLBuffer>, NSUInteger>> buffers) {
    if (!compute || !pipeline) {
        encoder->failMetal4Encoding("Missing Metal 4 transfer encoder or helper pipeline.");
        return false;
    }
    NSError* error = nil;
    auto* submission = encoder->getMetal4Submission();
    auto* tables = encoder->getMetal4ComputeHelperArgumentTables({buffers.size(), 0, 0});
    bool valid = tables != nullptr;
    NSUInteger index = 0;
    for (auto& binding : buffers) {
        if (!valid) break;
        valid = submission->addResource(binding.first, &error) &&
                tables->setBuffer(MVKMetal4ArgumentTables::Stage::Compute, binding.first, binding.second, index++, &error);
    }
    valid = valid && submission->retainObject(pipeline, &error) &&
            tables->bindCompute(compute, &error);
    if (!valid) {
        encoder->failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Could not bind Metal 4 transfer helper.");
        return false;
    }
    [compute setComputePipelineState:pipeline];
    return true;
}

static id<MTL4RenderCommandEncoder> mvkBeginMetal4TransferPass(MVKCommandEncoder* encoder, MTLRenderPassDescriptor* source, NSString* label) {
    MTL4RenderPassDescriptor* descriptor = [[MTL4RenderPassDescriptor new] autorelease];
    descriptor.colorAttachments[0] = source.colorAttachments[0];
    descriptor.depthAttachment = source.depthAttachment;
    descriptor.stencilAttachment = source.stencilAttachment;
    descriptor.renderTargetArrayLength = source.renderTargetArrayLength;
    for (id<MTLTexture> texture : {source.colorAttachments[0].texture, source.colorAttachments[0].resolveTexture,
                                  source.depthAttachment.texture, source.depthAttachment.resolveTexture,
                                  source.stencilAttachment.texture, source.stencilAttachment.resolveTexture}) {
        if (texture && !mvkMetal4TransferResource(encoder, texture)) return nil;
    }
    id<MTL4RenderCommandEncoder> clear = [encoder->getMetal4Submission()->commandBuffer() renderCommandEncoderWithDescriptor:descriptor];
    if (!clear) { encoder->failMetal4Encoding("Could not create native image transfer pass."); return nil; }
    clear.label = label;
    [clear barrierAfterQueueStages:(MTLStageVertex | MTLStageFragment | MTLStageDispatch | MTLStageBlit)
                      beforeStages:(MTLStageVertex | MTLStageFragment)
                 visibilityOptions:(MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias)];
    return clear;
}

static bool mvkEncodeMetal4ClearPass(MVKCommandEncoder* encoder, MTLRenderPassDescriptor* source, NSString* label) {
    id<MTL4RenderCommandEncoder> clear = mvkBeginMetal4TransferPass(encoder, source, label);
    if (!clear) return false;
    [clear endEncoding];
    return true;
}

static bool mvkEncodeMetal4BlitPass(MVKCommandEncoder* encoder, MTLRenderPassDescriptor* descriptor,
                                  NSString* label, id<MTLRenderPipelineState> pipeline,
                                  id<MTLDepthStencilState> depthState, id<MTLTexture> source,
                                  const MVKImageBlitRender& blit, uint32_t layer, bool layered,
                                  VkExtent3D sourceExtent, VkExtent3D destinationExtent, uint32_t destinationLayers) {
    auto* submission = encoder->getMetal4Submission();
    NSError* error = nil;
    MVKMetal4ArgumentTables tables;
    MVKVertexPosTex blitVertices[kMVKBlitVertexCount];
    memcpy(blitVertices, blit.vertices, sizeof(blitVertices));
    float zIncrement = 0.0f;
    if (source.textureType == MTLTextureType3D) {
        // The existing layered vertex helper adds (instanceID + 0.5) *
        // zIncrement. Normalize against the SOURCE mip depth, which can differ
        // from the destination mip depth during volume mipmap generation.
        id<MTLTexture> destination = descriptor.colorAttachments[0].texture;
        if (!destination) destination = descriptor.depthAttachment.texture;
        if (!destination) destination = descriptor.stencilAttachment.texture;
        float destinationStart = blit.region.dstOffsets[0].z;
        float destinationEnd = blit.region.dstOffsets[1].z;
        if (destination.textureType != MTLTextureType3D) {
            destinationStart = blit.region.dstSubresource.baseArrayLayer;
            destinationEnd = destinationStart + destinationLayers;
        }
        if (!sourceExtent.depth || destinationStart == destinationEnd) {
            encoder->failMetal4Encoding("Native 3D blit has an empty source depth or destination slice range."); return false;
        }
        float start = float(blit.region.srcOffsets[0].z) / float(sourceExtent.depth);
        float end = float(blit.region.srcOffsets[1].z) / float(sourceExtent.depth);
        if (layered && destinationStart > destinationEnd) std::swap(start, end);
        zIncrement = (end - start) / mvkAbsDiff(destinationEnd, destinationStart);
        float z = start + (layered ? 0.0f : (float(layer) + 0.5f)) * zIncrement;
        for (auto& vertex : blitVertices) vertex.texCoord.z = z;
    }
    const struct { uint32_t slice; float lod; } subresource = {
        blit.region.srcSubresource.baseArrayLayer + layer, float(blit.region.srcSubresource.mipLevel)
    };
    // These helper inputs are immutable until GPU completion, so they can share
    // the submission's upload slabs. Each binding must retain its slice offset.
    auto vertices = submission->uploadBytesRange(blitVertices, sizeof(blitVertices), &error);
    auto subresourceBuffer = submission->uploadBytesRange(&subresource, sizeof(subresource), &error);
    auto increment = layered ? submission->uploadBytesRange(&zIncrement, sizeof(zIncrement), &error) : MVKMetal4Upload{};
    bool stencil = (blit.region.srcSubresource.aspectMask & VK_IMAGE_ASPECT_STENCIL_BIT) != 0;
    bool stencilOnly = blit.region.srcSubresource.aspectMask == VK_IMAGE_ASPECT_STENCIL_BIT;
    id<MTLTexture> stencilSource = source;
    if (stencil && encoder->getPixelFormats()->isDepthFormat(source.pixelFormat) &&
        encoder->getPixelFormats()->isStencilFormat(source.pixelFormat)) {
        MTLPixelFormat format = source.pixelFormat == MTLPixelFormatDepth32Float_Stencil8 ?
            MTLPixelFormatX32_Stencil8 : MTLPixelFormatInvalid;
#if MVK_MACOS
        if (source.pixelFormat == MTLPixelFormatDepth24Unorm_Stencil8) format = MTLPixelFormatX24_Stencil8;
#endif
        if (format == MTLPixelFormatInvalid) { encoder->failMetal4Encoding("Unsupported native stencil view format."); return false; }
        stencilSource = [source newTextureViewWithPixelFormat:format];
        bool retained = mvkMetal4TransferResource(encoder, stencilSource);
        [stencilSource release];
        if (!retained) return false;
    }
    bool valid = vertices.buffer && subresourceBuffer.buffer && (!layered || increment.buffer) &&
                 tables.initialize(encoder->getMTLDevice(), {31, 2, 0}, &error) &&
                 submission->addResource(source, &error) &&
                 submission->retainObject(pipeline, &error) && submission->retainObject(depthState, &error) &&
                 tables.setBuffer(MVKMetal4ArgumentTables::Stage::Vertex, vertices.buffer, vertices.offset,
                     encoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex), &error) &&
                 tables.setBuffer(MVKMetal4ArgumentTables::Stage::Fragment, subresourceBuffer.buffer, subresourceBuffer.offset, 0, &error);
    if (valid && !stencilOnly) valid = tables.setTexture(MVKMetal4ArgumentTables::Stage::Fragment, source, 0, &error);
    if (valid && stencil) valid = tables.setTexture(MVKMetal4ArgumentTables::Stage::Fragment, stencilSource, 1, &error);
    if (valid && layered) valid = tables.setBuffer(MVKMetal4ArgumentTables::Stage::Vertex, increment.buffer, increment.offset, 0, &error);
    valid = valid && submission->retainObject(tables.getTable(MVKMetal4ArgumentTables::Stage::Vertex, &error), &error) &&
            submission->retainObject(tables.getTable(MVKMetal4ArgumentTables::Stage::Fragment, &error), &error);
    if (!valid) {
        encoder->failMetal4Encoding(error ? error.localizedDescription.UTF8String : "Could not bind native image blit helper.");
        return false;
    }
    id<MTL4RenderCommandEncoder> render = mvkBeginMetal4TransferPass(encoder, descriptor, label);
    if (!render) return false;
    if (!tables.bindRender(render, MTLRenderStageVertex | MTLRenderStageFragment, &error)) {
        [render endEncoding];
        encoder->failMetal4Encoding(error.localizedDescription.UTF8String);
        return false;
    }
    [render setRenderPipelineState:pipeline];
    [render setDepthStencilState:depthState];
    [render setViewport:MTLViewport{0, 0, double(destinationExtent.width), double(destinationExtent.height), 0, 1}];
    [render setScissorRect:MTLScissorRect{0, 0, destinationExtent.width, destinationExtent.height}];
    [render drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:kMVKBlitVertexCount
             instanceCount:layered ? descriptor.renderTargetArrayLength : 1];
    [render endEncoding];
    return true;
}
#endif


#pragma mark -
#pragma mark Support functions

// Clamps the size so that the sum of the origin and size do not exceed the maximum size.
static inline MTLSize mvkClampMTLSize(MTLSize size, MTLOrigin origin, MTLSize maxSize) {
	MTLSize clamped;
	clamped.width = std::min(size.width, maxSize.width - origin.x);
	clamped.height = std::min(size.height, maxSize.height - origin.y);
	clamped.depth = std::min(size.depth, maxSize.depth - origin.z);
	return clamped;
}


#pragma mark -
#pragma mark MVKCmdCopyImage

template <size_t N>
VkResult MVKCmdCopyImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										VkImage srcImage,
										VkImageLayout srcImageLayout,
										VkImage dstImage,
										VkImageLayout dstImageLayout,
										uint32_t regionCount,
										const VkImageCopy* pRegions) {
	_srcImage = (MVKImage*)srcImage;
	_srcLayout = srcImageLayout;

	_dstImage = (MVKImage*)dstImage;
	_dstLayout = dstImageLayout;

	_vkImageCopies.clear();		// Clear for reuse
    for (uint32_t regionIdx = 0; regionIdx < regionCount; regionIdx++) {
        auto& vkIR = pRegions[regionIdx];
        VkImageCopy2 vkIR2 = {
            VK_STRUCTURE_TYPE_IMAGE_COPY_2, nullptr,
            vkIR.srcSubresource, vkIR.srcOffset,
            vkIR.dstSubresource, vkIR.dstOffset,
            vkIR.extent
        };
        
        if (auto validation = validate(cmdBuff, &vkIR2); validation != VK_SUCCESS)
            return validation;
        
        _vkImageCopies.emplace_back(std::move(vkIR2));
	}
    
	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdCopyImage<N>::setContent(MVKCommandBuffer* cmdBuff,
                                        const VkCopyImageInfo2* pCopyImageInfo) {
    _srcImage = (MVKImage*)pCopyImageInfo->srcImage;
    _srcLayout = pCopyImageInfo->srcImageLayout;

    _dstImage = (MVKImage*)pCopyImageInfo->dstImage;
    _dstLayout = pCopyImageInfo->dstImageLayout;

    _vkImageCopies.clear();        // Clear for reuse
    _vkImageCopies.reserve(pCopyImageInfo->regionCount);
    for (uint32_t regionIdx = 0; regionIdx < pCopyImageInfo->regionCount; regionIdx++) {
        auto& vkIR = pCopyImageInfo->pRegions[regionIdx];
        
        if (auto validation = validate(cmdBuff, &vkIR); validation != VK_SUCCESS)
            return validation;
        
        _vkImageCopies.push_back(vkIR);
    }
    
    return VK_SUCCESS;
}

static inline MTLPixelFormat getDepthStencilAspectFormat(const MTLPixelFormat format, const VkImageAspectFlags aspectMask) {
    if (format == MTLPixelFormatDepth32Float_Stencil8) {
        if (aspectMask & VK_IMAGE_ASPECT_DEPTH_BIT) return MTLPixelFormatDepth32Float;
        if (aspectMask & VK_IMAGE_ASPECT_STENCIL_BIT) return MTLPixelFormatStencil8;
    }
#if MVK_MACOS
    if (format == MTLPixelFormatDepth24Unorm_Stencil8 && (aspectMask & VK_IMAGE_ASPECT_STENCIL_BIT))
        return MTLPixelFormatStencil8;
#endif
    return format;
}

template <size_t N>
inline VkResult MVKCmdCopyImage<N>::validate(MVKCommandBuffer* cmdBuff, const VkImageCopy2* region) {
    uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region->srcSubresource.aspectMask);
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region->dstSubresource.aspectMask);

    // If the format is combined depth-stencil, use the format based on the aspect for the following checks.
    auto srcFormat = getDepthStencilAspectFormat(_srcImage->getMTLPixelFormat(srcPlaneIndex), region->srcSubresource.aspectMask);
    auto dstFormat = getDepthStencilAspectFormat(_dstImage->getMTLPixelFormat(dstPlaneIndex), region->dstSubresource.aspectMask);

    // Validate
    MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
    if ((_dstImage->getSampleCount() != _srcImage->getSampleCount()) ||
        (pixFmts->getBytesPerBlock(srcFormat) != pixFmts->getBytesPerBlock(dstFormat))) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdCopyImage(): Cannot copy between incompatible formats, such as formats of different pixel sizes, or between images with different sample counts.");
    }
    return VK_SUCCESS;
}


template <size_t N>
void MVKCmdCopyImage<N>::encode(MVKCommandEncoder* cmdEncoder, MVKCommandUse commandUse) {
#if MVK_BUILD_METAL4_FOUNDATION
    if (cmdEncoder->isUsingMetal4()) {
        for (const auto& region : _vkImageCopies) {
            uint8_t srcPlane = MVKImage::getPlaneFromVkImageAspectFlags(region.srcSubresource.aspectMask);
            uint8_t dstPlane = MVKImage::getPlaneFromVkImageAspectFlags(region.dstSubresource.aspectMask);
            bool src3D = _srcImage->getMTLTextureType() == MTLTextureType3D;
            bool dst3D = _dstImage->getMTLTextureType() == MTLTextureType3D;
            auto* formats = cmdEncoder->getPixelFormats();
            MTLPixelFormat format = _srcImage->getMTLPixelFormat(srcPlane);
            VkImageAspectFlags aspects = (formats->isDepthFormat(format) ? VK_IMAGE_ASPECT_DEPTH_BIT : 0) |
                                         (formats->isStencilFormat(format) ? VK_IMAGE_ASPECT_STENCIL_BIT : 0);
            if (!aspects) aspects = VK_IMAGE_ASPECT_COLOR_BIT;
            VkImageAspectFlags requested = region.srcSubresource.aspectMask;
            if (!requested || (requested & aspects) != requested || requested != region.dstSubresource.aspectMask || src3D != dst3D ||
                format != _dstImage->getMTLPixelFormat(dstPlane)) {
                cmdEncoder->failMetal4Encoding("Metal 4 image copy format/aspect conversion and 2D/3D crossing are not implemented.");
                return;
            }
            if (requested != aspects) {
                // A texture-to-texture copy has no aspect mask. In particular,
                // copying a packed depth/stencil texture would overwrite the
                // untouched aspect. The existing buffer-image helpers encode
                // DepthFromDepthStencil or StencilFromDepthStencil explicitly.
                if (src3D || _srcImage->getSampleCount() != VK_SAMPLE_COUNT_1_BIT) {
                    cmdEncoder->failMetal4Encoding("Native selective depth/stencil copy requires single-sample 2D textures."); return;
                }
                uint32_t layers = region.srcSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
                    _srcImage->getLayerCount() - region.srcSubresource.baseArrayLayer : region.srcSubresource.layerCount;
                MVKBufferDescriptorData temporaryData;
                temporaryData.size = formats->getBytesPerLayer(format, formats->getBytesPerRow(format, region.extent.width),
                                                               region.extent.height) * region.extent.depth * layers;
                temporaryData.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
                VkBuffer temporary = (VkBuffer)mvkNewMetal4TransferBuffer(cmdEncoder, temporaryData);
                if (!temporary) return;
                VkBufferImageCopy sourceCopy{};
                sourceCopy.imageSubresource = region.srcSubresource; sourceCopy.imageOffset = region.srcOffset; sourceCopy.imageExtent = region.extent;
                VkBufferImageCopy destinationCopy = sourceCopy;
                destinationCopy.imageSubresource = region.dstSubresource; destinationCopy.imageOffset = region.dstOffset;
                MVKCmdBufferImageCopy<N> helper;
                if (helper.setContent(cmdEncoder->_cmdBuffer, temporary, (VkImage)_srcImage, _srcLayout, 1, &sourceCopy, false) != VK_SUCCESS) {
                    cmdEncoder->failMetal4Encoding("Unsupported native depth/stencil source texel layout."); return;
                }
                helper.encode(cmdEncoder);
                if (cmdEncoder->hasMetal4EncodingFailed()) return;
                if (helper.setContent(cmdEncoder->_cmdBuffer, temporary, (VkImage)_dstImage, _dstLayout, 1, &destinationCopy, true) != VK_SUCCESS) {
                    cmdEncoder->failMetal4Encoding("Unsupported native depth/stencil destination texel layout."); return;
                }
                helper.encode(cmdEncoder);
                if (cmdEncoder->hasMetal4EncodingFailed()) return;
                continue;
            }
            id<MTLTexture> src = _srcImage->getMTLTexture(srcPlane);
            id<MTLTexture> dst = _dstImage->getMTLTexture(dstPlane);
            if (!mvkMetal4TransferResource(cmdEncoder, src) || !mvkMetal4TransferResource(cmdEncoder, dst)) return;
            id<MTL4ComputeCommandEncoder> copy = cmdEncoder->getMetal4ComputeEncoder(commandUse, false, false, MTLStageBlit);
            if (!copy) return;
            uint32_t layers = region.srcSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS
                ? _srcImage->getLayerCount() - region.srcSubresource.baseArrayLayer : region.srcSubresource.layerCount;
            MTLOrigin origin = mvkMTLOriginFromVkOffset3D(region.srcOffset);
            MTLSize size = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(region.extent), origin,
                mvkMTLSizeFromVkExtent3D(_srcImage->getExtent3D(srcPlane, region.srcSubresource.mipLevel)));
            for (uint32_t layer = 0; layer < layers; ++layer) {
                [copy copyFromTexture:src sourceSlice:region.srcSubresource.baseArrayLayer + layer
                         sourceLevel:region.srcSubresource.mipLevel sourceOrigin:origin sourceSize:size
                           toTexture:dst destinationSlice:region.dstSubresource.baseArrayLayer + layer
                    destinationLevel:region.dstSubresource.mipLevel
                   destinationOrigin:mvkMTLOriginFromVkOffset3D(region.dstOffset)];
            }
        }
        return;
    }
#endif
    MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
    uint32_t copyCnt = (uint32_t)_vkImageCopies.size();
    VkBufferImageCopy vkSrcCopies[copyCnt];
    VkBufferImageCopy vkDstCopies[copyCnt];
    size_t tmpBuffSize = 0;

    for (uint32_t copyIdx = 0; copyIdx < copyCnt; copyIdx++) {
        auto& vkIC = _vkImageCopies[copyIdx];
        
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIC.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIC.dstSubresource.aspectMask);

        uint32_t layerCount = vkIC.srcSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
            _srcImage->getLayerCount() - vkIC.srcSubresource.baseArrayLayer :
            vkIC.srcSubresource.layerCount;

        MTLPixelFormat srcMTLPixFmt = _srcImage->getMTLPixelFormat(srcPlaneIndex);
        bool isSrcCompressed = _srcImage->getIsCompressed();
        bool isSrcColor = (vkIC.srcSubresource.aspectMask & VK_IMAGE_ASPECT_COLOR_BIT) != 0;
        bool isSrcCombinedDepthStencilAspect = getDepthStencilAspectFormat(srcMTLPixFmt, vkIC.srcSubresource.aspectMask) != srcMTLPixFmt;
        bool canReinterpretSrc = _srcImage->hasPixelFormatView(srcPlaneIndex);

        MTLPixelFormat dstMTLPixFmt = _dstImage->getMTLPixelFormat(dstPlaneIndex);
        bool isDstCompressed = _dstImage->getIsCompressed();
        bool isDstColor = (vkIC.dstSubresource.aspectMask & VK_IMAGE_ASPECT_COLOR_BIT) != 0;
        bool isDstCombinedDepthStencilAspect = getDepthStencilAspectFormat(dstMTLPixFmt, vkIC.dstSubresource.aspectMask) != dstMTLPixFmt;
        bool canReinterpretDst = _dstImage->hasPixelFormatView(dstPlaneIndex);

        bool isEitherCompressed = isSrcCompressed || isDstCompressed;
        bool isOnlyOneColor = isSrcColor != isDstColor;
        bool isOnlyOneCombinedDepthStencilAspect = isSrcCombinedDepthStencilAspect != isDstCombinedDepthStencilAspect;
        bool canReinterpret = canReinterpretSrc || canReinterpretDst;

        // If source and destination can't be reinterpreted to matching formats use a temporary intermediary buffer
        bool useTempBuffer = (srcMTLPixFmt != dstMTLPixFmt) && (isEitherCompressed || isOnlyOneColor || isOnlyOneCombinedDepthStencilAspect || !canReinterpret);

        if (useTempBuffer) {
            // Add copy from source image to temp buffer.
            auto& srcCpy = vkSrcCopies[copyIdx];
            srcCpy.bufferOffset = tmpBuffSize;
            srcCpy.bufferRowLength = 0;
            srcCpy.bufferImageHeight = 0;
            srcCpy.imageSubresource = vkIC.srcSubresource;
            srcCpy.imageOffset = vkIC.srcOffset;
            srcCpy.imageExtent = vkIC.extent;

            // Add copy from temp buffer to destination image.
            // Extent is provided in source texels. If the source is compressed but the
            // destination is not, each destination pixel will consume an entire source block,
            // so we must downscale the destination extent by the size of the source block.
            // Likewise if the destination is compressed and source is not, each source pixel
            // will map to a block of pixels in the destination texture, and we need to
            // adjust destination's extent accordingly.
            VkExtent3D dstExtent = vkIC.extent;
            if (isSrcCompressed && !isDstCompressed) {
                VkExtent2D srcBlockExtent = pixFmts->getBlockTexelSize(srcMTLPixFmt);
                dstExtent.width /= srcBlockExtent.width;
                dstExtent.height /= srcBlockExtent.height;
            } else if (!isSrcCompressed && isDstCompressed) {
                VkExtent2D dstBlockExtent = pixFmts->getBlockTexelSize(dstMTLPixFmt);
                dstExtent.width *= dstBlockExtent.width;
                dstExtent.height *= dstBlockExtent.height;
            }
            auto& dstCpy = vkDstCopies[copyIdx];
            dstCpy.bufferOffset = tmpBuffSize;
            dstCpy.bufferRowLength = 0;
            dstCpy.bufferImageHeight = 0;
            dstCpy.imageSubresource = vkIC.dstSubresource;
            dstCpy.imageOffset = vkIC.dstOffset;
            dstCpy.imageExtent = dstExtent;

            size_t bytesPerRow = pixFmts->getBytesPerRow(srcMTLPixFmt, vkIC.extent.width);
            size_t bytesPerRegion = pixFmts->getBytesPerLayer(srcMTLPixFmt, bytesPerRow, vkIC.extent.height);
            tmpBuffSize += bytesPerRegion * vkIC.extent.depth * layerCount;
        } else {
            // Map the source pixel format to the dest pixel format through a texture view on the reinterpretable texture.
            // If the source and dest pixel formats are the same, this will simply degenerate to the texture itself.
            MTLPixelFormat fmt = (canReinterpretSrc ? _dstImage : _srcImage)->getMTLPixelFormat(canReinterpretSrc ? dstPlaneIndex : srcPlaneIndex);
            id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture(srcPlaneIndex, fmt);
            id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture(dstPlaneIndex, fmt);
            if ( !srcMTLTex || !dstMTLTex ) { return; }

            id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(commandUse);

            // If copies can be performed using direct texture-texture copying, do so
            uint32_t srcLevel = vkIC.srcSubresource.mipLevel;
            uint32_t srcBaseLayer = vkIC.srcSubresource.baseArrayLayer;
            VkExtent3D srcExtent = _srcImage->getExtent3D(srcPlaneIndex, srcLevel);
            uint32_t dstLevel = vkIC.dstSubresource.mipLevel;
            uint32_t dstBaseLayer = vkIC.dstSubresource.baseArrayLayer;
            VkExtent3D dstExtent = _dstImage->getExtent3D(dstPlaneIndex, dstLevel);
            // If the extent completely covers both images, I can copy all layers at once.
            // This will obviously not apply to copies between a 3D and 2D image.
            if (mvkVkExtent3DsAreEqual(srcExtent, vkIC.extent) && mvkVkExtent3DsAreEqual(dstExtent, vkIC.extent)) {
                assert((_srcImage->getMTLTextureType() == MTLTextureType3D) == (_dstImage->getMTLTextureType() == MTLTextureType3D));
                [mtlBlitEnc copyFromTexture: srcMTLTex
                                sourceSlice: srcBaseLayer
                                sourceLevel: srcLevel
                                  toTexture: dstMTLTex
                           destinationSlice: dstBaseLayer
                           destinationLevel: dstLevel
                                 sliceCount: layerCount
                                 levelCount: 1];
            } else {
                MTLOrigin srcOrigin = mvkMTLOriginFromVkOffset3D(vkIC.srcOffset);
                MTLSize srcSize;
                uint32_t layCnt;
                if ((_srcImage->getMTLTextureType() == MTLTextureType3D) != (_dstImage->getMTLTextureType() == MTLTextureType3D)) {
                    // In the case, the number of layers to copy is in extent.depth. Use that value,
                    // then clamp the depth so we don't try to copy more than Metal will allow.
                    layCnt = vkIC.extent.depth;
                    srcSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(vkIC.extent),
                                              srcOrigin,
                                              mvkMTLSizeFromVkExtent3D(srcExtent));
                    srcSize.depth = 1;
                } else {
                    layCnt = layerCount;
                    srcSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(vkIC.extent),
                                              srcOrigin,
                                              mvkMTLSizeFromVkExtent3D(srcExtent));
                }
                MTLOrigin dstOrigin = mvkMTLOriginFromVkOffset3D(vkIC.dstOffset);
                
                for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
                    // We can copy between a 3D and a 2D image easily. Just copy between
                    // one slice of the 2D image and one plane of the 3D image at a time.
                    if ((_srcImage->getMTLTextureType() == MTLTextureType3D) == (_dstImage->getMTLTextureType() == MTLTextureType3D)) {
                        [mtlBlitEnc copyFromTexture: srcMTLTex
                                        sourceSlice: srcBaseLayer + layIdx
                                        sourceLevel: srcLevel
                                       sourceOrigin: srcOrigin
                                         sourceSize: srcSize
                                          toTexture: dstMTLTex
                                   destinationSlice: dstBaseLayer + layIdx
                                   destinationLevel: dstLevel
                                  destinationOrigin: dstOrigin];
                    } else if (_srcImage->getMTLTextureType() == MTLTextureType3D) {
                        [mtlBlitEnc copyFromTexture: srcMTLTex
                                        sourceSlice: srcBaseLayer
                                        sourceLevel: srcLevel
                                       sourceOrigin: MTLOriginMake(srcOrigin.x, srcOrigin.y, srcOrigin.z + layIdx)
                                         sourceSize: srcSize
                                          toTexture: dstMTLTex
                                   destinationSlice: dstBaseLayer + layIdx
                                   destinationLevel: dstLevel
                                  destinationOrigin: dstOrigin];
                    } else {
                        assert(_dstImage->getMTLTextureType() == MTLTextureType3D);
                        [mtlBlitEnc copyFromTexture: srcMTLTex
                                        sourceSlice: srcBaseLayer + layIdx
                                        sourceLevel: srcLevel
                                       sourceOrigin: srcOrigin
                                         sourceSize: srcSize
                                          toTexture: dstMTLTex
                                   destinationSlice: dstBaseLayer
                                   destinationLevel: dstLevel
                                  destinationOrigin: MTLOriginMake(dstOrigin.x, dstOrigin.y, dstOrigin.z + layIdx)];
                    }
                }
            }
        }
    }

    if (tmpBuffSize > 0) {
        MVKBufferDescriptorData tempBuffData;
        tempBuffData.size = tmpBuffSize;
        tempBuffData.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
        VkBuffer tempBuff = (VkBuffer)cmdEncoder->getCommandEncodingPool()->getTransferMVKBuffer(tempBuffData);

        MVKCmdBufferImageCopy<N> cpyCmd;

        // Copy from source image to buffer
        // Create and execute a temporary buffer image command.
        // To be threadsafe...do NOT acquire and return the command from the pool.
        cpyCmd.setContent(cmdEncoder->_cmdBuffer, tempBuff, (VkImage)_srcImage, _srcLayout, copyCnt, vkSrcCopies, false);
        cpyCmd.encode(cmdEncoder);

        // Copy from buffer to destination image
        // Create and execute a temporary buffer image command.
        // To be threadsafe...do NOT acquire and return the command from the pool.
        cpyCmd.setContent(cmdEncoder->_cmdBuffer, tempBuff, (VkImage)_dstImage, _dstLayout, copyCnt, vkDstCopies, true);
        cpyCmd.encode(cmdEncoder);
    }
}

template class MVKCmdCopyImage<1>;
template class MVKCmdCopyImage<4>;


#pragma mark -
#pragma mark MVKCmdBlitImage

template <size_t N>
VkResult MVKCmdBlitImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										VkImage srcImage,
										VkImageLayout srcImageLayout,
										VkImage dstImage,
										VkImageLayout dstImageLayout,
										uint32_t regionCount,
										const VkImageBlit* pRegions,
										VkFilter filter) {

	_srcImage = (MVKImage*)srcImage;
	_srcLayout = srcImageLayout;
	_dstImage = (MVKImage*)dstImage;
	_dstLayout = dstImageLayout;

	_filter = filter;

	bool isDestUnwritableLinear = !cmdBuff->getMetalFeatures().renderLinearTextures && _dstImage->getIsLinear();

	_vkImageBlits.clear();		// Clear for reuse
	for (uint32_t rIdx = 0; rIdx < regionCount; rIdx++) {
		auto& vkIB = pRegions[rIdx];
        VkImageBlit2 vkIB2 = {
            VK_STRUCTURE_TYPE_IMAGE_BLIT_2, nullptr,
            vkIB.srcSubresource, vkIB.srcOffsets[0], vkIB.srcOffsets[1],
            vkIB.dstSubresource, vkIB.dstOffsets[0], vkIB.dstOffsets[1],
        };
        
        if (auto validation = validate(cmdBuff, &vkIB2, isDestUnwritableLinear); validation != VK_SUCCESS)
            return validation;
        
		_vkImageBlits.push_back(vkIB2);
	}

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdBlitImage<N>::setContent(MVKCommandBuffer* cmdBuff,
                                        const VkBlitImageInfo2* pBlitImageInfo) {

    _srcImage = (MVKImage*)pBlitImageInfo->srcImage;
    _srcLayout = pBlitImageInfo->srcImageLayout;
    _dstImage = (MVKImage*)pBlitImageInfo->dstImage;
    _dstLayout = pBlitImageInfo->dstImageLayout;

    _filter = pBlitImageInfo->filter;

    bool isDestUnwritableLinear = !cmdBuff->getMetalFeatures().renderLinearTextures && _dstImage->getIsLinear();

    _vkImageBlits.clear();        // Clear for reuse
    _vkImageBlits.reserve(pBlitImageInfo->regionCount);
    for (uint32_t rIdx = 0; rIdx < pBlitImageInfo->regionCount; rIdx++) {
        auto& vkIB = pBlitImageInfo->pRegions[rIdx];
        
        if (auto validation = validate(cmdBuff, &vkIB, isDestUnwritableLinear); validation != VK_SUCCESS)
            return validation;
        
        _vkImageBlits.emplace_back(vkIB);
    }

    return VK_SUCCESS;
}

template <size_t N>
inline VkResult MVKCmdBlitImage<N>::validate(MVKCommandBuffer *cmdBuff, const VkImageBlit2 *region, bool isDestUnwritableLinear) {
    // Validate - macOS linear images cannot be a scaling or inversion destination
    if (isDestUnwritableLinear && !(canCopyFormats(*region) && canCopy(*region)) ) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdBlitImage(): Scaling or inverting to a linear destination image is not supported.");
    }
    return VK_SUCCESS;
}

template <size_t N>
bool MVKCmdBlitImage<N>::canCopyFormats(const VkImageBlit2& region) {
    uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.srcSubresource.aspectMask);
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.dstSubresource.aspectMask);
	return ((_srcImage->getMTLPixelFormat(srcPlaneIndex) == _dstImage->getMTLPixelFormat(dstPlaneIndex)) &&
			!_srcImage->needsSwizzle() &&
			(_dstImage->getSampleCount() == _srcImage->getSampleCount()));
}

// The source and destination sizes must be equal and not be negative in any direction
template <size_t N>
bool MVKCmdBlitImage<N>::canCopy(const VkImageBlit2& region) {
	VkOffset3D srcSize = mvkVkOffset3DDifference(region.srcOffsets[1], region.srcOffsets[0]);
	VkOffset3D dstSize = mvkVkOffset3DDifference(region.dstOffsets[1], region.dstOffsets[0]);
	return (mvkVkOffset3DsAreEqual(srcSize, dstSize) &&
			(srcSize.x >= 0) && (srcSize.y >= 0) && (srcSize.z >= 0));
}

template <size_t N>
void MVKCmdBlitImage<N>::populateVertices(MVKVertexPosTex* vertices, const VkImageBlit2& region) {
    const VkOffset3D& so0 = region.srcOffsets[0];
    const VkOffset3D& so1 = region.srcOffsets[1];
    const VkOffset3D& do0 = region.dstOffsets[0];
    const VkOffset3D& do1 = region.dstOffsets[1];

    // Get the extents of the source and destination textures.
    uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.srcSubresource.aspectMask);
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region.dstSubresource.aspectMask);
    VkExtent3D srcExtent = _srcImage->getExtent3D(srcPlaneIndex, region.srcSubresource.mipLevel);
    VkExtent3D dstExtent = _dstImage->getExtent3D(dstPlaneIndex, region.dstSubresource.mipLevel);

    // Determine the bottom-left and top-right corners of the source and destination
    // texture regions, each as a fraction of the corresponding texture size.
    CGPoint srcBL = CGPointMake((CGFloat)(so0.x) / (CGFloat)srcExtent.width,
                                (CGFloat)(srcExtent.height - so1.y) / (CGFloat)srcExtent.height);
    CGPoint srcTR = CGPointMake((CGFloat)(so1.x) / (CGFloat)srcExtent.width,
                                (CGFloat)(srcExtent.height - so0.y) / (CGFloat)srcExtent.height);
    CGPoint dstBL = CGPointMake((CGFloat)(do0.x) / (CGFloat)dstExtent.width,
                                (CGFloat)(dstExtent.height - do1.y) / (CGFloat)dstExtent.height);
    CGPoint dstTR = CGPointMake((CGFloat)(do1.x) / (CGFloat)dstExtent.width,
                                (CGFloat)(dstExtent.height - do0.y) / (CGFloat)dstExtent.height);

    // The destination region is used for vertex positions,
    // which are bounded by (-1.0 < p < 1.0) in clip-space.
    // Map texture coordinates (0.0 < p < 1.0) to vertex coordinates (-1.0 < p < 1.0).
    dstBL = CGPointMake((dstBL.x * 2.0) - 1.0, (dstBL.y * 2.0) - 1.0);
    dstTR = CGPointMake((dstTR.x * 2.0) - 1.0, (dstTR.y * 2.0) - 1.0);

    MVKVertexPosTex* pVtx;

    // Bottom left vertex
    pVtx = &vertices[0];
    pVtx->position.x = dstBL.x;
    pVtx->position.y = dstBL.y;
    pVtx->texCoord.x = srcBL.x;
    pVtx->texCoord.y = (1.0 - srcBL.y);

    // Bottom right vertex
    pVtx = &vertices[1];
    pVtx->position.x = dstTR.x;
    pVtx->position.y = dstBL.y;
    pVtx->texCoord.x = srcTR.x;
    pVtx->texCoord.y = (1.0 - srcBL.y);

    // Top left vertex
    pVtx = &vertices[2];
    pVtx->position.x = dstBL.x;
    pVtx->position.y = dstTR.y;
    pVtx->texCoord.x = srcBL.x;
    pVtx->texCoord.y = (1.0 - srcTR.y);

    // Top right vertex
    pVtx = &vertices[3];
    pVtx->position.x = dstTR.x;
    pVtx->position.y = dstTR.y;
    pVtx->texCoord.x = srcTR.x;
    pVtx->texCoord.y = (1.0 - srcTR.y);
}

template <size_t N>
void MVKCmdBlitImage<N>::encode(MVKCommandEncoder* cmdEncoder, MVKCommandUse commandUse) {
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	size_t vkIBCnt = _vkImageBlits.size();
	VkImageCopy vkImageCopies[vkIBCnt];
	MVKImageBlitRender mvkBlitRenders[vkIBCnt];
	uint32_t copyCnt = 0;
	uint32_t blitCnt = 0;

	// Separate BLITs into those that are really just simple texture region copies,
	// and those that require rendering
	for (auto& vkIB : _vkImageBlits) {
		if (canCopyFormats(vkIB) && canCopy(vkIB)) {

			const VkOffset3D& so0 = vkIB.srcOffsets[0];
			const VkOffset3D& so1 = vkIB.srcOffsets[1];

			auto& vkIC = vkImageCopies[copyCnt++];
			vkIC.srcSubresource = vkIB.srcSubresource;
			vkIC.srcOffset = vkIB.srcOffsets[0];
			vkIC.dstSubresource = vkIB.dstSubresource;
			vkIC.dstOffset = vkIB.dstOffsets[0];
			vkIC.extent.width = so1.x - so0.x;
			vkIC.extent.height = so1.y - so0.y;
			vkIC.extent.depth = so1.z - so0.z;

		} else {
			auto& mvkIBR = mvkBlitRenders[blitCnt++];
			mvkIBR.region = vkIB;
			populateVertices(mvkIBR.vertices, vkIB);
		}
	}

	// Perform those BLITs that can be covered by simple texture copying.
	if (copyCnt) {
		MVKCmdCopyImage<N> copyCmd;
		copyCmd.setContent(cmdEncoder->_cmdBuffer,
						   (VkImage)_srcImage, _srcLayout,
						   (VkImage)_dstImage, _dstLayout,
						   copyCnt, vkImageCopies);
		copyCmd.encode(cmdEncoder, kMVKCommandUseBlitImage);
	}

	// Perform those BLITs that require rendering to destination texture.
    for (uint32_t blitIdx = 0; blitIdx < blitCnt; blitIdx++) {
        auto& mvkIBR = mvkBlitRenders[blitIdx];

        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(mvkIBR.region.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(mvkIBR.region.dstSubresource.aspectMask);

        id<MTLTexture> srcMTLTex = _srcImage->getMTLTexture(srcPlaneIndex);
        id<MTLTexture> dstMTLTex = _dstImage->getMTLTexture(dstPlaneIndex);
#if MVK_BUILD_METAL4_FOUNDATION
        if (cmdEncoder->isUsingMetal4() && mvkIBR.region.srcSubresource.aspectMask != mvkIBR.region.dstSubresource.aspectMask) {
            NSString* reason = [NSString stringWithFormat:
                @"Native blit aspect conversion is unsupported: aspects=0x%x->0x%x textureTypes=%lu->%lu formats=%lu->%lu mips=%u->%u.",
                mvkIBR.region.srcSubresource.aspectMask, mvkIBR.region.dstSubresource.aspectMask,
                (unsigned long)_srcImage->getMTLTextureType(), (unsigned long)_dstImage->getMTLTextureType(),
                (unsigned long)_srcImage->getMTLPixelFormat(srcPlaneIndex), (unsigned long)_dstImage->getMTLPixelFormat(dstPlaneIndex),
                mvkIBR.region.srcSubresource.mipLevel, mvkIBR.region.dstSubresource.mipLevel];
            cmdEncoder->failMetal4Encoding(reason.UTF8String);
            return;
        }
#endif
        if (blitCnt && srcMTLTex && dstMTLTex) {
            uint32_t srcSwizzle = 0;
            if (_srcImage->needsSwizzle()) {
                if (mtlFeats.nativeTextureSwizzle) {
                    // Use a view that has a swizzle on it.
                    srcMTLTex = [srcMTLTex newTextureViewWithPixelFormat:srcMTLTex.pixelFormat
                                                              textureType:srcMTLTex.textureType
                                                                   levels:NSMakeRange(0, srcMTLTex.mipmapLevelCount)
                                                                   slices:NSMakeRange(0, srcMTLTex.arrayLength)
                                                                  swizzle:_srcImage->getPixelFormats()->getMTLTextureSwizzleChannels(_srcImage->getVkFormat())];
#if MVK_BUILD_METAL4_FOUNDATION
                    if (cmdEncoder->isUsingMetal4()) {
                        bool retained = mvkMetal4TransferResource(cmdEncoder, srcMTLTex);
                        [srcMTLTex release];
                        if (!retained) return;
                    } else
#endif
                    { [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) { [srcMTLTex release]; }]; }
                } else {
                    srcSwizzle = mvkPackSwizzle(_srcImage->getPixelFormats()->getVkComponentMapping(_srcImage->getVkFormat()));
                }
            }
            cmdEncoder->endCurrentMetalEncoding();

            MTLRenderPassDescriptor* mtlRPD = [MTLRenderPassDescriptor renderPassDescriptor];
            MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPD.colorAttachments[0];
            MTLRenderPassDepthAttachmentDescriptor* mtlDepthAttDesc = mtlRPD.depthAttachment;
            MTLRenderPassStencilAttachmentDescriptor* mtlStencilAttDesc = mtlRPD.stencilAttachment;
            if (mvkIsAnyFlagEnabled(mvkIBR.region.dstSubresource.aspectMask, (VK_IMAGE_ASPECT_DEPTH_BIT))) {
                mtlDepthAttDesc.loadAction = MTLLoadActionLoad;
                mtlDepthAttDesc.storeAction = MTLStoreActionStore;
                mtlDepthAttDesc.texture = dstMTLTex;
            } else {
                mtlDepthAttDesc.loadAction = MTLLoadActionDontCare;
                mtlDepthAttDesc.storeAction = MTLStoreActionDontCare;
                mtlDepthAttDesc.texture = nil;
            }
            if (mvkIsAnyFlagEnabled(mvkIBR.region.dstSubresource.aspectMask, (VK_IMAGE_ASPECT_STENCIL_BIT))) {
                mtlStencilAttDesc.loadAction = MTLLoadActionLoad;
                mtlStencilAttDesc.storeAction = MTLStoreActionStore;
                mtlStencilAttDesc.texture = dstMTLTex;
            } else {
                mtlStencilAttDesc.loadAction = MTLLoadActionDontCare;
                mtlStencilAttDesc.storeAction = MTLStoreActionDontCare;
                mtlStencilAttDesc.texture = nil;
            }
            if (!mvkIsAnyFlagEnabled(mvkIBR.region.dstSubresource.aspectMask, (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT))) {
                mtlColorAttDesc.loadAction = MTLLoadActionLoad;
                mtlColorAttDesc.storeAction = MTLStoreActionStore;
                mtlColorAttDesc.texture = dstMTLTex;
            }

            MVKRPSKeyBlitImg blitKey;
            blitKey.srcMTLPixelFormat = _srcImage->getMTLPixelFormat(srcPlaneIndex);
            blitKey.srcMTLTextureType = _srcImage->getMTLTextureType();
            if (blitKey.srcMTLTextureType == MTLTextureTypeCube || blitKey.srcMTLTextureType == MTLTextureTypeCubeArray) {
                // In this case, I'll use a temp 2D array view. That way, I don't have to
                // deal with mapping the blit coordinates to a cube direction vector.
                blitKey.srcMTLTextureType = MTLTextureType2DArray;
                srcMTLTex = [srcMTLTex newTextureViewWithPixelFormat: blitKey.getSrcMTLPixelFormat()
                                                         textureType: MTLTextureType2DArray
                                                              levels: NSMakeRange(0, srcMTLTex.mipmapLevelCount)
                                                              slices: NSMakeRange(0, srcMTLTex.arrayLength)];
#if MVK_BUILD_METAL4_FOUNDATION
                if (cmdEncoder->isUsingMetal4()) {
                    bool retained = mvkMetal4TransferResource(cmdEncoder, srcMTLTex);
                    [srcMTLTex release];
                    if (!retained) return;
                } else
#endif
                { [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) { [srcMTLTex release]; }]; }
            }
            blitKey.dstMTLPixelFormat = _dstImage->getMTLPixelFormat(dstPlaneIndex);
            blitKey.srcFilter = mvkMTLSamplerMinMagFilterFromVkFilter(_filter);
            blitKey.srcAspect = mvkIBR.region.srcSubresource.aspectMask & (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT);
            blitKey.dstSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_dstImage->getSampleCount());
            blitKey.srcSwizzle = srcSwizzle;
            id<MTLRenderPipelineState> mtlRPS = cmdEncoder->getCommandEncodingPool()->getCmdBlitImageMTLRenderPipelineState(blitKey);
            bool isBlittingDepth = mvkIsAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_DEPTH_BIT));
            bool isBlittingStencil = mvkIsAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_STENCIL_BIT));
            id<MTLDepthStencilState> mtlDSS = cmdEncoder->getCommandEncodingPool()->getMTLDepthStencilState(isBlittingDepth, isBlittingStencil);
            
            mtlColorAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;
            mtlDepthAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;
            mtlStencilAttDesc.level = mvkIBR.region.dstSubresource.mipLevel;

            bool isLayeredBlit = blitKey.dstSampleCount > 1 ? mtlFeats.multisampleLayeredRendering : mtlFeats.layeredRendering;

            uint32_t srcLayCnt = mvkIBR.region.srcSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
                _srcImage->getLayerCount() - mvkIBR.region.srcSubresource.baseArrayLayer :
                 mvkIBR.region.srcSubresource.layerCount;
            uint32_t dstLayCnt = mvkIBR.region.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
                _dstImage->getLayerCount() - mvkIBR.region.dstSubresource.baseArrayLayer :
                 mvkIBR.region.dstSubresource.layerCount;
            uint32_t layCnt;
            // If either image is 3D, the difference in z offset must:
            // - Equal the difference in z offset of the other subresource, if it is also 3D.
            // - Equal the number of layers in the other subresource, if it is not 3D.
            // Otherwise, the number of layers should be the same.
            if (_dstImage->getMTLTextureType() == MTLTextureType3D) {
                layCnt = mvkAbsDiff(mvkIBR.region.dstOffsets[1].z, mvkIBR.region.dstOffsets[0].z);
            } else if (blitKey.srcMTLTextureType == MTLTextureType3D) {
                layCnt = mvkAbsDiff(mvkIBR.region.srcOffsets[1].z, mvkIBR.region.srcOffsets[0].z);
            } else {
                layCnt = srcLayCnt;
            }
            if (isLayeredBlit) {
                // In this case, I can blit all layers at once with a layered draw.
                mtlRPD.renderTargetArrayLength = layCnt;
                layCnt = 1;     // Only need to run the loop once.
            }
            for (uint32_t layIdx = 0; layIdx < layCnt; layIdx++) {
                // Update the render pass descriptor for the texture level and slice, and create a render encoder.
                if (_dstImage->getMTLTextureType() == MTLTextureType3D) {
                    if (isLayeredBlit) {
                        // For layered blits, the layers are always in ascending order. I'll reverse the order
                        // of the 'r' coordinates if the destination is mirrored.
                        uint32_t depthPlane = std::min(mvkIBR.region.dstOffsets[0].z, mvkIBR.region.dstOffsets[1].z);
                        mtlColorAttDesc.depthPlane = depthPlane;
                        mtlDepthAttDesc.depthPlane = depthPlane;
                        mtlStencilAttDesc.depthPlane = depthPlane;
                    } else {
                        uint32_t depthPlane = mvkIBR.region.dstOffsets[0].z + (mvkIBR.region.dstOffsets[1].z > mvkIBR.region.dstOffsets[0].z ? layIdx : -(layIdx + 1));
                        mtlColorAttDesc.depthPlane = depthPlane;
                        mtlDepthAttDesc.depthPlane = depthPlane;
                        mtlStencilAttDesc.depthPlane = depthPlane;
                    }
                } else {
                    mtlColorAttDesc.slice = mvkIBR.region.dstSubresource.baseArrayLayer + layIdx;
                    mtlDepthAttDesc.slice = mvkIBR.region.dstSubresource.baseArrayLayer + layIdx;
                    mtlStencilAttDesc.slice = mvkIBR.region.dstSubresource.baseArrayLayer + layIdx;
                }
#if MVK_BUILD_METAL4_FOUNDATION
                if (cmdEncoder->isUsingMetal4()) {
                    if (!mvkEncodeMetal4BlitPass(cmdEncoder, mtlRPD, mvkMTLRenderCommandEncoderLabel(commandUse),
                            mtlRPS, mtlDSS, srcMTLTex, mvkIBR, layIdx, isLayeredBlit,
                            _srcImage->getExtent3D(srcPlaneIndex, mvkIBR.region.srcSubresource.mipLevel),
                            _dstImage->getExtent3D(dstPlaneIndex, mvkIBR.region.dstSubresource.mipLevel), dstLayCnt)) return;
                    continue;
                }
#endif
                id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPD];
				cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(commandUse));

				cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

                float zIncr;
                if (blitKey.srcMTLTextureType == MTLTextureType3D) {
                    // In this case, I need to interpolate along the third dimension manually.
                    VkExtent3D srcExtent = _srcImage->getExtent3D(srcPlaneIndex, mvkIBR.region.dstSubresource.mipLevel);
                    VkOffset3D so0 = mvkIBR.region.srcOffsets[0], so1 = mvkIBR.region.srcOffsets[1];
                    // If the dst is also 3D use the z offsets, otherwise use the layers.
                    float do0z = mvkIBR.region.dstOffsets[0].z, do1z = mvkIBR.region.dstOffsets[1].z;
                    if (_dstImage->getMTLTextureType() != MTLTextureType3D) {
                        do0z = mvkIBR.region.dstSubresource.baseArrayLayer;
                        do1z = do0z + dstLayCnt;
                    }
                    float startZ = (float)so0.z / (float)srcExtent.depth;
                    float endZ = (float)so1.z / (float)srcExtent.depth;
                    if (isLayeredBlit && do0z > do1z) {
                        // Swap start and end points so interpolation moves in the right direction.
                        std::swap(startZ, endZ);
                    }
                    zIncr = (endZ - startZ) / mvkAbsDiff(do1z, do0z);
                    float z = startZ + (isLayeredBlit ? 0.0 : (layIdx + 0.5)) * zIncr;
                    for (uint32_t i = 0; i < kMVKBlitVertexCount; ++i) {
                        mvkIBR.vertices[i].texCoord.z = z;
                    }
                }
                [mtlRendEnc pushDebugGroup: @"vkCmdBlitImage"];
                [mtlRendEnc setRenderPipelineState: mtlRPS];
                [mtlRendEnc setDepthStencilState: mtlDSS];
                cmdEncoder->setVertexBytes(mtlRendEnc, mvkIBR.vertices, sizeof(mvkIBR.vertices),
										   cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex));
                if (isLayeredBlit) {
                    cmdEncoder->setVertexBytes(mtlRendEnc, &zIncr, sizeof(zIncr), 0);
                }
                if (!mvkIsOnlyAnyFlagEnabled(blitKey.srcAspect, (VK_IMAGE_ASPECT_STENCIL_BIT))) {
                    [mtlRendEnc setFragmentTexture: srcMTLTex atIndex: 0];
                }
                if (isBlittingStencil) {
                    // For stencil blits of packed depth/stencil images, I need to use a stencil view. 
                    MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
                    if (pixFmts->isDepthFormat(blitKey.getSrcMTLPixelFormat()) &&
                        pixFmts->isStencilFormat(blitKey.getSrcMTLPixelFormat())) {
                        MTLPixelFormat stencilFmt = blitKey.getSrcMTLPixelFormat();
                        if (stencilFmt == MTLPixelFormatDepth32Float_Stencil8) {

                            stencilFmt = MTLPixelFormatX32_Stencil8;
#if MVK_MACOS
                        } else if (stencilFmt == MTLPixelFormatDepth24Unorm_Stencil8) {
                            stencilFmt = MTLPixelFormatX24_Stencil8;
#endif
                        }
                        id<MTLTexture> stencilMTLTex = [srcMTLTex newTextureViewWithPixelFormat: stencilFmt];
                        [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer>) { [stencilMTLTex release]; }];
                        [mtlRendEnc setFragmentTexture: stencilMTLTex atIndex: 1];
                    } else {
                        [mtlRendEnc setFragmentTexture: srcMTLTex atIndex: 1];
                    }
                }

                struct {
                    uint slice;
                    float lod;
                } texSubRez;
                texSubRez.slice = mvkIBR.region.srcSubresource.baseArrayLayer + layIdx;
                texSubRez.lod = mvkIBR.region.srcSubresource.mipLevel;
                cmdEncoder->setFragmentBytes(mtlRendEnc, &texSubRez, sizeof(texSubRez), 0);

                NSUInteger instanceCount = isLayeredBlit ? mtlRPD.renderTargetArrayLength : 1;
                [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangleStrip vertexStart: 0 vertexCount: kMVKBlitVertexCount instanceCount: instanceCount];

				cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

				[mtlRendEnc popDebugGroup];
                [mtlRendEnc endEncoding];
            }
        }
    }
}

template class MVKCmdBlitImage<1>;
template class MVKCmdBlitImage<4>;


#pragma mark -
#pragma mark MVKCmdResolveImage

template <size_t N>
VkResult MVKCmdResolveImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										   VkImage srcImage,
										   VkImageLayout srcImageLayout,
										   VkImage dstImage,
										   VkImageLayout dstImageLayout,
										   uint32_t regionCount,
										   const VkImageResolve* pRegions) {
    _srcImage = (MVKImage*)srcImage;
    _srcLayout = srcImageLayout;
    _dstImage = (MVKImage*)dstImage;
    _dstLayout = dstImageLayout;

	_vkImageResolves.clear();	// Clear for reuse
	_vkImageResolves.reserve(regionCount);
    for (uint32_t regionIdx = 0; regionIdx < regionCount; regionIdx++) {
        auto& vkIR = pRegions[regionIdx];
        VkImageResolve2 vkIR2 = {
            VK_STRUCTURE_TYPE_IMAGE_RESOLVE_2, nullptr,
            vkIR.srcSubresource, vkIR.srcOffset,
            vkIR.dstSubresource, vkIR.dstOffset,
            vkIR.extent,
        };
        
        if (auto validation = validate(cmdBuff, &vkIR2); validation != VK_SUCCESS)
            return validation;

		_vkImageResolves.emplace_back(std::move(vkIR2));
    }

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdResolveImage<N>::setContent(MVKCommandBuffer* cmdBuff,
                                           const VkResolveImageInfo2* pResolveImageInfo) {
    _srcImage = (MVKImage*)pResolveImageInfo->srcImage;
    _srcLayout = pResolveImageInfo->srcImageLayout;
    _dstImage = (MVKImage*)pResolveImageInfo->dstImage;
    _dstLayout = pResolveImageInfo->dstImageLayout;

    _vkImageResolves.clear();    // Clear for reuse
    _vkImageResolves.reserve(pResolveImageInfo->regionCount);
    for (uint32_t regionIdx = 0; regionIdx < pResolveImageInfo->regionCount; regionIdx++) {
        auto& vkIR = pResolveImageInfo->pRegions[regionIdx];
        
        if (auto validation = validate(cmdBuff, &vkIR); validation != VK_SUCCESS)
            return validation;
        
        _vkImageResolves.push_back(vkIR);
    }

    return VK_SUCCESS;
}

template <size_t N>
inline VkResult MVKCmdResolveImage<N>::validate(MVKCommandBuffer* cmdBuff, const VkImageResolve2* region) {
    uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(region->dstSubresource.aspectMask);

    // Validate
    MVKPixelFormats* pixFmts = cmdBuff->getPixelFormats();
    if ( !mvkAreAllFlagsEnabled(pixFmts->getCapabilities(_dstImage->getMTLPixelFormat(dstPlaneIndex)), kMVKMTLFmtCapsResolve) ) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdResolveImage(): %s cannot be used as a resolve destination on this device.", pixFmts->getName(_dstImage->getVkFormat()));
    }
    return VK_SUCCESS;
}

template <size_t N>
void MVKCmdResolveImage<N>::encode(MVKCommandEncoder* cmdEncoder) {
	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	size_t vkIRCnt = _vkImageResolves.size();
	VkImageBlit expansionRegions[vkIRCnt];
	VkImageCopy copyRegions[vkIRCnt];

	// If we can do layered rendering to a multisample texture, I can resolve all the layers at once.
	uint32_t layerCnt = 0;
	if (mtlFeats.multisampleLayeredRendering) {
		layerCnt = (uint32_t)_vkImageResolves.size();
	} else {
		for (VkImageResolve2& vkIR : _vkImageResolves) {
			uint32_t dstLayCnt = vkIR.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
				_dstImage->getLayerCount() - vkIR.dstSubresource.baseArrayLayer :
				vkIR.dstSubresource.layerCount;
			layerCnt += dstLayCnt;
		}
	}
	MVKMetalResolveSlice mtlResolveSlices[layerCnt];

	uint32_t expCnt = 0;
	uint32_t copyCnt = 0;
	uint32_t sliceCnt = 0;

	for (const auto& vkIR : _vkImageResolves) {
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.dstSubresource.aspectMask);

		VkExtent3D srcImgExt = _srcImage->getExtent3D(srcPlaneIndex, vkIR.srcSubresource.mipLevel);
		VkExtent3D dstImgExt = _dstImage->getExtent3D(dstPlaneIndex, vkIR.dstSubresource.mipLevel);

		// If the region does not cover the entire content of the destination level, expand
		// the destination content in the region to the temporary image. The purpose of this
		// expansion is to render the existing content of the destination image to the
		// temporary transfer multisample image, so that regions of that temporary transfer
		// image can then be overwritten with content from the source image, prior to
		// resolving it back to the destination image.
		if ( !mvkVkExtent3DsAreEqual(dstImgExt, vkIR.extent) ) {
			VkImageBlit& expRgn = expansionRegions[expCnt++];
			expRgn.srcSubresource = vkIR.dstSubresource;
			expRgn.srcOffsets[0] = { 0, 0, 0 };
			expRgn.srcOffsets[1] = { int32_t(dstImgExt.width), int32_t(dstImgExt.height), int32_t(dstImgExt.depth) };
			expRgn.dstSubresource = vkIR.dstSubresource;
			expRgn.dstOffsets[0] = { 0, 0, 0 };
			expRgn.dstOffsets[1] = { int32_t(dstImgExt.width), int32_t(dstImgExt.height), int32_t(dstImgExt.depth) };
		}

		// Copy the region from the source image to the temporary multisample image,
		// prior to the temporary image being resolved back to the destination image.
		// The source of this copy stage is the source image, and the destination of
		// this copy stage is the temporary transfer image.
		bool needXfrImage = !mvkVkExtent3DsAreEqual(srcImgExt, vkIR.extent) || !mvkVkExtent3DsAreEqual(dstImgExt, vkIR.extent);
		if ( needXfrImage ) {
			VkImageCopy& cpyRgn = copyRegions[copyCnt++];
			cpyRgn.srcSubresource = vkIR.srcSubresource;
			cpyRgn.srcOffset = vkIR.srcOffset;
			cpyRgn.dstSubresource = vkIR.dstSubresource;
			cpyRgn.dstOffset = vkIR.dstOffset;
			cpyRgn.extent = vkIR.extent;
		}

		// Adds a resolve slice struct for each destination layer in the resolve region.
		// Note that the source subresource for this is that of the SOURCE image if we're doing a
		// direct resolve, but that of the DESTINATION if we need a temporary transfer image.
		mtlResolveSlices[sliceCnt].dstSubresource = vkIR.dstSubresource;
		mtlResolveSlices[sliceCnt].srcSubresource = needXfrImage ? vkIR.dstSubresource : vkIR.srcSubresource;
		if (mtlFeats.multisampleLayeredRendering) {
			sliceCnt++;
		} else {
			uint32_t layCnt = vkIR.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
				_dstImage->getLayerCount() - vkIR.dstSubresource.baseArrayLayer :
				vkIR.dstSubresource.layerCount;
			mtlResolveSlices[sliceCnt].dstSubresource.layerCount = 1;
			mtlResolveSlices[sliceCnt].srcSubresource.layerCount = 1;
			sliceCnt++;
			for (uint32_t layIdx = 1; layIdx < layCnt; layIdx++) {
				MVKMetalResolveSlice& rslvSlice = mtlResolveSlices[sliceCnt];
				rslvSlice = mtlResolveSlices[sliceCnt - 1];
				rslvSlice.dstSubresource.baseArrayLayer++;
				rslvSlice.srcSubresource.baseArrayLayer++;
				sliceCnt++;
			}
		}
	}

    // Expansion and copying is not required. Each mip level of the source image
    // is being resolved entirely. Resolve directly from the source image.
    MVKImage* xfrImage = _srcImage;
	if (copyCnt) {
		// Expansion and/or copying is required. Acquire a temporary transfer image, expand
		// the destination image into it if necessary, copy from the source image to the
		// temporary image, and then resolve from the temporary image to the destination image.
		MVKImageDescriptorData xferImageData;
		_dstImage->getTransferDescriptorData(xferImageData);
		xferImageData.samples = _srcImage->getSampleCount();
#if MVK_BUILD_METAL4_FOUNDATION
        if (cmdEncoder->isUsingMetal4()) {
            xfrImage = mvkNewMetal4TransferImage(cmdEncoder, xferImageData);
            if (!xfrImage) return;
        } else
#endif
		{ xfrImage = cmdEncoder->getCommandEncodingPool()->getTransferMVKImage(xferImageData); }

		if (expCnt) {
			// Expand the current content of the destination image to the temporary transfer image.
			MVKCmdBlitImage<N> expCmd;
			expCmd.setContent(cmdEncoder->_cmdBuffer,
							  (VkImage)_dstImage, _dstLayout, (VkImage)xfrImage, _dstLayout,
							  expCnt, expansionRegions, VK_FILTER_LINEAR);
			expCmd.encode(cmdEncoder, kMVKCommandUseResolveExpandImage);
		}

		// Copy the resolve regions of the source image to the temporary transfer image.
		MVKCmdCopyImage<N> copyCmd;
		copyCmd.setContent(cmdEncoder->_cmdBuffer,
						   (VkImage)_srcImage, _srcLayout,
						   (VkImage)xfrImage, _dstLayout,
						   copyCnt, copyRegions);
		copyCmd.encode(cmdEncoder, kMVKCommandUseResolveCopyImage);
	}

	cmdEncoder->endCurrentMetalEncoding();

	MTLRenderPassDescriptor* mtlRPD = [MTLRenderPassDescriptor renderPassDescriptor];
    MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPD.colorAttachments[0];
    mtlColorAttDesc.loadAction = MTLLoadActionLoad;
    mtlColorAttDesc.storeAction = MTLStoreActionMultisampleResolve;

	// For each resolve slice, update the render pass descriptor for
	// the texture level and slice and create a render encoder.
	for (uint32_t sIdx = 0; sIdx < sliceCnt; sIdx++) {
		MVKMetalResolveSlice& rslvSlice = mtlResolveSlices[sIdx];
        uint8_t srcPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(rslvSlice.srcSubresource.aspectMask);
        uint8_t dstPlaneIndex = MVKImage::getPlaneFromVkImageAspectFlags(rslvSlice.dstSubresource.aspectMask);

        mtlColorAttDesc.texture = xfrImage->getMTLTexture(srcPlaneIndex);
        mtlColorAttDesc.resolveTexture = _dstImage->getMTLTexture(dstPlaneIndex);
		mtlColorAttDesc.level = rslvSlice.srcSubresource.mipLevel;
		mtlColorAttDesc.slice = rslvSlice.srcSubresource.baseArrayLayer;
		mtlColorAttDesc.resolveLevel = rslvSlice.dstSubresource.mipLevel;
		mtlColorAttDesc.resolveSlice = rslvSlice.dstSubresource.baseArrayLayer;
		if (rslvSlice.dstSubresource.layerCount > 1) {
			mtlRPD.renderTargetArrayLength = rslvSlice.dstSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
				_dstImage->getLayerCount() - rslvSlice.dstSubresource.baseArrayLayer :
				rslvSlice.dstSubresource.layerCount;
		}
#if MVK_BUILD_METAL4_FOUNDATION
        if (cmdEncoder->isUsingMetal4()) {
            // vkCmdResolveImage preserves its multisample source for later use.
            mtlColorAttDesc.storeAction = MTLStoreActionStoreAndMultisampleResolve;
            if (!mvkEncodeMetal4ClearPass(cmdEncoder, mtlRPD, mvkMTLRenderCommandEncoderLabel(kMVKCommandUseResolveImage))) return;
            continue;
        }
#endif
		id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPD];
		cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mvkMTLRenderCommandEncoderLabel(kMVKCommandUseResolveImage));

		[mtlRendEnc pushDebugGroup: @"vkCmdResolveImage"];
		[mtlRendEnc popDebugGroup];

		cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);
		cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

		[mtlRendEnc endEncoding];
	}
}

template class MVKCmdResolveImage<1>;
template class MVKCmdResolveImage<4>;


#pragma mark -
#pragma mark MVKCmdCopyBuffer

// Matches shader struct.
typedef struct {
	uint32_t srcOffset;
	uint32_t dstOffset;
	uint32_t size;
} MVKCmdCopyBufferInfo;

template <size_t N>
VkResult MVKCmdCopyBuffer<N>::setContent(MVKCommandBuffer* cmdBuff,
										 VkBuffer srcBuffer,
										 VkBuffer destBuffer,
										 uint32_t regionCount,
										 const VkBufferCopy* pRegions) {
	_srcBuffer = (MVKBuffer*)srcBuffer;
	_dstBuffer = (MVKBuffer*)destBuffer;

	// Add buffer regions
	_bufferCopyRegions.clear();	// Clear for reuse
	_bufferCopyRegions.reserve(regionCount);
	for (uint32_t i = 0; i < regionCount; i++) {
        auto& region = pRegions[i];
        VkBufferCopy2 region2 = {
            VK_STRUCTURE_TYPE_BUFFER_COPY_2, nullptr,
            region.srcOffset, region.dstOffset, region.size,
        };
		_bufferCopyRegions.emplace_back(std::move(region2));
	}

	return VK_SUCCESS;
}

template <size_t N>
VkResult MVKCmdCopyBuffer<N>::setContent(MVKCommandBuffer* cmdBuff,
                                         const VkCopyBufferInfo2* pCopyBufferInfo) {
    _srcBuffer = (MVKBuffer*)pCopyBufferInfo->srcBuffer;
    _dstBuffer = (MVKBuffer*)pCopyBufferInfo->dstBuffer;

    // Add buffer regions
    _bufferCopyRegions.clear();    // Clear for reuse
    _bufferCopyRegions.reserve(pCopyBufferInfo->regionCount);
    for (uint32_t i = 0; i < pCopyBufferInfo->regionCount; i++) {
        _bufferCopyRegions.push_back(pCopyBufferInfo->pRegions[i]);
    }

    return VK_SUCCESS;
}

template <size_t N>
void MVKCmdCopyBuffer<N>::encode(MVKCommandEncoder* cmdEncoder) {
	id<MTLBuffer> srcMTLBuff = _srcBuffer->getMTLBuffer();
	NSUInteger srcMTLBuffOffset = _srcBuffer->getMTLBufferOffset();

	id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
	NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset();

	VkDeviceSize buffAlign = cmdEncoder->getMetalFeatures().mtlCopyBufferAlignment;

#if MVK_BUILD_METAL4_FOUNDATION
    if (cmdEncoder->isUsingMetal4()) {
        if (!mvkMetal4TransferResource(cmdEncoder, srcMTLBuff) || !mvkMetal4TransferResource(cmdEncoder, dstMTLBuff)) return;
        // A single Vulkan copy can contain independent regions. Prove actual
        // allocation/range disjointness before sharing its entry dependency;
        // imported/unknown aliases and large region sets keep the old barriers.
        auto* srcMemory = _srcBuffer->getDeviceMemory();
        auto* dstMemory = _dstBuffer->getDeviceMemory();
        bool independent = _bufferCopyRegions.size() > 1 && _bufferCopyRegions.size() <= 128 &&
            srcMemory && dstMemory && srcMemory->isMetal4KnownInternalAllocation() && dstMemory->isMetal4KnownInternalAllocation();
        const auto srcBase = _srcBuffer->getDeviceMemoryOffset(), dstBase = _dstBuffer->getDeviceMemoryOffset();
        auto overlaps = [](VkDeviceSize a, VkDeviceSize aSize, VkDeviceSize b, VkDeviceSize bSize) {
            return a < b ? aSize > b - a : bSize > a - b;
        };
        for (size_t i = 0; independent && i < _bufferCopyRegions.size(); ++i) {
            const auto& a = _bufferCopyRegions[i];
            // Preserve the compute byte-copy helper's conservative sequencing.
            independent = (!buffAlign || !(a.srcOffset % buffAlign || a.dstOffset % buffAlign || a.size % buffAlign)) &&
                a.srcOffset <= UINT64_MAX - srcBase && a.dstOffset <= UINT64_MAX - dstBase &&
                a.size <= UINT64_MAX - (srcBase + a.srcOffset) && a.size <= UINT64_MAX - (dstBase + a.dstOffset);
            for (size_t j = 0; independent && j < _bufferCopyRegions.size(); ++j) {
                const auto& b = _bufferCopyRegions[j];
                independent = b.srcOffset <= UINT64_MAX - srcBase &&
                    (i == j || !overlaps(a.dstOffset, a.size, b.dstOffset, b.size)) &&
                    (srcMemory != dstMemory || !overlaps(dstBase + a.dstOffset, a.size, srcBase + b.srcOffset, b.size));
            }
        }
        id<MTL4ComputeCommandEncoder> sharedCopy = independent
            ? cmdEncoder->getMetal4ComputeEncoder(kMVKCommandUseCopyBuffer, false, false, MTLStageBlit) : nil;
        if (independent && !sharedCopy) return;
        if (independent) {
            if (auto* stats = cmdEncoder->getMetal4EncodingStats()) { stats->independentCopyRegions += _bufferCopyRegions.size(); }
        }
        for (const auto& region : _bufferCopyRegions) {
            const bool byteCopy = buffAlign > 1 &&
                (region.srcOffset % buffAlign || region.dstOffset % buffAlign || region.size % buffAlign);
            id<MTL4ComputeCommandEncoder> copy = independent ? sharedCopy
                : cmdEncoder->getMetal4ComputeEncoder(kMVKCommandUseCopyBuffer, false, false,
                                                     byteCopy ? MTLStageDispatch : MTLStageBlit);
            if (!copy) return;
            if (byteCopy) {
                if (!mvkFits<uint32_t>(region.srcOffset) || !mvkFits<uint32_t>(region.dstOffset) || !mvkFits<uint32_t>(region.size)) {
                    cmdEncoder->failMetal4Encoding("Metal 4 byte copy requires 32-bit helper offsets and size."); return;
                }
                MVKCmdCopyBufferInfo info;
                info.srcOffset = uint32_t(region.srcOffset);
                info.dstOffset = uint32_t(region.dstOffset);
                info.size = uint32_t(region.size);
                NSError* error = nil;
                id<MTLBuffer> constants = cmdEncoder->getMetal4Submission()->uploadBytes(&info, sizeof(info), &error);
                if (!constants) { cmdEncoder->failMetal4Encoding("Could not upload Metal 4 byte copy parameters."); return; }
                if (!mvkBindMetal4Transfer(cmdEncoder, copy,
                        cmdEncoder->getCommandEncodingPool()->getCmdCopyBufferBytesMTLComputePipelineState(),
                        {{srcMTLBuff, srcMTLBuffOffset}, {dstMTLBuff, dstMTLBuffOffset}, {constants, 0}})) return;
                [copy dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
            } else {
                [copy copyFromBuffer:srcMTLBuff sourceOffset:srcMTLBuffOffset + region.srcOffset
                           toBuffer:dstMTLBuff destinationOffset:dstMTLBuffOffset + region.dstOffset size:region.size];
            }
        }
        return;
    }
#endif

	for (const auto& cpyRgn : _bufferCopyRegions) {
		const bool useComputeCopy = buffAlign > 1 && (cpyRgn.srcOffset % buffAlign != 0 ||
													  cpyRgn.dstOffset % buffAlign != 0 ||
													  cpyRgn.size      % buffAlign != 0);
		if (useComputeCopy) {
			MVKAssert(mvkFits<uint32_t>(cpyRgn.srcOffset) && mvkFits<uint32_t>(cpyRgn.dstOffset) && mvkFits<uint32_t>(cpyRgn.size),
					  "Byte-aligned buffer copy region offsets and size must each fit into a 32-bit unsigned integer.");

			MVKCmdCopyBufferInfo copyInfo;
			copyInfo.srcOffset = (uint32_t)cpyRgn.srcOffset;
			copyInfo.dstOffset = (uint32_t)cpyRgn.dstOffset;
			copyInfo.size = (uint32_t)cpyRgn.size;

			id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseCopyBuffer);
			MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
			[mtlComputeEnc pushDebugGroup: @"vkCmdCopyBuffer"];
			state.bindPipeline(mtlComputeEnc, cmdEncoder->getCommandEncodingPool()->getCmdCopyBufferBytesMTLComputePipelineState());
			state.bindBuffer(mtlComputeEnc, srcMTLBuff, srcMTLBuffOffset, 0);
			state.bindBuffer(mtlComputeEnc, dstMTLBuff, dstMTLBuffOffset, 1);
			state.bindStructBytes(mtlComputeEnc, &copyInfo, 2);
			[mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
			[mtlComputeEnc popDebugGroup];
		} else {
			id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseCopyBuffer);
			[mtlBlitEnc copyFromBuffer: srcMTLBuff
						  sourceOffset: (srcMTLBuffOffset + cpyRgn.srcOffset)
							  toBuffer: dstMTLBuff
					 destinationOffset: (dstMTLBuffOffset + cpyRgn.dstOffset)
								  size: cpyRgn.size];
		}
	}
}

#if MVK_BUILD_METAL4_FOUNDATION
template <size_t N>
MVKMetal4RecordPolicy MVKCmdCopyBuffer<N>::getMetal4RecordPolicy() const {
	auto* src = _srcBuffer ? _srcBuffer->getDeviceMemory() : nullptr;
	auto* dst = _dstBuffer ? _dstBuffer->getDeviceMemory() : nullptr;
	return src && dst && src->isMetal4KnownInternalAllocation() && dst->isMetal4KnownInternalAllocation()
		? MVKMetal4RecordPolicy::Immediate : MVKMetal4RecordPolicy::Deferred;
}
#endif

template class MVKCmdCopyBuffer<1>;
template class MVKCmdCopyBuffer<4>;


#pragma mark -
#pragma mark MVKCmdBufferImageCopy

template <size_t N>
VkResult MVKCmdBufferImageCopy<N>::setContent(MVKCommandBuffer* cmdBuff,
											  VkBuffer buffer,
											  VkImage image,
											  VkImageLayout imageLayout,
											  uint32_t regionCount,
											  const VkBufferImageCopy* pRegions,
											  bool toImage) {
    _buffer = (MVKBuffer*)buffer;
    _image = (MVKImage*)image;
    _toImage = toImage;

    // Add buffer regions
    _bufferImageCopyRegions.clear();     // Clear for reuse
    _bufferImageCopyRegions.reserve(regionCount);
    for (uint32_t i = 0; i < regionCount; i++) {
        const auto& region = pRegions[i];
        VkBufferImageCopy2 region2 = {
            VK_STRUCTURE_TYPE_BUFFER_IMAGE_COPY_2, nullptr,
            region.bufferOffset, region.bufferRowLength, region.bufferImageHeight,
            region.imageSubresource, region.imageOffset, region.imageExtent,
        };
        _bufferImageCopyRegions.emplace_back(std::move(region2));
    }

	return validate(cmdBuff);
}

template <size_t N>
VkResult MVKCmdBufferImageCopy<N>::setContent(MVKCommandBuffer* cmdBuff,
                                              const VkCopyBufferToImageInfo2* pCopyBufferToImageInfo) {
    _buffer = (MVKBuffer*)pCopyBufferToImageInfo->srcBuffer;
    _image = (MVKImage*)pCopyBufferToImageInfo->dstImage;
    _toImage = true;
    
    _bufferImageCopyRegions.clear();     // Clear for reuse
    _bufferImageCopyRegions.resize(pCopyBufferToImageInfo->regionCount);
    std::memcpy(_bufferImageCopyRegions.data(), pCopyBufferToImageInfo->pRegions, pCopyBufferToImageInfo->regionCount * sizeof(VkBufferImageCopy2));
    return validate(cmdBuff);
}

template <size_t N>
VkResult MVKCmdBufferImageCopy<N>::setContent(MVKCommandBuffer* cmdBuff,
                                              const VkCopyImageToBufferInfo2* pCopyImageToBufferInfo) {
    _buffer = (MVKBuffer*)pCopyImageToBufferInfo->dstBuffer;
    _image = (MVKImage*)pCopyImageToBufferInfo->srcImage;
    _toImage = false;
    
    _bufferImageCopyRegions.clear();     // Clear for reuse
    _bufferImageCopyRegions.resize(pCopyImageToBufferInfo->regionCount);
    std::memcpy(_bufferImageCopyRegions.data(), pCopyImageToBufferInfo->pRegions, pCopyImageToBufferInfo->regionCount * sizeof(VkBufferImageCopy2));
    return validate(cmdBuff);
}

template <size_t N>
inline VkResult MVKCmdBufferImageCopy<N>::validate(MVKCommandBuffer *cmdBuff) {
    for (auto& region : _bufferImageCopyRegions) {
        if (!_image->hasExpectedTexelSize()) {
            MTLPixelFormat mtlPixFmt = _image->getMTLPixelFormat(MVKImage::getPlaneFromVkImageAspectFlags(region.imageSubresource.aspectMask));
            const char* cmdName = _toImage ? "vkCmdCopyBufferToImage" : "vkCmdCopyImageToBuffer";
            return cmdBuff->reportError(VK_ERROR_FORMAT_NOT_SUPPORTED, "%s(): The image is using Metal format %s as a substitute for Vulkan format %s. Since the pixel size is different, content for the image cannot be copied to or from a buffer.", cmdName, cmdBuff->getPixelFormats()->getName(mtlPixFmt), cmdBuff->getPixelFormats()->getName(_image->getVkFormat()));
        }
    }
    return VK_SUCCESS;
}
    
template <size_t N>
void MVKCmdBufferImageCopy<N>::encode(MVKCommandEncoder* cmdEncoder) {
    id<MTLBuffer> mtlBuffer = _buffer->getMTLBuffer();
    if ( !mtlBuffer ) { return; }

	NSUInteger mtlBuffOffsetBase = _buffer->getMTLBufferOffset();
    MVKCommandUse cmdUse = _toImage ? kMVKCommandUseCopyBufferToImage : kMVKCommandUseCopyImageToBuffer;
	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();

    for (auto& cpyRgn : _bufferImageCopyRegions) {
        uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(cpyRgn.imageSubresource.aspectMask);
        MTLPixelFormat mtlPixFmt = _image->getMTLPixelFormat(planeIndex);
        id<MTLTexture> mtlTexture = _image->getMTLTexture(planeIndex);
        if ( !mtlTexture ) { continue; }

		uint32_t mipLevel = cpyRgn.imageSubresource.mipLevel;
        MTLOrigin mtlTxtOrigin = mvkMTLOriginFromVkOffset3D(cpyRgn.imageOffset);
		MTLSize mtlTxtSize = mvkClampMTLSize(mvkMTLSizeFromVkExtent3D(cpyRgn.imageExtent),
											 mtlTxtOrigin,
											 mvkMTLSizeFromVkExtent3D(_image->getExtent3D(planeIndex, mipLevel)));
		NSUInteger mtlBuffOffset = mtlBuffOffsetBase + cpyRgn.bufferOffset;

        uint32_t buffImgWd = cpyRgn.bufferRowLength;
        if (buffImgWd == 0) { buffImgWd = cpyRgn.imageExtent.width; }

        uint32_t buffImgHt = cpyRgn.bufferImageHeight;
        if (buffImgHt == 0) { buffImgHt = cpyRgn.imageExtent.height; }

        NSUInteger bytesPerRow = pixFmts->getBytesPerRow(mtlPixFmt, buffImgWd);
        NSUInteger bytesPerImg = pixFmts->getBytesPerLayer(mtlPixFmt, bytesPerRow, buffImgHt);

        // If the format combines BOTH depth and stencil, determine whether one or both
        // components are to be copied, and adjust the byte counts and copy options accordingly.
        MTLBlitOption blitOptions = MTLBlitOptionNone;
        if (pixFmts->isDepthFormat(mtlPixFmt) && pixFmts->isStencilFormat(mtlPixFmt)) {

            VkImageAspectFlags imgFlags = cpyRgn.imageSubresource.aspectMask;
            bool wantDepth = mvkAreAllFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_DEPTH_BIT);
            bool wantStencil = mvkAreAllFlagsEnabled(imgFlags, VK_IMAGE_ASPECT_STENCIL_BIT);

            // The stencil component is always 1 byte per pixel.
			// Don't reduce depths of 32-bit depth/stencil formats.
            if (wantDepth && !wantStencil) {
				if (pixFmts->getBytesPerTexel(mtlPixFmt) != 4) {
					bytesPerRow -= buffImgWd;
					bytesPerImg -= buffImgWd * buffImgHt;
				}
                blitOptions |= MTLBlitOptionDepthFromDepthStencil;
            } else if (wantStencil && !wantDepth) {
                bytesPerRow = buffImgWd;
                bytesPerImg = buffImgWd * buffImgHt;
                blitOptions |= MTLBlitOptionStencilFromDepthStencil;
            }
        }

		if (pixFmts->isPVRTCFormat(mtlPixFmt)) {
			blitOptions |= MTLBlitOptionRowLinearPVRTC;
		}

		// Don't supply bytes per image if not an arrayed texture
		if ( !isArrayTexture() ) { bytesPerImg = 0; }

#if MVK_BUILD_METAL4_FOUNDATION
        if (cmdEncoder->isUsingMetal4()) {
            if (!mvkMetal4TransferResource(cmdEncoder, mtlBuffer) || !mvkMetal4TransferResource(cmdEncoder, mtlTexture)) return;
            id<MTL4ComputeCommandEncoder> copy = cmdEncoder->getMetal4ComputeEncoder(cmdUse, false, false, MTLStageBlit);
            if (!copy) return;
            uint32_t layers = cpyRgn.imageSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS
                ? _image->getLayerCount() - cpyRgn.imageSubresource.baseArrayLayer : cpyRgn.imageSubresource.layerCount;
            for (uint32_t layer = 0; layer < layers; ++layer) {
                if (_toImage) {
                    [copy copyFromBuffer:mtlBuffer sourceOffset:mtlBuffOffset + bytesPerImg * layer
                       sourceBytesPerRow:bytesPerRow sourceBytesPerImage:bytesPerImg sourceSize:mtlTxtSize
                               toTexture:mtlTexture destinationSlice:cpyRgn.imageSubresource.baseArrayLayer + layer
                        destinationLevel:mipLevel destinationOrigin:mtlTxtOrigin options:blitOptions];
                } else {
                    [copy copyFromTexture:mtlTexture sourceSlice:cpyRgn.imageSubresource.baseArrayLayer + layer
                              sourceLevel:mipLevel sourceOrigin:mtlTxtOrigin sourceSize:mtlTxtSize
                                 toBuffer:mtlBuffer destinationOffset:mtlBuffOffset + bytesPerImg * layer
                      destinationBytesPerRow:bytesPerRow destinationBytesPerImage:bytesPerImg options:blitOptions];
                }
            }
            continue;
        }
#endif
        id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(cmdUse);

        uint32_t layCnt = cpyRgn.imageSubresource.layerCount == VK_REMAINING_ARRAY_LAYERS ?
            _image->getLayerCount() - cpyRgn.imageSubresource.baseArrayLayer :
            cpyRgn.imageSubresource.layerCount;
        for (uint32_t lyrIdx = 0; lyrIdx < layCnt; lyrIdx++) {
            if (_toImage) {
                [mtlBlitEnc copyFromBuffer: mtlBuffer
                              sourceOffset: (mtlBuffOffset + (bytesPerImg * lyrIdx))
                         sourceBytesPerRow: bytesPerRow
                       sourceBytesPerImage: bytesPerImg
                                sourceSize: mtlTxtSize
                                 toTexture: mtlTexture
                          destinationSlice: (cpyRgn.imageSubresource.baseArrayLayer + lyrIdx)
                          destinationLevel: mipLevel
                         destinationOrigin: mtlTxtOrigin
                                   options: blitOptions];
            } else {
                [mtlBlitEnc copyFromTexture: mtlTexture
                                sourceSlice: (cpyRgn.imageSubresource.baseArrayLayer + lyrIdx)
                                sourceLevel: mipLevel
                               sourceOrigin: mtlTxtOrigin
                                 sourceSize: mtlTxtSize
                                   toBuffer: mtlBuffer
                          destinationOffset: (mtlBuffOffset + (bytesPerImg * lyrIdx))
                     destinationBytesPerRow: bytesPerRow
                   destinationBytesPerImage: bytesPerImg
                                    options: blitOptions];
            }
        }
    }
}

template <size_t N>
bool MVKCmdBufferImageCopy<N>::isArrayTexture() {
	MTLTextureType mtlTexType = _image->getMTLTextureType();
	return (mtlTexType == MTLTextureType3D ||
			mtlTexType == MTLTextureType2DArray ||
			mtlTexType == MTLTextureType2DMultisampleArray ||
			mtlTexType == MTLTextureType1DArray);
}

template class MVKCmdBufferImageCopy<1>;
template class MVKCmdBufferImageCopy<4>;	// To support MVKCmdCopyImage
template class MVKCmdBufferImageCopy<8>;
template class MVKCmdBufferImageCopy<16>;


#pragma mark -
#pragma mark MVKCmdClearAttachments

template <size_t N>
VkResult MVKCmdClearAttachments<N>::setContent(MVKCommandBuffer* cmdBuff,
											   uint32_t attachmentCount,
											   const VkClearAttachment* pAttachments,
											   uint32_t rectCount,
											   const VkClearRect* pRects,
											   MVKCommandUse cmdUse) {
	_commandUse = cmdUse;
	_clearDepthStencilValue = {};
	mvkClear(_shouldClearAtt, kMVKClearAttachmentCount);

    for (uint32_t i = 0; i < attachmentCount; i++) {
        auto& clrAtt = pAttachments[i];
        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_COLOR_BIT)) {
			uint32_t rpAttIdx = clrAtt.colorAttachment;
            if (rpAttIdx != VK_ATTACHMENT_UNUSED) {
                setClearColorValue(rpAttIdx, clrAtt.clearValue.color);
				_shouldClearAtt[rpAttIdx] = true;
            }
        }
        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT)) {
			_clearDepthStencilValue.depth = clrAtt.clearValue.depthStencil.depth;
			_shouldClearAtt[kMVKClearAttachmentDepthIndex] = true;
        }
        if (mvkIsAnyFlagEnabled(clrAtt.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT)) {
			_clearDepthStencilValue.stencil = clrAtt.clearValue.depthStencil.stencil;
			_shouldClearAtt[kMVKClearAttachmentStencilIndex] = true;
        }
    }

    _clearRects.clear();		// Clear for reuse
    _clearRects.reserve(rectCount);
    for (uint32_t i = 0; i < rectCount; i++) {
        _clearRects.push_back(pRects[i]);
    }

	return VK_SUCCESS;
}

// Returns the total number of vertices needed to clear all layers of all rectangles.
template <size_t N>
uint32_t MVKCmdClearAttachments<N>::getVertexCount(MVKCommandEncoder* cmdEncoder) {
	uint32_t vtxCnt = 0;
	if (cmdEncoder->getSubpass()->isMultiview()) {
		// In this case, all the layer counts will be one. We want to use the number of views in the current multiview pass.
		vtxCnt = (uint32_t)_clearRects.size() * cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex()) * 6;
	} else {
		for (auto& rect : _clearRects) {
			vtxCnt += 6 * rect.layerCount;
		}
	}
	return vtxCnt;
}

// Populates the vertices for all clear rectangles within an attachment of the specified size.
template <size_t N>
void MVKCmdClearAttachments<N>::populateVertices(MVKCommandEncoder* cmdEncoder, simd::float4* vertices,
												 float attWidth, float attHeight) {
	uint32_t vtxIdx = 0;
    for (auto& rect : _clearRects) {
		vtxIdx = populateVertices(cmdEncoder, vertices, vtxIdx, rect, attWidth, attHeight);
	}
}

// Populates the vertices, starting at the vertex, from the specified rectangle within
// an attachment of the specified size. Returns the next vertex that needs to be populated.
template <size_t N>
uint32_t MVKCmdClearAttachments<N>::populateVertices(MVKCommandEncoder* cmdEncoder,
													 simd::float4* vertices,
													 uint32_t startVertex,
													 VkClearRect& clearRect,
													 float attWidth,
													 float attHeight) {
	// Determine the positions of the four edges of the
    // clear rectangle as a fraction of the attachment size.
    float leftPos = (float)(clearRect.rect.offset.x) / attWidth;
    float rightPos = (float)(clearRect.rect.extent.width) / attWidth + leftPos;
    float bottomPos = (float)(clearRect.rect.offset.y) / attHeight;
    float topPos = (float)(clearRect.rect.extent.height) / attHeight + bottomPos;

    // Now transform to clip-space coordinates,
    // which are bounded by (-1.0 < p < 1.0) in clip-space.
    leftPos = (leftPos * 2.0) - 1.0;
    rightPos = (rightPos * 2.0) - 1.0;
    bottomPos = (bottomPos * 2.0) - 1.0;
    topPos = (topPos * 2.0) - 1.0;

    simd::float4 vtx;

	uint32_t vtxIdx = startVertex;
	uint32_t startLayer, endLayer;
	if (cmdEncoder->getSubpass()->isMultiview()) {
		// In a multiview pass, the baseArrayLayer will be 0 and the layerCount will be 1.
		// Use the view count instead. We already set the base slice properly in the
		// MTLRenderPassDescriptor, so we don't need to offset the starting layer.
		startLayer = 0;
		endLayer = cmdEncoder->getSubpass()->getViewCountInMetalPass(cmdEncoder->getMultiviewPassIndex());
	} else {
		startLayer = clearRect.baseArrayLayer;
		endLayer = startLayer + clearRect.layerCount;
	}
	for (uint32_t layer = startLayer; layer < endLayer; layer++) {

		vtx.z = 0.0;
		vtx.w = layer;

		// Top left vertex	- First triangle
		vtx.y = topPos;
		vtx.x = leftPos;
		vertices[vtxIdx++] = vtx;

		// Bottom left vertex
		vtx.y = bottomPos;
		vtx.x = leftPos;
		vertices[vtxIdx++] = vtx;

		// Bottom right vertex
		vtx.y = bottomPos;
		vtx.x = rightPos;
		vertices[vtxIdx++] = vtx;

		// Bottom right vertex	- Second triangle
		vertices[vtxIdx++] = vtx;

		// Top right vertex
		vtx.y = topPos;
		vtx.x = rightPos;
		vertices[vtxIdx++] = vtx;

		// Top left vertex
		vtx.y = topPos;
		vtx.x = leftPos;
		vertices[vtxIdx++] = vtx;
	}

	return vtxIdx;
}

template <size_t N>
void MVKCmdClearAttachments<N>::encode(MVKCommandEncoder* cmdEncoder) {

	uint32_t vtxCnt = getVertexCount(cmdEncoder);
	simd::float4 vertices[vtxCnt];
	simd::float4 clearColors[kMVKClearAttachmentCount];
	MVKRPSKeyClearAtt rpsKey;

	VkRect2D renderArea = cmdEncoder->clipToRenderArea({{0, 0}, cmdEncoder->getFramebufferExtent()});
	VkExtent2D fbExtent = {renderArea.offset.x + renderArea.extent.width, renderArea.offset.y + renderArea.extent.height};

	populateVertices(cmdEncoder, vertices, fbExtent.width, fbExtent.height);

	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
    MVKRenderSubpass* subpass = cmdEncoder->getSubpass();

    // Populate the render pipeline state attachment key with info from the subpass and framebuffer.
	rpsKey.mtlSampleCount = mvkSampleCountFromVkSampleCountFlagBits(subpass->getSampleCount());
	if (cmdEncoder->_canUseLayeredRendering &&
		(cmdEncoder->getFramebufferLayerCount() > 1 || cmdEncoder->getSubpass()->isMultiview())) {
		rpsKey.enableLayeredRendering();
	}

    uint32_t caCnt = subpass->getColorAttachmentCount();
    for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
		VkFormat vkAttFmt = subpass->getColorAttachmentFormat(caIdx);
		rpsKey.attachmentMTLPixelFormats[caIdx] = pixFmts->getMTLPixelFormat(vkAttFmt);
		uint32_t rpAttIdx = subpass->getClearColorAttachmentIndex(caIdx);
        if (rpAttIdx != VK_ATTACHMENT_UNUSED && _shouldClearAtt[rpAttIdx]) {
			rpsKey.enableAttachment(caIdx);
			MTLClearColor mtlCC = pixFmts->getMTLClearColor(getClearColorValue(rpAttIdx), vkAttFmt);
			clearColors[caIdx] = { (float)mtlCC.red, (float)mtlCC.green, (float)mtlCC.blue, (float)mtlCC.alpha};
        }
    }

	// The depth value is the vertex position Z value.
	auto clrDepthVal = _clearDepthStencilValue.depth;
	clearColors[kMVKClearAttachmentDepthIndex] = { clrDepthVal, clrDepthVal, clrDepthVal, clrDepthVal };
	rpsKey.attachmentMTLPixelFormats[kMVKClearAttachmentDepthIndex] = pixFmts->getMTLPixelFormat(subpass->getDepthFormat());
	rpsKey.attachmentMTLPixelFormats[kMVKClearAttachmentStencilIndex] = pixFmts->getMTLPixelFormat(subpass->getStencilFormat());

	if (subpass->isDepthAttachmentUsed() && _shouldClearAtt[kMVKClearAttachmentDepthIndex]) {
		rpsKey.enableAttachment(kMVKClearAttachmentDepthIndex);
	}
	if (subpass->isStencilAttachmentUsed() && _shouldClearAtt[kMVKClearAttachmentStencilIndex]) {
		rpsKey.enableAttachment(kMVKClearAttachmentStencilIndex);
	}

	if ( !rpsKey.isAnyAttachmentEnabled() ) { return; }		// Nothing to clear

    // Render the clear colors to the attachments
	cmdEncoder->restartMetalRenderPassIfNeeded();
	MVKCommandEncodingPool* cmdEncPool = cmdEncoder->getCommandEncodingPool();

#if MVK_BUILD_METAL4_FOUNDATION
    if (cmdEncoder->isUsingMetal4()) {
        if (!vtxCnt) return;
        if (!cmdEncoder->_occlusionQueryState.prepareMetal4HelperDraw(cmdEncoder)) return;
        auto* submission = cmdEncoder->getMetal4Submission();
        id<MTL4RenderCommandEncoder> render = cmdEncoder->getMetal4RenderEncoder();
        id<MTLRenderPipelineState> pipeline = cmdEncPool->getCmdClearMTLRenderPipelineState(rpsKey);
        id<MTLDepthStencilState> depth = cmdEncPool->getMTLDepthStencilState(
            rpsKey.isAttachmentUsed(kMVKClearAttachmentDepthIndex), rpsKey.isAttachmentUsed(kMVKClearAttachmentStencilIndex));
        NSError* error = nil;
        id<MTLBuffer> colors = submission->uploadBytes(clearColors, sizeof(clearColors), &error);
        id<MTLBuffer> positions = submission->uploadBytes(vertices, vtxCnt * sizeof(vertices[0]), &error);
        MVKMetal4ArgumentTables tables;
        using Stage = MVKMetal4ArgumentTables::Stage;
        bool valid = render && pipeline && depth && colors && positions &&
            submission->retainObject(pipeline, &error) && submission->retainObject(depth, &error) &&
            tables.initialize(cmdEncoder->getMTLDevice(), {31, 0, 0}, &error) &&
            tables.setBuffer(Stage::Vertex, colors, 0, 0, &error) && tables.setBuffer(Stage::Fragment, colors, 0, 0, &error) &&
            tables.setBuffer(Stage::Vertex, positions, 0,
                cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex), &error) &&
            submission->retainObject(tables.getTable(Stage::Vertex), &error) &&
            submission->retainObject(tables.getTable(Stage::Fragment), &error) &&
            tables.bindRender(render, MTLRenderStageVertex | MTLRenderStageFragment, &error);
        if (!valid) { cmdEncoder->failMetal4Encoding("Could not bind native attachment clear helper."); return; }
        [render setRenderPipelineState:pipeline];
        [render setCullMode:MTLCullModeNone];
        [render setDepthBias:0 slopeScale:0 clamp:0];
        [render setDepthClipMode:MTLDepthClipModeClip];
        if (cmdEncoder->getMetalFeatures().depthBoundsTest) [render setDepthTestMinBound:0 maxBound:1];
        [render setTriangleFillMode:MTLTriangleFillModeFill];
        [render setDepthStencilState:depth];
        [render setStencilReferenceValue:_clearDepthStencilValue.stencil];
        [render setVertexAmplificationCount:1 viewMappings:nullptr];
        [render setScissorRect:MTLScissorRect{0, 0, fbExtent.width, fbExtent.height}];
        [render setViewport:MTLViewport{0, 0, double(fbExtent.width), double(fbExtent.height), 0, 1}];
        [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vtxCnt];
        // Restore every helper-mutated state and root binding on the next draw
        // without discarding the current tile contents or resolving MSAA early.
        cmdEncoder->getState().invalidateMetal4GraphicsAfterHelper();
        if (auto* stats = cmdEncoder->getMetal4EncodingStats()) { ++stats->clearHelperRestores; }
        // This separate tile dependency is not a state-cache restoration cost.
        // Preserve clear->input-attachment visibility, including depth/stencil.
        if (cmdEncoder->getMetalFeatures().tileBasedDeferredRendering) {
            bool inputWasCleared = subpass->isInputAttachmentDepthStencilAttachment() &&
                (rpsKey.isAttachmentEnabled(kMVKClearAttachmentDepthIndex) || rpsKey.isAttachmentEnabled(kMVKClearAttachmentStencilIndex));
            for (uint32_t caIdx = 0; caIdx < caCnt; ++caIdx) {
                inputWasCleared |= rpsKey.isAttachmentEnabled(caIdx) && subpass->isColorAttachmentAlsoInputAttachment(caIdx);
            }
            if (inputWasCleared) {
                cmdEncoder->encodeStoreActions(true);
                cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
            }
        }
        return;
    }
#endif

	cmdEncoder->_occlusionQueryState.prepareHelperDraw(cmdEncoder);
	id<MTLRenderCommandEncoder> mtlRendEnc = cmdEncoder->_mtlRenderEncoder;
	if (!mtlRendEnc) { return; }

	[mtlRendEnc pushDebugGroup: getMTLDebugGroupLabel()];
	MVKHelperDrawState state = {};
	state.pipeline           = cmdEncPool->getCmdClearMTLRenderPipelineState(rpsKey);
	state.viewportAndScissor = { {}, fbExtent };
	state.stencilReference   = _clearDepthStencilValue.stencil;
	state.writeDepth         = rpsKey.isAttachmentUsed(kMVKClearAttachmentDepthIndex);
	state.writeStencil       = rpsKey.isAttachmentUsed(kMVKClearAttachmentStencilIndex);
	cmdEncoder->getMtlGraphics().prepareHelperDraw(mtlRendEnc, *cmdEncoder, state);
	cmdEncoder->setVertexBytes(mtlRendEnc, clearColors, sizeof(clearColors), 0);
	cmdEncoder->setFragmentBytes(mtlRendEnc, clearColors, sizeof(clearColors), 0);
	cmdEncoder->setVertexBytes(mtlRendEnc, vertices, vtxCnt * sizeof(vertices[0]),
	                           cmdEncoder->getDevice()->getMetalBufferIndexForVertexAttributeBinding(kMVKVertexContentBufferIndex));
    [mtlRendEnc drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: vtxCnt];
    [mtlRendEnc popDebugGroup];

	// Apple GPUs do not support rendering/writing to an attachment and then reading from
	// that attachment within a single Metal renderpass. So, if any of the attachments just
	// cleared is an input attachment, we need to restart into separate Metal renderpasses.
	if (cmdEncoder->getMetalFeatures().tileBasedDeferredRendering) {
		bool needsRenderpassRestart = false;
		for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
			if (rpsKey.isAttachmentEnabled(caIdx) && subpass->isColorAttachmentAlsoInputAttachment(caIdx)) {
				needsRenderpassRestart = true;
				break;
			}
		}
		if (needsRenderpassRestart) {
			cmdEncoder->encodeStoreActions(true);
			cmdEncoder->beginMetalRenderPass(kMVKCommandUseRestartSubpass);
		}
	}
}

template <size_t N>
NSString* MVKCmdClearAttachments<N>::getMTLDebugGroupLabel() {
	switch (_commandUse) {
		case kMVKCommandUseClearAttachments:    return @"vkCmdClearAttachments";
		case kMVKCommandUseBeginRenderPass:     return @"Clear Render Area on Begin Renderpass";
		case kMVKCommandUseBeginRendering:      return @"Clear Render Area on Begin Rendering";
		case kMVKCommandUseNextSubpass:         return @"Clear Render Area on Next Subpass";
		default:                                return @"Unknown Use Clear Attachments";
	}
}

template class MVKCmdClearAttachments<1>;
template class MVKCmdClearAttachments<4>;

template class MVKCmdClearSingleAttachment<1>;
template class MVKCmdClearSingleAttachment<4>;

template class MVKCmdClearMultiAttachments<1>;
template class MVKCmdClearMultiAttachments<4>;


#pragma mark -
#pragma mark MVKCmdClearImage

template <size_t N>
VkResult MVKCmdClearImage<N>::setContent(MVKCommandBuffer* cmdBuff,
										 VkImage image,
										 VkImageLayout imageLayout,
										 const VkClearValue& clearValue,
										 uint32_t rangeCount,
										 const VkImageSubresourceRange* pRanges) {
    _image = (MVKImage*)image;
	_clearValue = clearValue;

    // Add subresource ranges
    _subresourceRanges.clear();		// Clear for reuse
    _subresourceRanges.reserve(rangeCount);
    bool isDS = isDepthStencilClear();
    for (uint32_t rangeIdx = 0; rangeIdx < rangeCount; rangeIdx++) {
        auto& vkIR = pRanges[rangeIdx];
        uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(vkIR.aspectMask);

        // Validate
        MVKMTLFmtCaps mtlFmtCaps = cmdBuff->getPixelFormats()->getCapabilities(_image->getMTLPixelFormat(planeIndex));
		bool isDestUnwritableLinear = !cmdBuff->getMetalFeatures().renderLinearTextures && _image->getIsLinear();
		uint32_t reqCap = isDS ? kMVKMTLFmtCapsDSAtt : (isDestUnwritableLinear ? kMVKMTLFmtCapsWrite : kMVKMTLFmtCapsColorAtt);
        if (!mvkAreAllFlagsEnabled(mtlFmtCaps, reqCap)) {
            return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdClear%sImage(): Format %s cannot be cleared on this device.", (isDS ? "DepthStencil" : "Color"), cmdBuff->getPixelFormats()->getName(_image->getVkFormat()));
        }
        
        _subresourceRanges.push_back(vkIR);
    }
    
    // Validate
    if (_image->getImageType() == VK_IMAGE_TYPE_1D) {
        return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdClear%sImage(): Native 1D images cannot be cleared on this device. Consider enabling MVK_CONFIG_TEXTURE_1D_AS_2D.", (isDS ? "DepthStencil" : "Color"));
    }

	return VK_SUCCESS;
}

template <size_t N>
void MVKCmdClearImage<N>::encode(MVKCommandEncoder* cmdEncoder) {
	bool isDS = isDepthStencilClear();
	NSString* mtlRendEncName = (isDS
								? mvkMTLRenderCommandEncoderLabel(kMVKCommandUseClearDepthStencilImage)
								: mvkMTLRenderCommandEncoderLabel(kMVKCommandUseClearColorImage));

	cmdEncoder->endCurrentMetalEncoding();

	auto& mtlFeats = cmdEncoder->getMetalFeatures();
	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
	for (auto& srRange : _subresourceRanges) {
		uint8_t planeIndex = MVKImage::getPlaneFromVkImageAspectFlags(srRange.aspectMask);
        id<MTLTexture> imgMTLTex = _image->getMTLTexture(planeIndex);
        if ( !imgMTLTex ) { continue; }

        if (!mtlFeats.renderLinearTextures && _image->getIsLinear()) {
            // These images cannot be rendered. Instead, use a compute shader.
            // Luckily for us, linear images only have one mip and one array layer under Metal.
            assert( !isDS );
            const bool isTextureArray = _image->getLayerCount() != 1u;
            id<MTLComputePipelineState> mtlClearState = cmdEncoder->getCommandEncodingPool()->getCmdClearColorImageMTLComputePipelineState(pixFmts->getFormatType(_image->getVkFormat()), isTextureArray);
#if MVK_BUILD_METAL4_FOUNDATION
            if (cmdEncoder->isUsingMetal4()) {
                auto* submission = cmdEncoder->getMetal4Submission();
                NSError* error = nil;
                id<MTLBuffer> color = submission->uploadBytes(&_clearValue, sizeof(_clearValue), &error);
                id<MTL4ComputeCommandEncoder> compute = cmdEncoder->getMetal4ComputeEncoder(kMVKCommandUseClearColorImage, false, false, MTLStageDispatch);
                auto* tables = cmdEncoder->getMetal4ComputeHelperArgumentTables({1, 1, 0});
                using Stage = MVKMetal4ArgumentTables::Stage;
                bool valid = tables && color && compute && mtlClearState && submission->retainObject(mtlClearState, &error) &&
                    mvkMetal4TransferResource(cmdEncoder, imgMTLTex) &&
                    tables->setBuffer(Stage::Compute, color, 0, 0, &error) && tables->setTexture(Stage::Compute, imgMTLTex, 0, &error) &&
                    tables->bindCompute(compute, &error);
                if (!valid) { cmdEncoder->failMetal4Encoding("Could not bind native linear image clear helper."); return; }
                [compute setComputePipelineState:mtlClearState];
                MTLSize grid = mvkMTLSizeFromVkExtent3D(_image->getExtent3D());
                MTLSize group = MTLSizeMake(mtlClearState.threadExecutionWidth, 1, 1);
                if (mtlFeats.nonUniformThreadgroups) [compute dispatchThreads:grid threadsPerThreadgroup:group];
                else [compute dispatchThreadgroups:MTLSizeMake((grid.width + group.width - 1) / group.width, grid.height, grid.depth)
                            threadsPerThreadgroup:group];
                continue;
            }
#endif
            id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseClearColorImage);
            MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
            [mtlComputeEnc pushDebugGroup: @"vkCmdClearColorImage"];
            state.bindPipeline(mtlComputeEnc, mtlClearState);
            state.bindTexture(mtlComputeEnc, imgMTLTex, 0);
            state.bindStructBytes(mtlComputeEnc, &_clearValue, 0);
            MTLSize gridSize = mvkMTLSizeFromVkExtent3D(_image->getExtent3D());
            MTLSize tgSize = MTLSizeMake(mtlClearState.threadExecutionWidth, 1, 1);
            if (mtlFeats.nonUniformThreadgroups) {
                [mtlComputeEnc dispatchThreads: gridSize threadsPerThreadgroup: tgSize];
            } else {
                MTLSize tgCount = MTLSizeMake(gridSize.width / tgSize.width, gridSize.height, gridSize.depth);
                if (gridSize.width % tgSize.width) { tgCount.width += 1; }
                [mtlComputeEnc dispatchThreadgroups: tgCount threadsPerThreadgroup: tgSize];
            }
            [mtlComputeEnc popDebugGroup];
            continue;
        }

		MTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];
		MTLRenderPassColorAttachmentDescriptor* mtlRPCADesc = nil;
		MTLRenderPassDepthAttachmentDescriptor* mtlRPDADesc = nil;
		MTLRenderPassStencilAttachmentDescriptor* mtlRPSADesc = nil;

		bool isClearingColor = !isDS && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_COLOR_BIT);
		bool isClearingDepth = isDS && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_DEPTH_BIT);
		bool isClearingStencil = isDS && mvkIsAnyFlagEnabled(srRange.aspectMask, VK_IMAGE_ASPECT_STENCIL_BIT);

		if (isClearingColor) {
			mtlRPCADesc = mtlRPDesc.colorAttachments[0];
			mtlRPCADesc.texture = imgMTLTex;
			mtlRPCADesc.loadAction = MTLLoadActionClear;
			mtlRPCADesc.storeAction = MTLStoreActionStore;
			mtlRPCADesc.clearColor = pixFmts->getMTLClearColor(_clearValue.color, _image->getVkFormat());
		}

		if (isClearingDepth) {
			mtlRPDADesc = mtlRPDesc.depthAttachment;
			mtlRPDADesc.texture = imgMTLTex;
			mtlRPDADesc.loadAction = MTLLoadActionClear;
			mtlRPDADesc.storeAction = MTLStoreActionStore;
			mtlRPDADesc.clearDepth = pixFmts->getMTLClearDepthValue(_clearValue.depthStencil);
		}

		if (isClearingStencil) {
			mtlRPSADesc = mtlRPDesc.stencilAttachment;
			mtlRPSADesc.texture = imgMTLTex;
			mtlRPSADesc.loadAction = MTLLoadActionClear;
			mtlRPSADesc.storeAction = MTLStoreActionStore;
			mtlRPSADesc.clearStencil = pixFmts->getMTLClearStencilValue(_clearValue.depthStencil);
		}

        // Extract the mipmap levels that are to be updated
        uint32_t mipLvlStart = srRange.baseMipLevel;
        uint32_t mipLvlCnt = srRange.levelCount;
        uint32_t mipLvlEnd = (mipLvlCnt == VK_REMAINING_MIP_LEVELS
                              ? _image->getMipLevelCount()
                              : (mipLvlStart + mipLvlCnt));

        // Extract the cube or array layers (slices) that are to be updated
		bool is3D = _image->getMTLTextureType() == MTLTextureType3D;
        uint32_t layerStart = is3D ? 0 : srRange.baseArrayLayer;
        uint32_t layerCnt = srRange.layerCount;
        uint32_t layerEnd = (layerCnt == VK_REMAINING_ARRAY_LAYERS
                             ? _image->getLayerCount()
                             : (layerStart + layerCnt));

        // Iterate across mipmap levels and layers, and perform and empty render to clear each
        for (uint32_t mipLvl = mipLvlStart; mipLvl < mipLvlEnd; mipLvl++) {
			mtlRPCADesc.level = mipLvl;
			mtlRPDADesc.level = mipLvl;
			mtlRPSADesc.level = mipLvl;

			// If a 3D image, we need to get the depth for each level.
			if (is3D) {
				layerCnt = _image->getExtent3D(planeIndex, mipLvl).depth;
				layerEnd = layerStart + layerCnt;
			}

            // If we can do layered rendering, I can clear all the layers at once.
            if (mtlFeats.layeredRendering && (mtlFeats.multisampleLayeredRendering || _image->getSampleCount() == VK_SAMPLE_COUNT_1_BIT)) {
                if (is3D) {
                    mtlRPCADesc.depthPlane = layerStart;
                    mtlRPDADesc.depthPlane = layerStart;
                    mtlRPSADesc.depthPlane = layerStart;
                } else {
                    mtlRPCADesc.slice = layerStart;
                    mtlRPDADesc.slice = layerStart;
                    mtlRPSADesc.slice = layerStart;
                }
                mtlRPDesc.renderTargetArrayLength = (layerCnt == VK_REMAINING_ARRAY_LAYERS
                                                     ? (_image->getLayerCount() - layerStart)
                                                     : layerCnt);

#if MVK_BUILD_METAL4_FOUNDATION
                if (cmdEncoder->isUsingMetal4()) {
                    if (!mvkEncodeMetal4ClearPass(cmdEncoder, mtlRPDesc, mtlRendEncName)) return;
                    continue;
                }
#endif
                id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
				cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mtlRendEncName);

				cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);
				cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

                [mtlRendEnc endEncoding];
            } else {
                for (uint32_t layer = layerStart; layer < layerEnd; layer++) {
                    if (is3D) {
                        mtlRPCADesc.depthPlane = layer;
                        mtlRPDADesc.depthPlane = layer;
                        mtlRPSADesc.depthPlane = layer;
                    } else {
                        mtlRPCADesc.slice = layer;
                        mtlRPDADesc.slice = layer;
                        mtlRPSADesc.slice = layer;
                    }

#if MVK_BUILD_METAL4_FOUNDATION
                    if (cmdEncoder->isUsingMetal4()) {
                        if (!mvkEncodeMetal4ClearPass(cmdEncoder, mtlRPDesc, mtlRendEncName)) return;
                        continue;
                    }
#endif
                    id<MTLRenderCommandEncoder> mtlRendEnc = [cmdEncoder->_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
					cmdEncoder->_cmdBuffer->setMetalObjectLabel(mtlRendEnc, mtlRendEncName);

					cmdEncoder->barrierWait(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);
					cmdEncoder->barrierUpdate(kMVKBarrierStageCopy, mtlRendEnc, MTLRenderStageFragment);

					[mtlRendEnc endEncoding];
                }
            }
        }
    }
}

template class MVKCmdClearImage<1>;
template class MVKCmdClearImage<4>;

template class MVKCmdClearColorImage<1>;
template class MVKCmdClearColorImage<4>;

template class MVKCmdClearDepthStencilImage<1>;
template class MVKCmdClearDepthStencilImage<4>;


#pragma mark -
#pragma mark MVKCmdFillBuffer

VkResult MVKCmdFillBuffer::setContent(MVKCommandBuffer* cmdBuff,
									  VkBuffer dstBuffer,
									  VkDeviceSize dstOffset,
									  VkDeviceSize size,
									  uint32_t data) {
    _dstBuffer = (MVKBuffer*)dstBuffer;
    _dstOffset = dstOffset;
    _dataValue = data;

	// Round down in case of VK_WHOLE_SIZE on a buffer size which is not aligned to 4 bytes.
	VkDeviceSize byteCnt = (size == VK_WHOLE_SIZE) ? (_dstBuffer->getByteCount() - _dstOffset) : size;
	VkDeviceSize wdCnt = byteCnt >> 2;
	if (mvkFits<uint32_t>(wdCnt)) {
		_wordCount = (uint32_t)wdCnt;
	} else {
		_wordCount = std::numeric_limits<uint32_t>::max();
		return cmdBuff->reportError(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdFillBuffer(): Buffer fill size must fit into a 32-bit unsigned integer. Fill size %llu is too large.", wdCnt);
	}

	return VK_SUCCESS;
}

#if MVK_BUILD_METAL4_FOUNDATION
MVKMetal4RecordPolicy MVKCmdFillBuffer::getMetal4RecordPolicy() const {
	auto* memory = _dstBuffer ? _dstBuffer->getDeviceMemory() : nullptr;
	return memory && memory->isMetal4KnownInternalAllocation()
		? MVKMetal4RecordPolicy::Immediate : MVKMetal4RecordPolicy::Deferred;
}
#endif

void MVKCmdFillBuffer::encode(MVKCommandEncoder* cmdEncoder) {
	if (_wordCount == 0) { return; }

	id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
	NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset() + _dstOffset;

	// Determine the number of full threadgroups we can dispatch to cover the buffer content efficiently.
	// Some GPU's report different values for max threadgroup width between the pipeline state and device,
	// so conservatively use the minimum of these two reported values.
	id<MTLComputePipelineState> cps = cmdEncoder->getCommandEncodingPool()->getCmdFillBufferMTLComputePipelineState();
	NSUInteger tgWidth = std::min(cps.maxTotalThreadsPerThreadgroup, cmdEncoder->getMTLDevice().maxThreadsPerThreadgroup.width);
#if MVK_BUILD_METAL4_FOUNDATION
	if (cmdEncoder->isUsingMetal4() && (!cps || !tgWidth)) {
		cmdEncoder->failMetal4Encoding("Native fill pipeline or threadgroup width is unavailable.");
		return;
	}
#endif
	NSUInteger tgCount = _wordCount / tgWidth;

#if MVK_BUILD_METAL4_FOUNDATION
    if (cmdEncoder->isUsingMetal4()) {
        NSError* error = nil;
        id<MTLBuffer> value = cmdEncoder->getMetal4Submission()->uploadBytes(&_dataValue, sizeof(_dataValue), &error);
        if (!value) { cmdEncoder->failMetal4Encoding("Could not upload Metal 4 fill pattern."); return; }
        id<MTL4ComputeCommandEncoder> compute = cmdEncoder->getMetal4ComputeEncoder(kMVKCommandUseFillBuffer, false, false, MTLStageDispatch);
        if (!mvkBindMetal4Transfer(cmdEncoder, compute, cps, {{dstMTLBuff, dstMTLBuffOffset}, {value, 0}})) return;
        if (tgCount) [compute dispatchThreadgroups:MTLSizeMake(tgCount, 1, 1) threadsPerThreadgroup:MTLSizeMake(tgWidth, 1, 1)];
        uint32_t remaining = _wordCount % tgWidth;
        if (remaining) {
            if (tgCount && !mvkBindMetal4Transfer(cmdEncoder, compute, cps,
                    {{dstMTLBuff, dstMTLBuffOffset + tgCount * tgWidth * sizeof(_dataValue)}, {value, 0}})) return;
            [compute dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(remaining, 1, 1)];
        }
        return;
    }
#endif

	id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseFillBuffer);
	MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
	[mtlComputeEnc pushDebugGroup: @"vkCmdFillBuffer"];
	state.bindPipeline(mtlComputeEnc, cps);
	state.bindStructBytes(mtlComputeEnc, &_dataValue, 1);
	state.bindBuffer(mtlComputeEnc, dstMTLBuff, dstMTLBuffOffset, 0);

	// Run as many full threadgroups as will fit into the buffer content.
	if (tgCount > 0) {
		[mtlComputeEnc dispatchThreadgroups: MTLSizeMake(tgCount, 1, 1)
					  threadsPerThreadgroup: MTLSizeMake(tgWidth, 1, 1)];
	}

	// If there is left-over buffer content after running full threadgroups, or if the buffer content
	// fits within a single threadgroup, run a single partial threadgroup of the appropriate size.
	uint32_t remainderWordCount = _wordCount % tgWidth;
	if (remainderWordCount > 0) {
		if (tgCount > 0) {		// If we've already written full threadgroups, skip ahead to unwritten content
			dstMTLBuffOffset += tgCount * tgWidth * sizeof(_dataValue);
			state.bindBuffer(mtlComputeEnc, dstMTLBuff, dstMTLBuffOffset, 0);
		}
		[mtlComputeEnc dispatchThreadgroups: MTLSizeMake(1, 1, 1)
					  threadsPerThreadgroup: MTLSizeMake(remainderWordCount, 1, 1)];
	}

	[mtlComputeEnc popDebugGroup];
}


#pragma mark -
#pragma mark MVKCmdUpdateBuffer

VkResult MVKCmdUpdateBuffer::setContent(MVKCommandBuffer* cmdBuff,
										VkBuffer dstBuffer,
										VkDeviceSize dstOffset,
										VkDeviceSize dataSize,
										const void* pData) {
    _dstBuffer = (MVKBuffer*)dstBuffer;
    _dstOffset = dstOffset;
    _dataSize = dataSize;

    _srcDataCache.reserve(_dataSize);
    memcpy(_srcDataCache.data(), pData, _dataSize);

	return VK_SUCCESS;
}

#if MVK_BUILD_METAL4_FOUNDATION
MVKMetal4RecordPolicy MVKCmdUpdateBuffer::getMetal4RecordPolicy() const {
	auto* memory = _dstBuffer ? _dstBuffer->getDeviceMemory() : nullptr;
	// setContent copied pData; encode uploads those copied bytes into the native
	// recording's owned arena before the command node can be reused.
	return memory && memory->isMetal4KnownInternalAllocation()
		? MVKMetal4RecordPolicy::Immediate : MVKMetal4RecordPolicy::Deferred;
}
#endif

void MVKCmdUpdateBuffer::encode(MVKCommandEncoder* cmdEncoder) {
#if MVK_BUILD_METAL4_FOUNDATION
    if (cmdEncoder->isUsingMetal4()) {
        NSError* error = nil;
        auto* submission = cmdEncoder->getMetal4Submission();
        id<MTLBuffer> source = submission->uploadBytes(_srcDataCache.data(), _dataSize, &error);
        id<MTLBuffer> target = _dstBuffer->getMTLBuffer();
        if (!source) { cmdEncoder->failMetal4Encoding("Could not upload Metal 4 vkCmdUpdateBuffer data."); return; }
        if (!mvkMetal4TransferResource(cmdEncoder, target)) return;
        id<MTL4ComputeCommandEncoder> copy = cmdEncoder->getMetal4ComputeEncoder(kMVKCommandUseUpdateBuffer, false, false, MTLStageBlit);
        if (!copy) return;
        [copy copyFromBuffer:source sourceOffset:0 toBuffer:target
          destinationOffset:_dstBuffer->getMTLBufferOffset() + _dstOffset size:_dataSize];
        return;
    }
#endif

    id<MTLBlitCommandEncoder> mtlBlitEnc = cmdEncoder->getMTLBlitEncoder(kMVKCommandUseUpdateBuffer);

    id<MTLBuffer> dstMTLBuff = _dstBuffer->getMTLBuffer();
    NSUInteger dstMTLBuffOffset = _dstBuffer->getMTLBufferOffset() + _dstOffset;

    // Copy data to the source MTLBuffer
    MVKMTLBufferAllocation* srcMTLBufferAlloc = cmdEncoder->getCommandEncodingPool()->acquireMTLBufferAllocation(_dataSize);
    void* pBuffData = srcMTLBufferAlloc->getContents();
    memcpy(pBuffData, _srcDataCache.data(), _dataSize);

    [mtlBlitEnc copyFromBuffer: srcMTLBufferAlloc->_mtlBuffer
                  sourceOffset: srcMTLBufferAlloc->_offset
                      toBuffer: dstMTLBuff
             destinationOffset: dstMTLBuffOffset
                          size: _dataSize];

    // Return the MTLBuffer allocation to the pool once the command buffer is done with it
    [cmdEncoder->_mtlCmdBuffer addCompletedHandler: ^(id<MTLCommandBuffer> mcb) {
        srcMTLBufferAlloc->returnToPool();
    }];
}
