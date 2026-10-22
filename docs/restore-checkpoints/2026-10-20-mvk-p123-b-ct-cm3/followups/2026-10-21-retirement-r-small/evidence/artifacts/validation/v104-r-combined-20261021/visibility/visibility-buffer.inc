MVKVisibilityBuffer::MVKVisibilityBuffer(id<MTLDevice> device, NSUInteger size, uint32_t nameIdx) {
	_halfSize = static_cast<uint32_t>(size / 2);
	assert(_halfSize % kMVKQuerySlotSizeInBytes == 0);
	@autoreleasepool {
		MTLResourceOptions options = MTLResourceHazardTrackingModeUntracked | MTLResourceStorageModePrivate;
		_buffer = [device newBufferWithLength:_halfSize * 2 options:options];
		if (_buffer) {
			_needsInitialClear = true;
			[_buffer setLabel:[NSString stringWithFormat:@"Metal Visibility Result Buffer %d", nameIdx]];
			for (uint32_t gid = 0; gid < std::size(_fences); gid++) {
				for (uint32_t lohi = 0; lohi < std::size(_fences[0]); lohi++) {
					_fences[gid][lohi] = [device newFence];
					[_fences[gid][lohi] setLabel:[NSString stringWithFormat:@"Visibility Fence %d %c%d", nameIdx, lohi ? 'H' : 'L', gid]];
				}
			}
		}
	}
}

MVKVisibilityBuffer::~MVKVisibilityBuffer() {
	if (_buffer) {
		[_buffer release];
		for (auto& groups : _fences)
			for (auto& fence : groups)
				[fence release];
	}
}

uint32_t MVKVisibilityBuffer::advanceOffset() {
	_currentOffset += kMVKQuerySlotSizeInBytes;
	if (_currentOffset >= _halfSize * 2) {
		_currentOffset = 0;
		for (int lohi = 0; lohi < 2; lohi++) {
			// Rotate fences so that the new prevRead is the previous read
			id<MTLFence> read = _fences[0][lohi];
			for (int i = 0; i < 2; i++)
				_fences[i][lohi] = _fences[i + 1][lohi];
			_fences[2][lohi] = read;
		}
		return 0;
	}
	return _currentOffset;
}
