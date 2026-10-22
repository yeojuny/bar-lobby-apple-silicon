template<class Descriptor>
void MVKRenderSubpass::populateMTLRenderPassDescriptorImpl(MVKCommandEncoder* cmdEncoder, Descriptor* mtlRPDesc,
													   uint32_t passIdx,
													   MVKFramebuffer* framebuffer,
													   MVKArrayRef<MVKImageView*const> attachments,
													   MVKArrayRef<const VkClearValue> clearValues,
													   bool isRenderingEntireAttachment,
													   bool loadOverride) {
	MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();
	const bool isSuspending = mvkIsAnyFlagEnabled(_renderPass->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT);

	// Populate the Metal color attachments
	uint32_t caCnt = getColorAttachmentCount();
	uint32_t caUsedCnt = 0;
	for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
		uint32_t clrRPAttIdx = _colorAttachments[caIdx].attachment;
        if (clrRPAttIdx != VK_ATTACHMENT_UNUSED) {
			++caUsedCnt;
            MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPDesc.colorAttachments[caIdx];

            // If it exists, configure the resolve attachment first,
            // as it affects the store action of the color attachment.
            uint32_t rslvRPAttIdx = caIdx < _resolveAttachments.size() ? _resolveAttachments[caIdx].attachment : VK_ATTACHMENT_UNUSED;
            bool hasResolveAttachment = (rslvRPAttIdx != VK_ATTACHMENT_UNUSED);
			bool canResolveFormat = true;
			if (hasResolveAttachment) {
				MVKImageView* raImgView = attachments[rslvRPAttIdx];
				canResolveFormat = mvkAreAllFlagsEnabled(pixFmts->getCapabilities(raImgView->getMTLPixelFormat()), kMVKMTLFmtCapsResolve);
				// Keep the logical resolve metadata, but do not attach a native
				// resolve destination to an encoder that must only preserve samples.
				if (canResolveFormat && !isSuspending) {
					raImgView->populateMTLRenderPassAttachmentDescriptorResolve(mtlColorAttDesc, cmdEncoder->getRenderPassAttachmentTexture(raImgView));

					// In a multiview render pass, we need to override the starting layer to ensure
					// only the enabled views are loaded.
					if (isMultiview()) {
						uint32_t startView = getFirstViewIndexInMetalPass(passIdx);
						if (mtlColorAttDesc.resolveTexture.textureType == MTLTextureType3D)
							mtlColorAttDesc.resolveDepthPlane += startView;
						else
							mtlColorAttDesc.resolveSlice += startView;
					}
				}
			}

            // Configure the color attachment
            MVKAttachmentDescription* clrMVKRPAtt = &_renderPass->_attachments[clrRPAttIdx];
			if (clrMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(cmdEncoder, mtlColorAttDesc, this, attachments[clrRPAttIdx],
                                                                       isRenderingEntireAttachment,
                                                                       hasResolveAttachment, canResolveFormat,
																	   false, loadOverride)) {
				mtlColorAttDesc.clearColor = pixFmts->getMTLClearColor(clearValues[clrRPAttIdx].color, clrMVKRPAtt->getFormat());
			}
			if (isMultiview()) {
				uint32_t startView = getFirstViewIndexInMetalPass(passIdx);
				if (mtlColorAttDesc.texture.textureType == MTLTextureType3D)
					mtlColorAttDesc.depthPlane += startView;
				else
					mtlColorAttDesc.slice += startView;
			}
		}
	}

	// Populate the Metal depth attachment
	uint32_t depthRPAttIdx = _depthAttachment.attachment;
	if (depthRPAttIdx != VK_ATTACHMENT_UNUSED) {
		MVKAttachmentDescription* depthMVKRPAtt = &_renderPass->_attachments[depthRPAttIdx];
		MVKImageView* depthImage = attachments[depthRPAttIdx];

		MVKImageView* depthRslvImage = nullptr;
		uint32_t depthRslvRPAttIdx = _depthResolveAttachment.attachment;
		if (depthRslvRPAttIdx != VK_ATTACHMENT_UNUSED) {
			depthRslvImage = attachments[depthRslvRPAttIdx];
		}

		MTLRenderPassDepthAttachmentDescriptor* mtlDepthAttDesc = mtlRPDesc.depthAttachment;
		bool hasDepthResolve = depthRslvRPAttIdx != VK_ATTACHMENT_UNUSED && _depthResolveMode != VK_RESOLVE_MODE_NONE;
		if (hasDepthResolve && !isSuspending) {
			depthRslvImage->populateMTLRenderPassAttachmentDescriptorResolve(mtlDepthAttDesc, cmdEncoder->getRenderPassAttachmentTexture(depthRslvImage));
			mtlDepthAttDesc.depthResolveFilter = mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBits(_depthResolveMode);
			if (isMultiview()) {
				mtlDepthAttDesc.resolveSlice += getFirstViewIndexInMetalPass(passIdx);
			}
		}
		if (depthMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(cmdEncoder, mtlDepthAttDesc, this, depthImage,
																	 isRenderingEntireAttachment,
																	 hasDepthResolve, true,
																	 false, loadOverride)) {
			mtlDepthAttDesc.clearDepth = pixFmts->getMTLClearDepthValue(clearValues[depthRPAttIdx].depthStencil);
		}
		if (isMultiview()) {
			mtlDepthAttDesc.slice += getFirstViewIndexInMetalPass(passIdx);
		}
	}

	// Populate the Metal stencil attachment
	uint32_t stencilRPAttIdx = _stencilAttachment.attachment;
	if (stencilRPAttIdx != VK_ATTACHMENT_UNUSED) {
		MVKAttachmentDescription* stencilMVKRPAtt = &_renderPass->_attachments[stencilRPAttIdx];
		MVKImageView* stencilImage = attachments[stencilRPAttIdx];

		MVKImageView* stencilRslvImage = nullptr;
		uint32_t stencilRslvRPAttIdx = _stencilResolveAttachment.attachment;
		if (stencilRslvRPAttIdx != VK_ATTACHMENT_UNUSED) {
			stencilRslvImage = attachments[stencilRslvRPAttIdx];
		}

		MTLRenderPassStencilAttachmentDescriptor* mtlStencilAttDesc = mtlRPDesc.stencilAttachment;
		bool hasStencilResolve = (stencilRslvRPAttIdx != VK_ATTACHMENT_UNUSED && _stencilResolveMode != VK_RESOLVE_MODE_NONE);
		if (hasStencilResolve && !isSuspending) {
			stencilRslvImage->populateMTLRenderPassAttachmentDescriptorResolve(mtlStencilAttDesc, cmdEncoder->getRenderPassAttachmentTexture(stencilRslvImage));
			mtlStencilAttDesc.stencilResolveFilter = mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBits(_stencilResolveMode);
			if (isMultiview()) {
				mtlStencilAttDesc.resolveSlice += getFirstViewIndexInMetalPass(passIdx);
			}
		}
		if (stencilMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(cmdEncoder, mtlStencilAttDesc, this, stencilImage,
																	   isRenderingEntireAttachment,
																	   hasStencilResolve, true,
																	   true, loadOverride)) {
			mtlStencilAttDesc.clearStencil = pixFmts->getMTLClearStencilValue(clearValues[stencilRPAttIdx].depthStencil);
		}
		if (isMultiview()) {
			mtlStencilAttDesc.slice += getFirstViewIndexInMetalPass(passIdx);
		}
	}

	if (caUsedCnt == 0 && depthRPAttIdx == VK_ATTACHMENT_UNUSED && stencilRPAttIdx == VK_ATTACHMENT_UNUSED) {
        mtlRPDesc.defaultRasterSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_defaultSampleCount);
	}

}

