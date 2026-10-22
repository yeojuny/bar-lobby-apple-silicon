/*
 * MVKMetal4ArgumentTable.h
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

#import <Metal/Metal.h>
#include <vector>
#include <memory>

class MVKMetal4Submission;

extern NSString* const MVKMetal4ArgumentTableErrorDomain;

/**
 * Native Metal 4 root bindings for the existing vertex, fragment and compute ABI.
 * This helper does not modify argument-buffer payloads or allocate inline bytes.
 * Upload data must already reside in a submission-owned MTLBuffer.
 *
 * All methods and destruction require external serialization. The helper owns its
 * device and initialized tables using manual reference counting. setBytes also
 * retains its cached immutable uploads and current binding objects. Holding each
 * current object makes its immutable device/address/ID metadata reusable without
 * an object-address ABA. This is only CPU binding-cache ownership; the submitting
 * owner must still retain and
 * make resident those resources, including resources reached through argument
 * buffers, for the complete GPU lifetime. It must also keep the tables alive
 * until submission completion, either by keeping this helper alive or retaining
 * the +0 references returned by getTable().
 *
 * SDK MTL4RenderCommandEncoder.h / MTL4ComputeCommandEncoder.h specify that table
 * bindings are snapshotted at draw, dispatch and execute, not at setArgumentTable.
 * Thus setters affect subsequent encoded work. This does not extend the lifetime
 * of an underlying resource, nor permit unsynchronized concurrent table edits.
 * This class is not connected to the legacy command encoder path.
 */
class API_AVAILABLE(macos(26.0), ios(26.0)) MVKMetal4ArgumentTables {
public:

	enum class Stage : NSUInteger { Vertex, Fragment, Compute, Count };

	/** SDK ceilings, not inferred device capabilities. Callers may request less. */
	struct Limits {
		NSUInteger bufferCount = 31;
		NSUInteger textureCount = 128;
		NSUInteger samplerCount = 16;
	};

	enum class ErrorCode : NSInteger {
		Unsupported = 1,
		InvalidState,
		InvalidStage,
		InvalidLimits,
		InvalidIndex,
		InvalidBufferRange,
		WrongDevice,
		AllocationFailed,
		InvalidEncoder,
		InvalidStages,
		InvalidResource,
	};

	MVKMetal4ArgumentTables() = default;
	~MVKMetal4ArgumentTables();
	MVKMetal4ArgumentTables(const MVKMetal4ArgumentTables&) = delete;
	MVKMetal4ArgumentTables& operator=(const MVKMetal4ArgumentTables&) = delete;
	MVKMetal4ArgumentTables(MVKMetal4ArgumentTables&&) = delete;
	MVKMetal4ArgumentTables& operator=(MVKMetal4ArgumentTables&&) = delete;

	/**
	 * Initializes all three tables atomically; initial entries are explicitly nil.
	 * Failure leaves the helper uninitialized and reusable. A successful instance
	 * cannot be initialized again. Zero-sized slot classes are passed through to
	 * Metal (the SDK specifies maxima, not a positive minimum); any device rejection
	 * is returned as an allocation error, never clamped or silently ignored.
	 */
	[[nodiscard]] bool initialize(id<MTLDevice> device, const Limits& limits,
	                              NSError** error = nullptr);
	/** Initializes only Compute, with the same atomic failure contract as initialize(). */
	[[nodiscard]] bool initializeCompute(id<MTLDevice> device, const Limits& limits,
	                                     NSError** error = nullptr);
	/**
	 * Clears every entry in an initialized stage before reusing it for a helper.
	 * Already encoded draws/dispatches keep their snapshots. Referenced resources
	 * still require submission lifetime ownership after their entries are cleared.
	 */
	[[nodiscard]] bool clearBindings(Stage stage, NSError** error = nullptr);
	/** Required after direct mutation through getTable(); saved byte uploads remain usable. */
	[[nodiscard]] bool invalidateCachedBindings(Stage stage, NSError** error = nullptr);
	/**
	 * Begins a fresh logical lease after all CPU encoders using this primary lease
	 * have ended. Physical values survive until the next stage bind: setters claim
	 * their slots, then binding clears any unclaimed old slots before encoded work
	 * can snapshot them. Encoded commands keep their earlier snapshots. The owner
	 * must keep this wrapper and every referenced resource alive until retirement.
	 * Cached immutable uploads and recording identity remain usable in this SAME
	 * recording; no allocator reset, resource release or GPU wait occurs here.
	 */
	[[nodiscard]] bool resetBindingsForNextEncoder(NSError** error = nullptr);
	/**
	 * Clears all initialized stages and drops every cached upload/token before a
	 * retired table lease is reused. The owner must prove prior GPU retirement and
	 * exclusive access; this method does not wait for or establish either fact.
	 * Small host-byte vector capacities survive, with a 64 KiB total bound. Their
	 * former bytes are never reused across recordings. Metal tables stay allocated.
	 */
	[[nodiscard]] bool resetForReuse(NSError** error = nullptr);

