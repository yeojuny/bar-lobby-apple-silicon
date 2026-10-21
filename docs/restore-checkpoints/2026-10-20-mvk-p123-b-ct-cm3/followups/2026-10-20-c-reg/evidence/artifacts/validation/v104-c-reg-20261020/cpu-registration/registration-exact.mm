
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include "MVKMetal4TextureRegistrationCache.h"
#include "MVKMetal4PreparedResource.h"
#include <unordered_set>
#define main r50_preserved_r47_main
#include "metal4-r47-retirement-cpu.mm"
#undef main
enum MVKDescriptorBindingFlagBits {
	MVK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT           = VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT,
	MVK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT = VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT,
	MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT   = VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT,
	MVK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT             = VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT,
	MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS            = 0x0f,
	/** If set, this binding uses immutable samplers, stored on the descriptor set layout. */
	MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT     = 0x80,
};struct MVKMetal4DescriptorPreparationStamp {
	uint64_t incarnation;
	uint64_t revision;
	// The pool owns this storage. The descriptor/free-list union stays trivial.
	uint64_t* bindingRevisions;
	uint32_t bindingRevisionCount;
	bool individualCacheEligible;
	MVKMetal4PreparedBindingSnapshots* snapshots;

	static bool allowsBindingFlags(uint8_t flags) {
		return !(flags & (MVK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT |
		                  MVK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT |
		                  MVK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT));
	}
	static bool allowsGroupFlags(uint8_t flags) {
		return !(flags & (MVK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT |
		                  MVK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT));
	}
	static uint64_t allocateIncarnation(std::atomic<uint64_t>& next) {
		uint64_t value = next.load(std::memory_order_relaxed);
		while (value != UINT64_MAX) {
			if (next.compare_exchange_weak(value, value + 1, std::memory_order_relaxed)) {
				return value + 1;
			}
		}
		return 0;
	}
	void initialize(bool eligible, bool groupEligible = false) {
		incarnation = revision = 0;
		bindingRevisions = nullptr;
		bindingRevisionCount = 0;
		individualCacheEligible = eligible;
		snapshots = nullptr;
		if (!eligible && !groupEligible) { return; }
		static std::atomic<uint64_t> next{0};
		incarnation = allocateIncarnation(next);
		if (incarnation) { revision = 1; }
	}
	void updated() {
		if (revision) { revision = revision == UINT64_MAX ? 0 : revision + 1; }
	}
	void useBindingRevisions(uint64_t* values, uint32_t count) {
		bindingRevisions = values && count ? values : nullptr;
		bindingRevisionCount = bindingRevisions ? count : 0;
	}
	uint64_t bindingRevision(uint32_t binding) const {
		if (!individualCacheEligible || !incarnation || !revision) { return 0; }
		if (!bindingRevisions) { return revision; }
		return binding < bindingRevisionCount ? bindingRevisions[binding] : 0;
	}
	// Writes/copies can spill across successive bindings, including empty ones.
	// Track actual destination ranges before touching either CPU or GPU payload.
	template<class DescriptorCount>
	void updatedBindings(uint32_t binding, uint32_t start, uint32_t count,
	                     const DescriptorCount& descriptorCount) {
		if (!incarnation || !revision || !bindingRevisions || !count) { return; }
		uint64_t remaining = count, element = start;
		for (; binding < bindingRevisionCount; ++binding) {
			uint64_t size = descriptorCount(binding);
			if (element >= size) { element -= size; continue; }
			uint64_t written = std::min(remaining, size - element);
			uint64_t& value = bindingRevisions[binding];
			if (value) { value = value == UINT64_MAX ? 0 : value + 1; }
			remaining -= written;
			if (!remaining) { return; }
			element = 0;
		}
		// An unrepresentable range must never leave a stale preparation eligible.
		incarnation = revision = 0;
	}
};