void MVKRenderSubpass::populateMTLRenderPassDescriptor(MVKCommandEncoder* cmdEncoder, MTLRenderPassDescriptor* mtlRPDesc,
													   uint32_t passIdx,
													   MVKFramebuffer* framebuffer,
													   MVKArrayRef<MVKImageView*const> attachments,
													   MVKArrayRef<const VkClearValue> clearValues,
													   bool isRenderingEntireAttachment,
													   bool loadOverride) {
	populateMTLRenderPassDescriptorImpl(cmdEncoder, mtlRPDesc, passIdx, framebuffer, attachments, clearValues, isRenderingEntireAttachment, loadOverride);

#if MVK_USE_METAL_PRIVATE_API
	if (getMVKConfig().useMetalPrivateAPI) {
		if ([mtlRPDesc respondsToSelector: @selector(setDitherEnabled:)]) {
			[mtlRPDesc setDitherEnabled:_isDitheringEnabled];
		}
		if ([mtlRPDesc respondsToSelector: @selector(setOpenGLModeEnabled:)]) {
			// Unlocks APIs such as setPrimitiveRestartEnabled.
			[mtlRPDesc setOpenGLModeEnabled:true];
		}
	}
#endif
}

#if MVK_BUILD_METAL4_FOUNDATION
void MVKRenderSubpass::populateMTLRenderPassDescriptor(MVKCommandEncoder* cmdEncoder, MTL4RenderPassDescriptor* mtlRPDesc,
													   uint32_t passIdx,
													   MVKFramebuffer* framebuffer,
													   MVKArrayRef<MVKImageView*const> attachments,
													   MVKArrayRef<const VkClearValue> clearValues,
													   bool isRenderingEntireAttachment,
													   bool loadOverride) {
	populateMTLRenderPassDescriptorImpl(cmdEncoder, mtlRPDesc, passIdx, framebuffer, attachments, clearValues, isRenderingEntireAttachment, loadOverride);
}
#endif