	/**
	 * Bind buffer.gpuAddress + offset without changing the shader binding index.
	 * nil with zero offset explicitly clears the entry. offset == buffer.length
	 * denotes zero accessible bytes; the caller still owns shader bounds metadata
	 * and must not issue an access beyond the available range.
	 */
	[[nodiscard]] bool setBuffer(Stage stage, id<MTLBuffer> buffer, NSUInteger offset,
	                             NSUInteger index, NSError** error = nullptr);
	/**
	 * Supplies an actual dynamic attribute stride; it must match the caller's
	 * vertex descriptor. Apple7+ permits byte alignment and specifies no fixed
	 * maximum stride (Metal feature tables); zero stride is not rejected here.
	 * This helper requires both offset and stride to be zero for a nil-buffer
	 * clear, so clearing cannot silently preserve a requested nonzero stride.
	 */
	[[nodiscard]] bool setBufferWithStride(Stage stage, id<MTLBuffer> buffer,
	                                       NSUInteger offset, NSUInteger stride,
	                                       NSUInteger index, NSError** error = nullptr);
	/**
	 * Uploads immutable bytes, reusing the last byte-identical upload for this slot.
	 * The cache is scoped to one submission recording token. A new submission
	 * discards cached bytes even if pooled storage has the same object/address;
	 * arena contents cease being immutable at the prior GPU retirement.
	 * Buffer/table setters may overwrite the slot without invalidating the saved
	 * bytes: the next call restores that exact upload into the actual table slot.
	 */
	[[nodiscard]] bool setBytes(Stage stage, const void* data, NSUInteger length,
	                            NSUInteger index, MVKMetal4Submission& submission,
	                            NSError** error = nullptr);
	/**
	 * A nil texture or sampler explicitly clears the corresponding root entry.
	 * A non-nil resource must expose a nonzero GPU resource ID. The caller must
	 * create sampler states suitable for GPU-addressed argument binding.
	 */
	[[nodiscard]] bool setTexture(Stage stage, id<MTLTexture> texture, NSUInteger index,
	                              NSError** error = nullptr);
	[[nodiscard]] bool setSampler(Stage stage, id<MTLSamplerState> sampler, NSUInteger index,
	                              NSError** error = nullptr);

	/**
	 * Applies complete stored tables to the selected vertex/fragment stages.
	 * The stage mask must be nonempty and contain only those two stages. Unselected
	 * stages are untouched. Clear an individual entry using a nil setter above;
	 * these methods do not detach tables or clear existing stored entries.
	 */
	[[nodiscard]] bool bindRender(id<MTL4RenderCommandEncoder> encoder, MTLRenderStages stages,
	                              NSError** error = nullptr);
	[[nodiscard]] bool bindCompute(id<MTL4ComputeCommandEncoder> encoder,
	                               NSError** error = nullptr);

	/**
	 * Returns a borrowed (+0) table after resolving pending logical nils. Direct
	 * edits require invalidateCachedBindings(); keep this call before those edits.
	 */
	[[nodiscard]] id<MTL4ArgumentTable> getTable(Stage stage, NSError** error = nullptr);
	/** Exact physical/logical slot generation; zero means invalid or uncacheable. */
	uint64_t bufferBindingRevision(Stage stage, NSUInteger index) const;
	bool isInitialized() const { return _device != nil; }
	const Limits& getLimits() const { return _limits; }
	/** Exact initialized stages for the lease pool key; zero when uninitialized. */
	NSUInteger getStageMask() const;
	/** Host cache capacity only; the SDK does not expose native table allocation size. */
	uint64_t retainedHostByteCapacity() const;
	/** Serialized encoding counters, used to verify actual setter/upload reuse. */
	uint64_t getBindingWriteCount() const { return _bindingWriteCount; }
	uint64_t getByteUploadCount() const { return _byteUploadCount; }

private:
	struct BufferSlot;
	bool initializeStages(id<MTLDevice> device, const Limits& limits, NSUInteger stageMask,
	                      NSError** error);
	static bool fail(NSError** error, ErrorCode code, NSString* description);
	bool validateStage(Stage stage, NSError** error) const;
	bool validateSlot(Stage stage, NSUInteger index, NSUInteger count, NSError** error) const;
	bool getBufferAddress(id<MTLBuffer> buffer, NSUInteger offset, MTLGPUAddress& address,
	                      BufferSlot& slot, NSError** error) const;
	bool validateEncoder(id<MTL4CommandEncoder> encoder, NSError** error) const;
	void discardByteUploads(bool boundHostCapacity);
	bool resolvePendingBindings(Stage stage, NSError** error);
	bool clearBindingSlots(Stage stage, uint32_t buffers, const uint64_t* textures,
	                       uint32_t samplers, NSError** error);
	void invalidateBufferRevisions(NSUInteger stage);

	id<MTLDevice> _device = nil;
	id<MTL4ArgumentTable> _tables[static_cast<NSUInteger>(Stage::Count)] = {};
	Limits _limits;
	struct BufferSlot {
		MTLGPUAddress address = 0;
		NSUInteger stride = 0;
		bool known = false;
		bool withStride = false;
		id<MTLBuffer> resource = nil;
		MTLGPUAddress baseAddress = 0;
		NSUInteger length = 0;
	};
	struct ResourceSlot { uint64_t resourceID = 0; bool known = false; id resource = nil; };
	struct ByteUpload {
		std::vector<uint8_t> bytes;
		id<MTLBuffer> buffer = nil;
		NSUInteger offset = 0;
	};
	BufferSlot _buffers[3][31] = {};
	ResourceSlot _textures[3][128] = {};
	ResourceSlot _samplers[3][16] = {};
	// Only wrapper writes or explicitly invalidated slots need retirement clearing.
	uint32_t _dirtyBuffers[3] = {};
	uint64_t _dirtyTextures[3][2] = {};
	uint32_t _dirtySamplers[3] = {};
	// Old physical values not yet claimed by a setter in the fresh logical lease.
	// Stage binding (and raw table exposure) clears only these remaining entries.
	uint32_t _pendingBuffers[3] = {};
	uint64_t _pendingTextures[3][2] = {};
	uint32_t _pendingSamplers[3] = {};
	uint64_t _bufferBindingRevisions[3][31] = {};
	ByteUpload _byteUploads[3][31];
	std::weak_ptr<void> _byteUploadRecordingToken;
	uint64_t _bindingWriteCount = 0;
	uint64_t _byteUploadCount = 0;
};