// Only already validated and submission-retained buffer-only bindings may enter.
// The recording owner clears this bounded cache when its weak token changes.
class MVKMetal4DescriptorPreparationCache {
	struct Key {
		uint64_t incarnation;
		uint32_t binding;
		bool operator==(const Key& rhs) const { return incarnation == rhs.incarnation && binding == rhs.binding; }
	};
	struct Hash {
		size_t operator()(const Key& key) const {
			return std::hash<uint64_t>{}(key.incarnation) ^ (std::hash<uint32_t>{}(key.binding) << 1);
		}
	};
	struct Entry {
		uint64_t revision, generation;
		std::vector<MVKMetal4PreparedResourceProof> proofs;
	};
	std::unordered_map<Key, Entry, Hash> _bindings;
public:
	void clear() { _bindings.clear(); }
	template<class StableGeneration>
	bool matches(const MVKMetal4DescriptorPreparationStamp& stamp, uint32_t binding, uint64_t generation,
	             const StableGeneration& stableGeneration) {
		uint64_t revision = stamp.bindingRevision(binding);
		if (!generation || generation == UINT64_MAX || !stamp.incarnation || !revision) { return false; }
		auto it = _bindings.find({stamp.incarnation, binding});
		if (it == _bindings.end() || it->second.revision != revision) { return false; }
		if (it->second.generation == generation) { return true; }
		// Unproved/oversized bindings keep generation-only reuse. A miss never
		// discards another binding already retained in this recording.
		if (it->second.proofs.empty()) { return false; }
		for (const auto& proof : it->second.proofs) { if (!proof.valid()) { return false; } }
		if (generation != stableGeneration()) { return false; }
		it->second.generation = generation;
		return true;
	}
	void remember(const MVKMetal4DescriptorPreparationStamp& stamp, uint32_t binding, uint64_t generation,
	              std::vector<MVKMetal4PreparedResourceProof>&& proofs = {}) {
		uint64_t revision = stamp.bindingRevision(binding);
		if (!generation || generation == UINT64_MAX || !stamp.incarnation || !revision) { return; }
		if (proofs.size() > MVKMetal4PreparedBindingSnapshots::kMaxResources) { return; }
		for (const auto& proof : proofs) { if (!proof.valid()) { return; } }
		Key key{stamp.incarnation, binding};
		auto it = _bindings.find(key);
		if (it != _bindings.end()) { it->second = {revision, generation, std::move(proofs)}; }
		else if (_bindings.size() < 256) { _bindings.emplace(key, Entry{revision, generation, std::move(proofs)}); }
	}
};
class MVKCommandEncoder;
class MVKCommandEncoderState {
public:
	id<MTLRenderPipelineState> _metal4GraphicsPipeline = nil;
	id<MTLComputePipelineState> _metal4ComputePipeline = nil;
	bool _metal4GraphicsTablesBound = false;
	bool _metal4ComputeTableBound = false;
	// Exact Metal identities proved retained/resident by this recording. The
	// weak token also scopes revision-based descriptor preparation to this recording.
	std::weak_ptr<void> _metal4BindingRecordingToken;
	std::unordered_set<const void*> _metal4OwnedBuffers, _metal4OwnedObjects;
	MVKMetal4TextureRegistrationCache _metal4OwnedTextures;
	MVKMetal4DescriptorPreparationCache _metal4PreparedDescriptorBindings;
	MVKMetal4PreparedTextureBindingCache _metal4PreparedTextureBindings;
	MVKMetal4StagePreparation _metal4StagePreparation[kMVKShaderStageCount];
    bool prepareMetal4ResourceRegistration(MVKCommandEncoder&);
    bool registerMetal4Buffer(MVKCommandEncoder&, id<MTLBuffer>);
    bool registerMetal4Texture(MVKCommandEncoder&, id<MTLTexture>);
    bool retainMetal4Object(MVKCommandEncoder&, id);
};
struct Recording {
    std::shared_ptr<MVKMetal4Submission> batch;
    unsigned calls = 0;
    std::function<void()> afterRegistration;
    id<MTL4CommandBuffer> commandBuffer() const { return batch->commandBuffer(); }
    auto recordingToken() const { return batch->recordingToken(); }
    bool matchesRecordingToken(const std::weak_ptr<void>& token) const { return batch->matchesRecordingToken(token); }
    bool retainObject(id object, NSError** error) { return batch->retainObject(object, error); }
    bool addResource(id<MTLResource> object, NSError** error) {
        ++calls;
        bool okay = batch->addResource(object, error);
        if (okay && afterRegistration) { auto hook = std::move(afterRegistration); hook(); }
        return okay;
    }
    bool addBufferResource(id<MTLBuffer> object, NSError** error) {
        ++calls;
        bool okay = batch->addBufferResource(object, error);
        if (okay && afterRegistration) { auto hook = std::move(afterRegistration); hook(); }
        return okay;
    }
    bool addTextureResource(id<MTLTexture> object, NSError** error) {
        ++calls;
        bool okay = batch->addTextureResource(object, error);
        if (okay && afterRegistration) { auto hook = std::move(afterRegistration); hook(); }
        return okay;
    }
};
class MVKCommandEncoder {
public:
    MVKCommandEncoderState state;
    Recording recording;
    bool failed = false;
    Recording* getMetal4Submission() { return recording.batch ? &recording : nullptr; }
    MVKCommandEncoderState& getState() { return state; }
    MVKMetal4ArgumentTables* getMetal4ArgumentTables() { return nullptr; }
    void failMetal4Encoding(const char*) { failed = true; }
};
using Metal4Stage = MVKMetal4ArgumentTables::Stage;
static bool metal4Failure(MVKCommandEncoder& encoder, const char* message) {
	encoder.failMetal4Encoding(message);
	return false;
}bool MVKCommandEncoderState::prepareMetal4ResourceRegistration(MVKCommandEncoder& encoder) {
	auto* submission = encoder.getMetal4Submission();
	if (!submission || !submission->commandBuffer()) {
		return metal4Failure(encoder, "Native resource binding requires a recording submission.");
	}
	if (!submission->matchesRecordingToken(_metal4BindingRecordingToken)) {
		_metal4OwnedBuffers.clear(); _metal4OwnedObjects.clear();
		_metal4OwnedTextures.clear();
		_metal4PreparedDescriptorBindings.clear(); _metal4PreparedTextureBindings.clear();
		for (auto& stage : _metal4StagePreparation) { stage = {}; }
		_metal4BindingRecordingToken = submission->recordingToken();
	}
	return true;
}

