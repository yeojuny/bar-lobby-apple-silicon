/*
 * MVKMetal4ArgumentTable.mm
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

#include "MVKMetal4ArgumentTable.h"
#include "MVKMetal4Submission.h"
#include <cstring>
#include <limits>

NSString* const MVKMetal4ArgumentTableErrorDomain = @"MVKMetal4ArgumentTableErrorDomain";

bool MVKMetal4ArgumentTables::fail(NSError** error, ErrorCode code, NSString* description) {
	if (error) {
		*error = [NSError errorWithDomain:MVKMetal4ArgumentTableErrorDomain
		                           code:static_cast<NSInteger>(code)
		                       userInfo:@{ NSLocalizedDescriptionKey: description }];
	}
	return false;
}

bool MVKMetal4ArgumentTables::initialize(id<MTLDevice> device, const Limits& limits,
	                                    NSError** error) {
	return initializeStages(device, limits, (1u << static_cast<NSUInteger>(Stage::Count)) - 1, error);
}

bool MVKMetal4ArgumentTables::initializeCompute(id<MTLDevice> device, const Limits& limits,
	                                           NSError** error) {
	return initializeStages(device, limits, 1u << static_cast<NSUInteger>(Stage::Compute), error);
}

bool MVKMetal4ArgumentTables::initializeStages(id<MTLDevice> device, const Limits& limits,
	                                          NSUInteger stageMask, NSError** error) {
	if (error) { *error = nil; }
	if (isInitialized()) {
		return fail(error, ErrorCode::InvalidState, @"Metal 4 argument tables are already initialized.");
	}
	if (!device) {
		return fail(error, ErrorCode::WrongDevice, @"A Metal device is required.");
	}
	if (limits.bufferCount > 31 || limits.textureCount > 128 || limits.samplerCount > 16) {
		return fail(error, ErrorCode::InvalidLimits, @"Argument-table counts exceed SDK limits (31 buffers, 128 textures, 16 samplers).");
	}
	if (@available(macOS 26.0, iOS 26.0, *)) {
		if (![device supportsFamily:MTLGPUFamilyMetal4]) {
			return fail(error, ErrorCode::Unsupported, @"The device does not support the Metal 4 family.");
		}
		MTL4ArgumentTableDescriptor* descriptor = [[MTL4ArgumentTableDescriptor alloc] init];
		descriptor.maxBufferBindCount = limits.bufferCount;
		descriptor.maxTextureBindCount = limits.textureCount;
		descriptor.maxSamplerStateBindCount = limits.samplerCount;
		descriptor.initializeBindings = YES;
		descriptor.supportAttributeStrides = (stageMask & (1u << static_cast<NSUInteger>(Stage::Vertex))) != 0;

		id<MTL4ArgumentTable> tables[static_cast<NSUInteger>(Stage::Count)] = {};
		NSString* labels[] = { @"MVK Metal 4 vertex arguments", @"MVK Metal 4 fragment arguments",
		                       @"MVK Metal 4 compute arguments" };
		for (NSUInteger i = 0; i < static_cast<NSUInteger>(Stage::Count); ++i) {
			if (!(stageMask & (1u << i))) { continue; }
			descriptor.label = labels[i];
			NSError* creationError = nil;
			tables[i] = [device newArgumentTableWithDescriptor:descriptor error:&creationError];
			if (!tables[i]) {
				for (id<MTL4ArgumentTable> table : tables) { [table release]; }
				[descriptor release];
				if (creationError) {
					if (error) { *error = creationError; }
					return false;
				}
				return fail(error, ErrorCode::AllocationFailed, @"Metal failed to create an argument table.");
			}
		}
		[descriptor release];
		for (NSUInteger i = 0; i < static_cast<NSUInteger>(Stage::Count); ++i) { _tables[i] = tables[i]; }
		_limits = limits;
		// initializeBindings guarantees nil bindings. Match those known values
		// without issuing redundant Metal writes. Stride setter mode stays false:
		// no assumption about the initializer's attribute-stride contents is needed.
		for (NSUInteger i = 0; i < static_cast<NSUInteger>(Stage::Count); ++i) {
			for (auto& slot : _buffers[i]) { slot = {0, 0, true, false}; }
			for (auto& slot : _textures[i]) { slot = {0, true}; }
			for (auto& slot : _samplers[i]) { slot = {0, true}; }
			for (auto& revision : _bufferBindingRevisions[i]) { revision = 1; }
		}
		_device = [device retain];
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 argument tables require macOS 26 or iOS 26.");
}

MVKMetal4ArgumentTables::~MVKMetal4ArgumentTables() {
	for (auto& stage : _byteUploads) { for (auto& upload : stage) { [upload.buffer release]; } }
	for (auto& stage : _buffers) { for (auto& slot : stage) { [slot.resource release]; } }
	for (auto& stage : _textures) { for (auto& slot : stage) { [slot.resource release]; } }
	for (auto& stage : _samplers) { for (auto& slot : stage) { [slot.resource release]; } }
	for (id<MTL4ArgumentTable> table : _tables) { [table release]; }
	[_device release];
}

bool MVKMetal4ArgumentTables::validateStage(Stage stage, NSError** error) const {
	if (!isInitialized()) {
		return fail(error, ErrorCode::InvalidState, @"Metal 4 argument tables are not initialized.");
	}
	if (static_cast<NSUInteger>(stage) >= static_cast<NSUInteger>(Stage::Count) ||
		!_tables[static_cast<NSUInteger>(stage)]) {
		return fail(error, ErrorCode::InvalidStage, @"The requested shader stage has no argument table.");
	}
	return true;
}

bool MVKMetal4ArgumentTables::invalidateCachedBindings(Stage stage, NSError** error) {
	if (error) { *error = nil; }
	if (!validateStage(stage, error)) { return false; }
	NSUInteger si = static_cast<NSUInteger>(stage);
	invalidateBufferRevisions(si);
	for (NSUInteger i = 0; i < _limits.bufferCount; ++i) {
		_buffers[si][i].known = false; _dirtyBuffers[si] |= uint32_t(1) << i;
	}
	for (NSUInteger i = 0; i < _limits.textureCount; ++i) {
		_textures[si][i].known = false; _dirtyTextures[si][i / 64] |= uint64_t(1) << (i % 64);
	}
	for (NSUInteger i = 0; i < _limits.samplerCount; ++i) {
		_samplers[si][i].known = false; _dirtySamplers[si] |= uint32_t(1) << i;
	}
	return true;
}

void MVKMetal4ArgumentTables::invalidateBufferRevisions(NSUInteger stage) {
	for (NSUInteger i = 0; i < _limits.bufferCount; ++i) {
		// Zero permanently disables memoization after a theoretical wrap rather
		// than making an old generation current again.
		auto& revision = _bufferBindingRevisions[stage][i];
		if (revision) { ++revision; }
	}
}

uint64_t MVKMetal4ArgumentTables::bufferBindingRevision(Stage stage, NSUInteger index) const {
	NSUInteger si = static_cast<NSUInteger>(stage);
	return si < static_cast<NSUInteger>(Stage::Count) && _tables[si] && index < _limits.bufferCount
		? _bufferBindingRevisions[si][index] : 0;
}

NSUInteger MVKMetal4ArgumentTables::getStageMask() const {
	NSUInteger mask = 0;
	for (NSUInteger i = 0; i < static_cast<NSUInteger>(Stage::Count); ++i) {
		if (_tables[i]) { mask |= NSUInteger(1) << i; }
	}
	return mask;
}

uint64_t MVKMetal4ArgumentTables::retainedHostByteCapacity() const {
	uint64_t bytes = 0;
	for (const auto& stage : _byteUploads) {
		for (const auto& upload : stage) { bytes += upload.bytes.capacity(); }
	}
	return bytes;
}

void MVKMetal4ArgumentTables::discardByteUploads(bool boundHostCapacity) {
	size_t remainingCapacity = 64 * 1024;
	for (auto& stage : _byteUploads) {
		for (auto& upload : stage) {
			[upload.buffer release];
			upload.buffer = nil;
			upload.offset = 0;
			if (boundHostCapacity && upload.bytes.capacity() > remainingCapacity) {
				std::vector<uint8_t>().swap(upload.bytes);
			} else {
				if (boundHostCapacity) { remainingCapacity -= upload.bytes.capacity(); }
				upload.bytes.clear();
			}
		}
	}
	_byteUploadRecordingToken.reset();
}

bool MVKMetal4ArgumentTables::resetBindingsForNextEncoder(NSError** error) {
	if (error) { *error = nil; }
	if (!isInitialized()) { return fail(error, ErrorCode::InvalidState, @"Metal 4 argument tables are not initialized."); }
	// A fresh Vulkan encoder has no inherited logical bindings. Keep the physical
	// values so a successful same-value setter can claim them without a zero/write
	// pair; unresolved old values become nil at the first bind of their stage.
	// Inactive stages retain pending nils until used or fully retired.
	for (NSUInteger i = 0; i < static_cast<NSUInteger>(Stage::Count); ++i) {
		if (!_tables[i]) { continue; }
		_pendingBuffers[i] = _dirtyBuffers[i];
		_pendingTextures[i][0] = _dirtyTextures[i][0];
		_pendingTextures[i][1] = _dirtyTextures[i][1];
		_pendingSamplers[i] = _dirtySamplers[i];
		invalidateBufferRevisions(i);
	}
	return true;
}

bool MVKMetal4ArgumentTables::resetForReuse(NSError** error) {
	if (error) { *error = nil; }
	if (!isInitialized()) { return fail(error, ErrorCode::InvalidState, @"Metal 4 argument tables are not initialized."); }
	for (NSUInteger i = 0; i < static_cast<NSUInteger>(Stage::Count); ++i) {
		if (_tables[i] && !clearBindings(static_cast<Stage>(i), error)) { return false; }
	}
	// Only GPU retirement permits dropping cached upload identities and reusing
	// arena storage. Sequential CPU encoder reuse intentionally keeps both.
	discardByteUploads(true);
	return true;
}

bool MVKMetal4ArgumentTables::clearBindings(Stage stage, NSError** error) {
	if (error) { *error = nil; }
	if (!validateStage(stage, error)) { return false; }
	NSUInteger si = static_cast<NSUInteger>(stage);
	invalidateBufferRevisions(si);
	return clearBindingSlots(stage, _dirtyBuffers[si], _dirtyTextures[si], _dirtySamplers[si], error);
}

bool MVKMetal4ArgumentTables::resolvePendingBindings(Stage stage, NSError** error) {
	NSUInteger si = static_cast<NSUInteger>(stage);
	if (!_pendingBuffers[si] && !_pendingTextures[si][0] && !_pendingTextures[si][1] && !_pendingSamplers[si]) { return true; }
	return clearBindingSlots(stage, _pendingBuffers[si], _pendingTextures[si], _pendingSamplers[si], error);
}

bool MVKMetal4ArgumentTables::clearBindingSlots(Stage stage, uint32_t bufferMask,
	                                           const uint64_t* textureMasks, uint32_t samplerMask,
	                                           NSError** error) {
	if (@available(macOS 26.0, iOS 26.0, *)) {
		NSUInteger si = static_cast<NSUInteger>(stage);
		id<MTL4ArgumentTable> table = _tables[si];
		// Copy before modifying the dirty/pending masks: callers can pass either.
		uint64_t textureMask[2] = {textureMasks[0], textureMasks[1]};
		uint32_t buffers = bufferMask;
		while (buffers) {
			NSUInteger i = __builtin_ctz(buffers); buffers &= buffers - 1;
			auto& slot = _buffers[si][i];
			bool withStride = _tables[static_cast<NSUInteger>(Stage::Vertex)] != nil;
			if (!slot.known || slot.address || slot.withStride != withStride || (withStride && slot.stride)) {
				if (withStride) { [table setAddress:0 attributeStride:0 atIndex:i]; }
				else { [table setAddress:0 atIndex:i]; }
				++_bindingWriteCount;
			}
			[slot.resource release];
			slot = {0, 0, true, withStride};
			auto& revision = _bufferBindingRevisions[si][i];
			if (revision) { ++revision; }
		}
		_dirtyBuffers[si] &= ~bufferMask;
		_pendingBuffers[si] &= ~bufferMask;
		for (NSUInteger word = 0; word < 2; ++word) {
			uint64_t textures = textureMask[word];
			while (textures) {
				NSUInteger i = word * 64 + __builtin_ctzll(textures); textures &= textures - 1;
				auto& slot = _textures[si][i];
				if (!slot.known || slot.resourceID) { [table setTexture:MTLResourceID{} atIndex:i]; ++_bindingWriteCount; }
				[slot.resource release];
				slot = {0, true};
			}
			_dirtyTextures[si][word] &= ~textureMask[word];
			_pendingTextures[si][word] &= ~textureMask[word];
		}
		uint32_t samplers = samplerMask;
		while (samplers) {
			NSUInteger i = __builtin_ctz(samplers); samplers &= samplers - 1;
			auto& slot = _samplers[si][i];
			if (!slot.known || slot.resourceID) { [table setSamplerState:MTLResourceID{} atIndex:i]; ++_bindingWriteCount; }
			[slot.resource release];
			slot = {0, true};
		}
		_dirtySamplers[si] &= ~samplerMask;
		_pendingSamplers[si] &= ~samplerMask;
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 argument binding is unavailable.");
}

bool MVKMetal4ArgumentTables::validateSlot(Stage stage, NSUInteger index, NSUInteger count,
	                                      NSError** error) const {
	if (!validateStage(stage, error)) { return false; }
	if (index >= count) {
		return fail(error, ErrorCode::InvalidIndex, @"The binding index is outside the configured argument table.");
	}
	return true;
}

bool MVKMetal4ArgumentTables::getBufferAddress(id<MTLBuffer> buffer, NSUInteger offset,
	                                          MTLGPUAddress& address, BufferSlot& slot, NSError** error) const {
	address = 0;
	if (!buffer) {
		if (offset) { return fail(error, ErrorCode::InvalidBufferRange, @"Clearing a buffer binding requires a zero offset."); }
		[slot.resource release];
		slot.resource = nil; slot.baseAddress = 0; slot.length = 0;
		return true;
	}
	// The slot owns this exact object. Its read-only device, length and GPU base
	// remain valid for that lifetime; offset/range/overflow are checked every time.
	bool prepared = slot.resource == buffer;
	if (!prepared && buffer.device != _device) {
		return fail(error, ErrorCode::WrongDevice, @"The buffer belongs to a different Metal device.");
	}
	NSUInteger length = prepared ? slot.length : buffer.length;
	if (offset > length) {
		return fail(error, ErrorCode::InvalidBufferRange, @"The buffer offset exceeds its length.");
	}
	if (@available(macOS 26.0, iOS 26.0, *)) {
		MTLGPUAddress baseAddress = prepared ? slot.baseAddress : buffer.gpuAddress;
		if (!baseAddress || offset > std::numeric_limits<MTLGPUAddress>::max() - baseAddress) {
			return fail(error, ErrorCode::InvalidBufferRange, @"The buffer GPU address is unavailable or its offset overflows.");
		}
		address = baseAddress + offset;
		if (!prepared) {
			[buffer retain]; [slot.resource release];
			slot.resource = buffer; slot.baseAddress = baseAddress; slot.length = length;
		}
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 buffer address binding is unavailable.");
}

bool MVKMetal4ArgumentTables::setBuffer(Stage stage, id<MTLBuffer> buffer, NSUInteger offset,
	                                   NSUInteger index, NSError** error) {
	if (error) { *error = nil; }
	if (!validateSlot(stage, index, _limits.bufferCount, error)) { return false; }
	auto& slot = _buffers[static_cast<NSUInteger>(stage)][index];
	MTLGPUAddress address;
	if (!getBufferAddress(buffer, offset, address, slot, error)) { return false; }
	if (@available(macOS 26.0, iOS 26.0, *)) {
		_pendingBuffers[static_cast<NSUInteger>(stage)] &= ~(uint32_t(1) << index);
		if (slot.known && !slot.withStride && slot.address == address) { return true; }
		[_tables[static_cast<NSUInteger>(stage)] setAddress:address atIndex:index];
		// Conservatively distinguish the two setters: the SDK does not promise
		// whether the address-only setter preserves a previously supplied stride.
		slot.address = address; slot.stride = 0; slot.known = true; slot.withStride = false;
		_dirtyBuffers[static_cast<NSUInteger>(stage)] |= uint32_t(1) << index;
		auto& revision = _bufferBindingRevisions[static_cast<NSUInteger>(stage)][index];
		if (revision) { ++revision; }
		++_bindingWriteCount;
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 argument binding is unavailable.");
}

bool MVKMetal4ArgumentTables::setBufferWithStride(Stage stage, id<MTLBuffer> buffer,
	                                             NSUInteger offset, NSUInteger stride,
	                                             NSUInteger index, NSError** error) {
	if (error) { *error = nil; }
	if (!validateSlot(stage, index, _limits.bufferCount, error)) { return false; }
	if (!_tables[static_cast<NSUInteger>(Stage::Vertex)]) {
		return fail(error, ErrorCode::InvalidStage, @"Compute-only tables do not support vertex attribute strides.");
	}
	if (!buffer && stride != 0) {
		return fail(error, ErrorCode::InvalidBufferRange, @"Clearing a dynamic buffer binding requires a zero stride.");
	}
	auto& slot = _buffers[static_cast<NSUInteger>(stage)][index];
	MTLGPUAddress address;
	if (!getBufferAddress(buffer, offset, address, slot, error)) { return false; }
	if (@available(macOS 26.0, iOS 26.0, *)) {
		_pendingBuffers[static_cast<NSUInteger>(stage)] &= ~(uint32_t(1) << index);
		if (slot.known && slot.withStride && slot.address == address && slot.stride == stride) { return true; }
		[_tables[static_cast<NSUInteger>(stage)] setAddress:address attributeStride:stride atIndex:index];
		slot.address = address; slot.stride = stride; slot.known = true; slot.withStride = true;
		_dirtyBuffers[static_cast<NSUInteger>(stage)] |= uint32_t(1) << index;
		auto& revision = _bufferBindingRevisions[static_cast<NSUInteger>(stage)][index];
		if (revision) { ++revision; }
		++_bindingWriteCount;
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 argument binding is unavailable.");
}

bool MVKMetal4ArgumentTables::setTexture(Stage stage, id<MTLTexture> texture, NSUInteger index,
	                                    NSError** error) {
	if (error) { *error = nil; }
	if (!validateSlot(stage, index, _limits.textureCount, error)) { return false; }
	auto& slot = _textures[static_cast<NSUInteger>(stage)][index];
	if (slot.known && slot.resource == texture) {
		_pendingTextures[static_cast<NSUInteger>(stage)][index / 64] &= ~(uint64_t(1) << (index % 64));
		return true;
	}
	if (texture && texture.device != _device) {
		return fail(error, ErrorCode::WrongDevice, @"The texture belongs to a different Metal device.");
	}
	if (@available(macOS 26.0, iOS 26.0, *)) {
		MTLResourceID resourceID = texture ? texture.gpuResourceID : MTLResourceID{};
		if (texture && !resourceID._impl) {
			return fail(error, ErrorCode::InvalidResource, @"The texture has no GPU resource ID for argument binding.");
		}
		if (!slot.known || slot.resourceID != resourceID._impl) {
			[_tables[static_cast<NSUInteger>(stage)] setTexture:resourceID atIndex:index];
			++_bindingWriteCount;
		}
		[texture retain]; [slot.resource release];
		slot = {resourceID._impl, true, texture};
		_dirtyTextures[static_cast<NSUInteger>(stage)][index / 64] |= uint64_t(1) << (index % 64);
		_pendingTextures[static_cast<NSUInteger>(stage)][index / 64] &= ~(uint64_t(1) << (index % 64));
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 argument binding is unavailable.");
}

bool MVKMetal4ArgumentTables::setSampler(Stage stage, id<MTLSamplerState> sampler,
	                                    NSUInteger index, NSError** error) {
	if (error) { *error = nil; }
	if (!validateSlot(stage, index, _limits.samplerCount, error)) { return false; }
	auto& slot = _samplers[static_cast<NSUInteger>(stage)][index];
	if (slot.known && slot.resource == sampler) {
		_pendingSamplers[static_cast<NSUInteger>(stage)] &= ~(uint32_t(1) << index);
		return true;
	}
	if (sampler && sampler.device != _device) {
		return fail(error, ErrorCode::WrongDevice, @"The sampler belongs to a different Metal device.");
	}
	if (@available(macOS 26.0, iOS 26.0, *)) {
		MTLResourceID resourceID = sampler ? sampler.gpuResourceID : MTLResourceID{};
		if (sampler && !resourceID._impl) {
			return fail(error, ErrorCode::InvalidResource, @"The sampler has no GPU resource ID for argument binding.");
		}
		if (!slot.known || slot.resourceID != resourceID._impl) {
			[_tables[static_cast<NSUInteger>(stage)] setSamplerState:resourceID atIndex:index];
			++_bindingWriteCount;
		}
		[sampler retain]; [slot.resource release];
		slot = {resourceID._impl, true, sampler};
		_dirtySamplers[static_cast<NSUInteger>(stage)] |= uint32_t(1) << index;
		_pendingSamplers[static_cast<NSUInteger>(stage)] &= ~(uint32_t(1) << index);
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 argument binding is unavailable.");
}

bool MVKMetal4ArgumentTables::setBytes(Stage stage, const void* data, NSUInteger length,
	                                  NSUInteger index, MVKMetal4Submission& submission,
	                                  NSError** error) {
	if (error) { *error = nil; }
	if (!validateSlot(stage, index, _limits.bufferCount, error)) { return false; }
	if (!length) { return setBuffer(stage, nil, 0, index, error); }
	if (!data) { return fail(error, ErrorCode::InvalidBufferRange, @"Nonempty inline data requires a host pointer."); }
	if (!submission.matchesRecordingToken(_byteUploadRecordingToken)) {
		// Retaining an arena buffer does not reserve its bytes past GPU retirement.
		// Weak control-block identity prevents same-address submission ABA without
		// making a cycle between the table's cache and its owning submission.
		discardByteUploads(false);
		_byteUploadRecordingToken = submission.recordingToken();
	}
	auto& cached = _byteUploads[static_cast<NSUInteger>(stage)][index];
	if (cached.buffer && cached.bytes.size() == length && !memcmp(cached.bytes.data(), data, length)) {
		// Matching weak identity alone does not establish Phase::Recording. Keep
		// the old registration/error path after end/retirement; recording is
		// externally serialized, just as for the original addResource + setter.
		if (!submission.commandBuffer()) {
			return submission.addResource(cached.buffer, error) && setBuffer(stage, cached.buffer, cached.offset, index, error);
		}
		// uploadBytesRange already retained and made this exact immutable buffer
		// resident in this recording. It is a buffer, never a drawable texture.
		// Keep setter validation/restoration, skip only the duplicate map lookup.
		return setBuffer(stage, cached.buffer, cached.offset, index, error);
	}
	// The old slice remains immutable and submission-owned until GPU retirement.
	auto upload = submission.uploadBytesRange(data, length, error);
	if (!upload.buffer || !setBuffer(stage, upload.buffer, upload.offset, index, error)) { return false; }
	cached.bytes.assign(static_cast<const uint8_t*>(data), static_cast<const uint8_t*>(data) + length);
	[upload.buffer retain];
	[cached.buffer release];
	cached.buffer = upload.buffer;
	cached.offset = upload.offset;
	++_byteUploadCount;
	return true;
}

bool MVKMetal4ArgumentTables::validateEncoder(id<MTL4CommandEncoder> encoder, NSError** error) const {
	if (!isInitialized()) {
		return fail(error, ErrorCode::InvalidState, @"Metal 4 argument tables are not initialized.");
	}
	if (@available(macOS 26.0, iOS 26.0, *)) {
		if (!encoder || !encoder.commandBuffer) {
			return fail(error, ErrorCode::InvalidEncoder, @"A live Metal 4 command encoder is required.");
		}
		if (encoder.commandBuffer.device != _device) {
			return fail(error, ErrorCode::WrongDevice, @"The encoder belongs to a different Metal device.");
		}
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 command encoding is unavailable.");
}

bool MVKMetal4ArgumentTables::bindRender(id<MTL4RenderCommandEncoder> encoder,
	                                    MTLRenderStages stages, NSError** error) {
	if (error) { *error = nil; }
	const MTLRenderStages supported = MTLRenderStageVertex | MTLRenderStageFragment;
	if (!stages || (stages & ~supported)) {
		return fail(error, ErrorCode::InvalidStages, @"Select only vertex and/or fragment argument tables.");
	}
	if (!validateEncoder(encoder, error)) { return false; }
	if ((stages & MTLRenderStageVertex) && !validateStage(Stage::Vertex, error)) { return false; }
	if ((stages & MTLRenderStageFragment) && !validateStage(Stage::Fragment, error)) { return false; }
	if (@available(macOS 26.0, iOS 26.0, *)) {
		if (stages & MTLRenderStageVertex) {
			if (!resolvePendingBindings(Stage::Vertex, error)) { return false; }
			[encoder setArgumentTable:_tables[static_cast<NSUInteger>(Stage::Vertex)] atStages:MTLRenderStageVertex];
		}
		if (stages & MTLRenderStageFragment) {
			if (!resolvePendingBindings(Stage::Fragment, error)) { return false; }
			[encoder setArgumentTable:_tables[static_cast<NSUInteger>(Stage::Fragment)] atStages:MTLRenderStageFragment];
		}
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 command encoding is unavailable.");
}

bool MVKMetal4ArgumentTables::bindCompute(id<MTL4ComputeCommandEncoder> encoder, NSError** error) {
	if (error) { *error = nil; }
	if (!validateEncoder(encoder, error) || !validateStage(Stage::Compute, error)) { return false; }
	if (@available(macOS 26.0, iOS 26.0, *)) {
		if (!resolvePendingBindings(Stage::Compute, error)) { return false; }
		[encoder setArgumentTable:_tables[static_cast<NSUInteger>(Stage::Compute)]];
		return true;
	}
	return fail(error, ErrorCode::Unsupported, @"Metal 4 command encoding is unavailable.");
}

id<MTL4ArgumentTable> MVKMetal4ArgumentTables::getTable(Stage stage, NSError** error) {
	if (error) { *error = nil; }
	if (!validateStage(stage, error) || !resolvePendingBindings(stage, error)) { return nil; }
	return _tables[static_cast<NSUInteger>(stage)];
}