void MVKRenderSubpass::resolveUnresolvableAttachments(MVKCommandEncoder* cmdEncoder, MVKArrayRef<MVKImageView*const> attachments) {
	// A suspended logical pass has no resolve operation, including formats
	// that need the software helper. The final resumed pass owns that resolve.
	if (mvkIsAnyFlagEnabled(_renderPass->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT)) { return; }
	MVKPixelFormats* pixFmts = cmdEncoder->getPixelFormats();
	size_t raCnt = _resolveAttachments.size();
	for (uint32_t raIdx = 0; raIdx < raCnt; raIdx++) {
		auto& ra = _resolveAttachments[raIdx];
		auto& ca = _colorAttachments[raIdx];
		if (ra.attachment != VK_ATTACHMENT_UNUSED && ca.attachment != VK_ATTACHMENT_UNUSED) {
			MVKImageView* raImgView = attachments[ra.attachment];
			MVKImageView* caImgView = attachments[ca.attachment];

			if ( !mvkAreAllFlagsEnabled(pixFmts->getCapabilities(raImgView->getMTLPixelFormat()), kMVKMTLFmtCapsResolve) ) {
				MVKFormatType mvkFmtType = _renderPass->getPixelFormats()->getFormatType(raImgView->getMTLPixelFormat());
				const bool isTextureArray = raImgView->getImage()->getLayerCount() != 1u;
				id<MTLComputePipelineState> mtlRslvState = cmdEncoder->getCommandEncodingPool()->getCmdResolveColorImageMTLComputePipelineState(mvkFmtType, isTextureArray);
				id<MTLComputeCommandEncoder> mtlComputeEnc = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseResolveSubpassAttachment);
				MVKMetalComputeCommandEncoderState& state = cmdEncoder->getMtlCompute();
				state.bindPipeline(mtlComputeEnc, mtlRslvState);
				state.bindTexture(mtlComputeEnc, cmdEncoder->getRenderPassAttachmentTexture(raImgView), 0);
				state.bindTexture(mtlComputeEnc, cmdEncoder->getRenderPassAttachmentTexture(caImgView), 1);
				MTLSize gridSize = mvkMTLSizeFromVkExtent3D(raImgView->getExtent3D());
				MTLSize tgSize = MTLSizeMake(mtlRslvState.threadExecutionWidth, 1, 1);
				if (cmdEncoder->getMetalFeatures().nonUniformThreadgroups) {
					[mtlComputeEnc dispatchThreads: gridSize threadsPerThreadgroup: tgSize];
				} else {
					MTLSize tgCount = MTLSizeMake(gridSize.width / tgSize.width, gridSize.height, gridSize.depth);
					if (gridSize.width % tgSize.width) { tgCount.width += 1; }
					[mtlComputeEnc dispatchThreadgroups: tgCount threadsPerThreadgroup: tgSize];
				}
			}
		}
	}
}
void MVKRenderSubpass::populateLegacyReference(MVKCommandEncoder* cmdEncoder, MTLRenderPassDescriptor* mtlRPDesc,
													   uint32_t passIdx,
													   MVKFramebuffer* framebuffer,
													   MVKArrayRef<MVKImageView*const> attachments,
													   MVKArrayRef<const VkClearValue> clearValues,
													   bool isRenderingEntireAttachment,
													   bool loadOverride) {
	MVKPixelFormats* pixFmts = _renderPass->getPixelFormats();
	const bool isSuspending = mvkIsAnyFlagEnabled(_renderPass->getRenderingFlags(), VK_RENDERING_SUSPENDING_BIT);

	// Populate the Metal color attachments
	uint32_t caCnt = getColorAttachmentCount();
	uint32_t caUsedCnt = 0;
	for (uint32_t caIdx = 0; caIdx < caCnt; caIdx++) {
		uint32_t clrRPAttIdx = _colorAttachments[caIdx].attachment;
        if (clrRPAttIdx != VK_ATTACHMENT_UNUSED) {
			++caUsedCnt;
            MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPDesc.colorAttachments[caIdx];

            // If it exists, configure the resolve attachment first,
            // as it affects the store action of the color attachment.
            uint32_t rslvRPAttIdx = caIdx < _resolveAttachments.size() ? _resolveAttachments[caIdx].attachment : VK_ATTACHMENT_UNUSED;
            bool hasResolveAttachment = (rslvRPAttIdx != VK_ATTACHMENT_UNUSED);
			bool canResolveFormat = true;
			if (hasResolveAttachment) {
				MVKImageView* raImgView = attachments[rslvRPAttIdx];
				canResolveFormat = mvkAreAllFlagsEnabled(pixFmts->getCapabilities(raImgView->getMTLPixelFormat()), kMVKMTLFmtCapsResolve);
				// Keep the logical resolve metadata, but do not attach a native
				// resolve destination to an encoder that must only preserve samples.
				if (canResolveFormat && !isSuspending) {
					raImgView->populateMTLRenderPassAttachmentDescriptorResolve(mtlColorAttDesc, cmdEncoder->getRenderPassAttachmentTexture(raImgView));

					// In a multiview render pass, we need to override the starting layer to ensure
					// only the enabled views are loaded.
					if (isMultiview()) {
						uint32_t startView = getFirstViewIndexInMetalPass(passIdx);
						if (mtlColorAttDesc.resolveTexture.textureType == MTLTextureType3D)
							mtlColorAttDesc.resolveDepthPlane += startView;
						else
							mtlColorAttDesc.resolveSlice += startView;
					}
				}
			}

            // Configure the color attachment
            MVKAttachmentDescription* clrMVKRPAtt = &_renderPass->_attachments[clrRPAttIdx];
			if (clrMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(cmdEncoder, mtlColorAttDesc, this, attachments[clrRPAttIdx],
                                                                       isRenderingEntireAttachment,
                                                                       hasResolveAttachment, canResolveFormat,
																	   false, loadOverride)) {
				mtlColorAttDesc.clearColor = pixFmts->getMTLClearColor(clearValues[clrRPAttIdx].color, clrMVKRPAtt->getFormat());
			}
			if (isMultiview()) {
				uint32_t startView = getFirstViewIndexInMetalPass(passIdx);
				if (mtlColorAttDesc.texture.textureType == MTLTextureType3D)
					mtlColorAttDesc.depthPlane += startView;
				else
					mtlColorAttDesc.slice += startView;
			}
		}
	}

	// Populate the Metal depth attachment
	uint32_t depthRPAttIdx = _depthAttachment.attachment;
	if (depthRPAttIdx != VK_ATTACHMENT_UNUSED) {
		MVKAttachmentDescription* depthMVKRPAtt = &_renderPass->_attachments[depthRPAttIdx];
		MVKImageView* depthImage = attachments[depthRPAttIdx];

		MVKImageView* depthRslvImage = nullptr;
		uint32_t depthRslvRPAttIdx = _depthResolveAttachment.attachment;
		if (depthRslvRPAttIdx != VK_ATTACHMENT_UNUSED) {
			depthRslvImage = attachments[depthRslvRPAttIdx];
		}

		MTLRenderPassDepthAttachmentDescriptor* mtlDepthAttDesc = mtlRPDesc.depthAttachment;
		bool hasDepthResolve = depthRslvRPAttIdx != VK_ATTACHMENT_UNUSED && _depthResolveMode != VK_RESOLVE_MODE_NONE;
		if (hasDepthResolve && !isSuspending) {
			depthRslvImage->populateMTLRenderPassAttachmentDescriptorResolve(mtlDepthAttDesc, cmdEncoder->getRenderPassAttachmentTexture(depthRslvImage));
			mtlDepthAttDesc.depthResolveFilter = mvkMTLMultisampleDepthResolveFilterFromVkResolveModeFlagBits(_depthResolveMode);
			if (isMultiview()) {
				mtlDepthAttDesc.resolveSlice += getFirstViewIndexInMetalPass(passIdx);
			}
		}
		if (depthMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(cmdEncoder, mtlDepthAttDesc, this, depthImage,
																	 isRenderingEntireAttachment,
																	 hasDepthResolve, true,
																	 false, loadOverride)) {
			mtlDepthAttDesc.clearDepth = pixFmts->getMTLClearDepthValue(clearValues[depthRPAttIdx].depthStencil);
		}
		if (isMultiview()) {
			mtlDepthAttDesc.slice += getFirstViewIndexInMetalPass(passIdx);
		}
	}

	// Populate the Metal stencil attachment
	uint32_t stencilRPAttIdx = _stencilAttachment.attachment;
	if (stencilRPAttIdx != VK_ATTACHMENT_UNUSED) {
		MVKAttachmentDescription* stencilMVKRPAtt = &_renderPass->_attachments[stencilRPAttIdx];
		MVKImageView* stencilImage = attachments[stencilRPAttIdx];

		MVKImageView* stencilRslvImage = nullptr;
		uint32_t stencilRslvRPAttIdx = _stencilResolveAttachment.attachment;
		if (stencilRslvRPAttIdx != VK_ATTACHMENT_UNUSED) {
			stencilRslvImage = attachments[stencilRslvRPAttIdx];
		}

		MTLRenderPassStencilAttachmentDescriptor* mtlStencilAttDesc = mtlRPDesc.stencilAttachment;
		bool hasStencilResolve = (stencilRslvRPAttIdx != VK_ATTACHMENT_UNUSED && _stencilResolveMode != VK_RESOLVE_MODE_NONE);
		if (hasStencilResolve && !isSuspending) {
			stencilRslvImage->populateMTLRenderPassAttachmentDescriptorResolve(mtlStencilAttDesc, cmdEncoder->getRenderPassAttachmentTexture(stencilRslvImage));
			mtlStencilAttDesc.stencilResolveFilter = mvkMTLMultisampleStencilResolveFilterFromVkResolveModeFlagBits(_stencilResolveMode);
			if (isMultiview()) {
				mtlStencilAttDesc.resolveSlice += getFirstViewIndexInMetalPass(passIdx);
			}
		}
		if (stencilMVKRPAtt->populateMTLRenderPassAttachmentDescriptor(cmdEncoder, mtlStencilAttDesc, this, stencilImage,
																	   isRenderingEntireAttachment,
																	   hasStencilResolve, true,
																	   true, loadOverride)) {
			mtlStencilAttDesc.clearStencil = pixFmts->getMTLClearStencilValue(clearValues[stencilRPAttIdx].depthStencil);
		}
		if (isMultiview()) {
			mtlStencilAttDesc.slice += getFirstViewIndexInMetalPass(passIdx);
		}
	}

	if (caUsedCnt == 0 && depthRPAttIdx == VK_ATTACHMENT_UNUSED && stencilRPAttIdx == VK_ATTACHMENT_UNUSED) {
        mtlRPDesc.defaultRasterSampleCount = mvkSampleCountFromVkSampleCountFlagBits(_defaultSampleCount);
	}

#if MVK_USE_METAL_PRIVATE_API
	if (getMVKConfig().useMetalPrivateAPI) {
		if ([mtlRPDesc respondsToSelector: @selector(setDitherEnabled:)]) {
			[mtlRPDesc setDitherEnabled:_isDitheringEnabled];
		}
		if ([mtlRPDesc respondsToSelector: @selector(setOpenGLModeEnabled:)]) {
			// Unlocks APIs such as setPrimitiveRestartEnabled.
			[mtlRPDesc setOpenGLModeEnabled:true];
		}
	}
#endif
}