bool MVKCommandEncoderState::registerMetal4Buffer(MVKCommandEncoder& encoder, id<MTLBuffer> buffer) {
	if (!buffer) { return true; }
	const void* identity = (const void*)buffer;
	if (_metal4OwnedBuffers.count(identity)) { return true; }
	NSError* error = nil;
	if (!encoder.getMetal4Submission()->addBufferResource(buffer, &error)) {
		return metal4Failure(encoder, error ? error.localizedDescription.UTF8String : "Native buffer registration failed.");
	}
	// The successful registration pins this exact buffer through retirement.
	// Bound CPU storage is bounded by entry count; overflow uses the old path.
	if (_metal4OwnedBuffers.size() < 256) { _metal4OwnedBuffers.insert(identity); }
	return true;
}

bool MVKCommandEncoderState::registerMetal4Texture(MVKCommandEncoder& encoder, id<MTLTexture> texture) {
	if (!texture) { return true; }
	const void* identity = (const void*)texture;
	if (_metal4OwnedTextures.matchesOrdinary(identity)) { return true; }
	// Sample before registration: a concurrent registry mutation during or after
	// addResource must leave this memo stale, never falsely current.
	uint64_t generation = MVKMetal4Submission::drawableRegistrationGeneration(texture);
	if (_metal4OwnedTextures.matches(identity, generation)) { return true; }
	NSError* error = nil;
	if (!encoder.getMetal4Submission()->addTextureResource(texture, &error)) {
		return metal4Failure(encoder, error ? error.localizedDescription.UTF8String : "Native texture registration failed.");
	}
	if (!generation) { _metal4OwnedTextures.rememberOrdinary(identity); }
	else { _metal4OwnedTextures.remember(identity, generation); }
	return true;
}

bool MVKCommandEncoderState::retainMetal4Object(MVKCommandEncoder& encoder, id object) {
	if (!object) { return true; }
	const void* identity = (const void*)object;
	if (_metal4OwnedObjects.count(identity)) { return true; }
	NSError* error = nil;
	if (!encoder.getMetal4Submission()->retainObject(object, &error)) {
		return metal4Failure(encoder, error ? error.localizedDescription.UTF8String : "Native object retention failed.");
	}
	if (_metal4OwnedObjects.size() < 256) { _metal4OwnedObjects.insert(identity); }
	return true;
}struct Metal4BindingSink { MVKCommandEncoder& encoder; Metal4Stage stage;
bool resource(id<MTLTexture> value) {
		return encoder.getState().registerMetal4Texture(encoder, value);
	}
};
@interface R50Texture : R47Allocation {
@public R50Texture* parent; unsigned* deaths; unsigned* protocolChecks;
}
@end
@implementation R50Texture
- (BOOL)conformsToProtocol:(Protocol*)protocol {
    if (protocol == @protocol(MTLTexture) && protocolChecks) { ++*protocolChecks; }
    return protocol == @protocol(MTLTexture) || protocol == @protocol(MTLResource) || [super conformsToProtocol:protocol];
}
- (id<MTLHeap>)heap { return nil; }
- (id<MTLTexture>)parentTexture { return (id<MTLTexture>)parent; }
- (void)dealloc { if (deaths) { ++*deaths; } [parent release]; [super dealloc]; }
@end

