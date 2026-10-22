template<class Descriptor>
bool MVKCommandEncoder::prepareVisibilityResultBuffer(Descriptor* descriptor) {
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
