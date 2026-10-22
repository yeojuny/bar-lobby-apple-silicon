class MVKVisibilityBuffer {
public:
	struct FenceSet {
		id<MTLFence> read;     ///< Updated by reads
		id<MTLFence> write;    ///< Updated by writes, and waited on by reads
		id<MTLFence> prevRead; ///< The read fence from the previous use of the buffer, waited on by writes to prevent WAR hazards
	};
private:
	id<MTLBuffer> _buffer = nullptr;
	uint32_t _currentOffset = 0;
	uint32_t _halfSize = 0;
	bool _needsInitialClear = false;
	id<MTLFence> _fences[3][2] = {};
public:
	id<MTLBuffer> buffer() const { return _buffer; }
	uint32_t offset() const { return _currentOffset; }
	uint32_t size() const { return _halfSize * 2; }
	bool needsInitialClear() const { return _needsInitialClear; }
	void markInitialClearEncoded() { _needsInitialClear = false; }
	id<MTLFence> initialClearFence(uint32_t half) const { return _fences[2][half]; }
	bool isFirstWithCurrentFence() const { return _currentOffset == _halfSize || _currentOffset == 0; }
	FenceSet currentFence() const {
		uint32_t idx = _currentOffset >= _halfSize ? 1 : 0;
		return { _fences[0][idx], _fences[1][idx], _fences[2][idx] };
	}
	MVKVisibilityBuffer() = default;
	MVKVisibilityBuffer(id<MTLDevice> device, NSUInteger size, uint32_t nameIdx);
	MVKVisibilityBuffer(const MVKVisibilityBuffer&) = delete;
	MVKVisibilityBuffer(MVKVisibilityBuffer&& other) {
		_buffer = std::exchange(other._buffer, nil);
		_currentOffset = other._currentOffset;
		_halfSize = other._halfSize;
		_needsInitialClear = std::exchange(other._needsInitialClear, false);
		for (uint32_t i = 0; i < std::size(_fences); i++)
			for (uint32_t j = 0; j < std::size(_fences[0]); j++)
				_fences[i][j] = std::exchange(other._fences[i][j], nil);
	}
	~MVKVisibilityBuffer();
	/// Advances `_currentOffset`, swaps fences if needed, and returns the new offset.
	uint32_t advanceOffset();
	MVKVisibilityBuffer& operator=(MVKVisibilityBuffer&& other) {
		if (this != &other) {
			this->~MVKVisibilityBuffer();
			new (this) MVKVisibilityBuffer(std::move(other));
		}
		return *this;
	}
};