@interface R50Buffer : R47Allocation {
@public unsigned* protocolChecks; unsigned* deaths;
}
@end
@implementation R50Buffer
- (BOOL)conformsToProtocol:(Protocol*)protocol {
    if (protocol == @protocol(MTLTexture) && protocolChecks) { ++*protocolChecks; }
    return protocol == @protocol(MTLBuffer) || protocol == @protocol(MTLResource) || [super conformsToProtocol:protocol];
}
- (id<MTLHeap>)heap { return nil; }
- (void)dealloc { if (deaths) { ++*deaths; } [super dealloc]; }
@end

static R50Texture* texture(R47Device* device, R50Texture* parent = nil) {
    auto* value = [R50Texture new]; value->device = (id<MTLDevice>)device;
    value->parent = [parent retain]; return value;
}
static void start(MVKCommandEncoder& encoder, MVKMetal4Queue& queue) {
    NSError* error = nil; encoder.recording.batch = queue.begin(&error); encoder.failed = false;
    require(encoder.recording.batch && encoder.state.prepareMetal4ResourceRegistration(encoder), "fresh recording prepared");
}
static void cancel(MVKCommandEncoder& encoder) {
    NSError* error = nil; require(encoder.recording.batch->end(&error), "end before cancellation");
    encoder.recording.batch.reset();
}
static void cacheBounds() {
    using Cache = MVKMetal4TextureRegistrationCache;
    static_assert(sizeof(Cache) == 4096, "fixed storage has no node allocation");
    Cache cache; const void* a = reinterpret_cast<void*>(16);
    require(!cache.matches(a, 1) && !cache.matches(nullptr, 1), "empty and nil miss");
    cache.remember(a, 0); cache.remember(a, UINT64_MAX);
    require(!cache.matches(a, 0) && !cache.matches(a, UINT64_MAX), "zero and saturated generations never admit");
    cache.remember(a, 1); require(cache.matches(a, 1) && !cache.matches(a, 2), "exact generation only");
    cache.clear(); require(!cache.matches(a, 1), "recording reset clears memo");
    for (uintptr_t i = 1; i <= 257; ++i) {
        const void* value = reinterpret_cast<void*>(i << 4);
        cache.remember(value, 3); require(cache.matches(value, 3), "exact object admitted after collision replacement");
    }
    unsigned hits = 0;
    for (uintptr_t i = 1; i <= 257; ++i) { hits += cache.matches(reinterpret_cast<void*>(i << 4), 3); }
    require(hits <= 256 && hits > 0, "bounded collisions only cause misses");
}
static void typedRegistrationEquivalence() {
    for (bool typed : {false, true}) {
        auto* device = [R47Device new]; auto* foreign = [R47Device new]; NSError* error = nil;
        auto residency = MVKMetal4DeviceResidency::create((id<MTLDevice>)device, &error);
        auto pool = MVKMetal4RecordingPool::create((id<MTLDevice>)device, &error, residency);
        require(bool(pool), "recording pool with actual residency implementation");
        auto batch = pool->begin(&error);
        unsigned bufferChecks = 0, textureChecks = 0, bufferDeaths = 0, textureDeaths = 0;
        auto* buffer = [R50Buffer new]; buffer->device = (id<MTLDevice>)device;
        buffer->protocolChecks = &bufferChecks; buffer->deaths = &bufferDeaths;
        auto* value = texture(device); value->protocolChecks = &textureChecks; value->deaths = &textureDeaths;
        auto addBuffer = [&](R50Buffer* b) { return typed ? batch->addBufferResource((id<MTLBuffer>)b, &error) : batch->addResource((id<MTLResource>)b, &error); };
        auto addTexture = [&](R50Texture* t) { return typed ? batch->addTextureResource((id<MTLTexture>)t, &error) : batch->addResource((id<MTLResource>)t, &error); };
        require(!addBuffer(nil) && error.code == 3 && !addTexture(nil) && error.code == 3, "nil rejects identically");
        auto* wrongBuffer = [R50Buffer new]; wrongBuffer->device = (id<MTLDevice>)foreign;
        auto* wrongTexture = texture(foreign);
        require(!addBuffer(wrongBuffer) && error.code == 3 && !addTexture(wrongTexture) && error.code == 3, "foreign device rejects identically");
        [wrongBuffer release]; [wrongTexture release];
        require(batch->retainObject(buffer, &error) && batch->retainObject(value, &error), "retain before registering");
        require(addBuffer(buffer) && !error && addTexture(value) && !error, "unregistered resources retain dynamic fallback");
        require(bufferChecks == unsigned(!typed) && textureChecks == unsigned(!typed), "generic classifies once through residency fallback; typed classifies zero times");
        require(addBuffer(buffer) && addTexture(value), "repeat registration succeeds");
        auto stats = batch->resourceRegistrationStats();
        require(stats.retainedObjects == 2 && stats.residentResources == 2 && stats.deviceResidencyLeases == 0, "types imply neither ownership nor residency");
        require(bufferChecks == unsigned(!typed) && textureChecks == unsigned(!typed), "resident hit does not classify again");
        auto second = pool->begin(&error);
        require(second->addBufferResource((id<MTLBuffer>)buffer, &error) && second->addTextureResource((id<MTLTexture>)value, &error), "second recording independently registers");
        require(second->resourceRegistrationStats().residentResources == 2, "recording resource ownership remains separate");
        require(batch->end(&error), "end registration batch");
        require(!addBuffer(buffer) && error.code == 3 && !addTexture(value) && error.code == 3, "ended recording rejects previously resident objects");
        [buffer release]; [value release]; batch.reset();
        require(bufferDeaths == 0 && textureDeaths == 0, "second recording retains after first cancellation");
        second.reset();
        require(bufferDeaths == 1 && textureDeaths == 1, "recording cancellation releases both resource kinds");
        // Unknown views must still acquire the registered parent's lease.
        auto* base = texture(device); auto* view = texture(device, base); unsigned viewChecks = 0; view->protocolChecks = &viewChecks;
        require(residency->registerAllocation((id<MTLAllocation>)base, &error), "register parent allocation");
        std::weak_ptr<void> lease = residency->lease((id<MTLResource>)view);
        require(!lease.expired() && viewChecks == 1, "public generic lease retains texture ancestry discovery");
        viewChecks = 0; batch = pool->begin(&error);
        require(addTexture(view) && viewChecks == unsigned(!typed), "known type reaches parent lookup without second classification");
        require(batch->resourceRegistrationStats().deviceResidencyLeases == 1, "view registration acquires parent lease");
        residency->unregisterAllocation((id<MTLAllocation>)base); [view release]; [base release];
        require(!lease.expired(), "parent lease survives allocation-owner release");
        batch.reset(); require(lease.expired(), "parent lease retires at cancellation");
        pool.reset(); residency.reset(); [foreign release]; [device release];
    }
}
static void reuseAndRecording() {
    auto* device = [R47Device new]; NSError* error = nil; auto queue = MVKMetal4Queue::create((id<MTLDevice>)device, &error);
    require(bool(queue), "CPU mock queue");
    MVKCommandEncoder encoder; start(encoder, *queue);
    Metal4BindingSink sink{encoder, Metal4Stage::Fragment};
    auto* value = texture(device); unsigned deaths = 0; value->deaths = &deaths;
    require(sink.resource(nil) && encoder.recording.calls == 0, "nil adds no registration");
    for (unsigned i = 0; i < 32; ++i) { require(sink.resource((id<MTLTexture>)value), "unchanged texture usable"); }
    require(encoder.recording.calls == 1 && encoder.recording.batch->resourceRegistrationStats().residentResources == 1,
            "32 unchanged binding fallbacks enter actual addResource once");
    require(encoder.state.prepareMetal4ResourceRegistration(encoder) && sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 1,
            "same recording preparation preserves reuse");
    auto old = encoder.recording.batch; cancel(encoder); start(encoder, *queue);
    require(sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 2, "new token re-registers even while old token survives");
    [value release]; require(deaths == 0, "actual submissions pin texture");
    cancel(encoder); require(deaths == 0, "older submission retains its own lifetime");
    old.reset(); require(deaths == 1, "memo does not own or prolong texture");
    require(!encoder.state.prepareMetal4ResourceRegistration(encoder) && encoder.failed, "missing recording rejects before reuse");
    start(encoder, *queue); require(encoder.recording.batch->end(&error), "end recording");
    require(!encoder.state.prepareMetal4ResourceRegistration(encoder) && encoder.failed, "ended recording cannot hit stale memo");
    encoder.recording.batch.reset(); queue.reset(); [device release];
}
static void drawableAndConcurrentMutation() {
    auto* device = [R47Device new]; NSError* error = nil; auto queue = MVKMetal4Queue::create((id<MTLDevice>)device, &error);
    MVKCommandEncoder encoder; start(encoder, *queue); Metal4BindingSink sink{encoder, Metal4Stage::Vertex};
    auto* base = texture(device); auto* view = texture(device, base);
    auto* first = [NSObject new]; auto* second = [NSObject new];
    require(sink.resource((id<MTLTexture>)view), "unregistered view first use");
    require(mvkRegisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)first, &error), "register base drawable");
    require(sink.resource((id<MTLTexture>)view) && encoder.recording.calls == 2 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 2, "generation change finds and retains view parent drawable");
    mvkUnregisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)first);
    require(mvkRegisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)second, &error), "replace drawable snapshot");
    require(sink.resource((id<MTLTexture>)view) && encoder.recording.calls == 3 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 3, "same texture now retains second drawable");
    mvkUnregisterMetal4Drawable((id<MTLTexture>)base, (id<MTLDrawable>)second);
    require(sink.resource((id<MTLTexture>)view) && encoder.recording.calls == 4, "drawable removal invalidates memo");
    auto* raced = texture(device);
    encoder.recording.afterRegistration = [&] { require(mvkRegisterMetal4Drawable((id<MTLTexture>)raced, (id<MTLDrawable>)first, &error), "mutation after registration"); };
    require(sink.resource((id<MTLTexture>)raced) && encoder.recording.calls == 5, "first registration with mutation hook");
    require(sink.resource((id<MTLTexture>)raced) && encoder.recording.calls == 6 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 4, "pre-call generation cannot hide concurrent drawable addition");
    require(sink.resource((id<MTLTexture>)raced) && encoder.recording.calls == 6, "revalidated generation reuses safely");
    mvkUnregisterMetal4Drawable((id<MTLTexture>)raced, (id<MTLDrawable>)first);
    [first release]; [second release]; [base release]; [view release]; [raced release];
    cancel(encoder); queue.reset(); [device release];
}
static void failuresAndSaturation() {
    auto* device = [R47Device new]; auto* foreign = [R47Device new]; NSError* error = nil;
    auto queue = MVKMetal4Queue::create((id<MTLDevice>)device, &error);
    MVKCommandEncoder encoder; start(encoder, *queue); Metal4BindingSink sink{encoder, Metal4Stage::Fragment};
    auto* value = texture(foreign);
    require(!sink.resource((id<MTLTexture>)value) && encoder.failed && encoder.recording.calls == 1,
            "wrong device rejects with original failure");
    require(!sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 2 &&
            encoder.recording.batch->resourceRegistrationStats().retainedObjects == 0, "failed registration never admits a cache hit");
    [value release]; value = texture(device);
    auto before = drawableRegistryGeneration.load();
    drawableRegistryGeneration.store(UINT64_MAX, std::memory_order_release);
    require(sink.resource((id<MTLTexture>)value) && sink.resource((id<MTLTexture>)value) && encoder.recording.calls == 4,
            "saturated generation keeps original registration on every use");
    require(encoder.recording.batch->resourceRegistrationStats().drawableRegistryLookups == 2, "saturation still rechecks drawable ancestry");
    [value release]; cancel(encoder); queue.reset(); [device release]; [foreign release];
    drawableRegistryGeneration.store(before, std::memory_order_release); // Isolated test fixture only.
}
int main() {
    @autoreleasepool {
        try {
            cacheBounds(); typedRegistrationEquivalence(); reuseAndRecording(); drawableAndConcurrentMutation(); failuresAndSaturation();
            require(drawableRegistry.empty(), "fixture leaves no registered drawables");
            std::printf("{\"passed\":true,\"assertions\":%u,\"unchangedBindingUses\":32,\"actualRegistrationCalls\":1}\n", assertions);
            return 0;
        } catch (const std::exception& error) {
            std::fprintf(stderr, "r50 CPU registration assertion failed: %s\n", error.what()); return 1;
        }
    }
}
