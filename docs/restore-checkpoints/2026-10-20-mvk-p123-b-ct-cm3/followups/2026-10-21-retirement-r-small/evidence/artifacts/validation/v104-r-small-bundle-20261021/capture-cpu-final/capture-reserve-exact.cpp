
#include "capture-prepared.h"
#include <vulkan/vulkan.h>
#include <atomic>
#include <mutex>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <stdexcept>
#include <algorithm>
using id=const void*;
constexpr id nil=nullptr;
static bool counting=false;
static size_t allocations=0,allocationBytes=0;
void* operator new(size_t size){void*p=std::malloc(size?size:1);if(!p)throw std::bad_alloc();if(counting){++allocations;allocationBytes+=size;}return p;}
void operator delete(void*p)noexcept{std::free(p);}
void* operator new[](size_t n){return ::operator new(n);}
void operator delete[](void*p)noexcept{::operator delete(p);}
class FixtureLiveList {
public:
    using Lock=std::mutex;
    struct Group {Lock lock;std::unordered_map<id,uint32_t> entries;std::unordered_map<id,MVKMetal4PreparedResourceIdentity> preparationIdentities;std::unordered_map<id,std::shared_ptr<void>> membershipIdentities;};
    Group groups[16];std::atomic<uint64_t> _generation{1};
    Group* getGroup(id object){return &groups[(reinterpret_cast<uintptr_t>(object)>>4)%16];}
    struct IsLiveResult {Lock*lock;bool value;IsLiveResult(Lock*l,bool v):lock(l),value(v){};IsLiveResult(IsLiveResult&&)=delete;~IsLiveResult(){lock->unlock();}operator bool()const{return value;}};
    IsLiveResult isLive(id object){auto*g=getGroup(object);g->lock.lock();return {&g->lock,g->entries.count(object)!=0};}
    void add(id);void remove(id);void advanceGeneration();void addPrepared(id,const MVKMetal4PreparedResourceProof*parent=nullptr);
    MVKMetal4PreparedResourceProof preparationProof(id,const IsLiveResult&);
    MVKMetal4PreparedResourceProof membershipProof(id,const IsLiveResult&);
    uint64_t generation()const{return _generation.load(std::memory_order_acquire);}
};
void FixtureLiveList::add(id object) {
	Group* group = getGroup(object);
	std::lock_guard<Lock> guard(group->lock);
	if (group->entries[object]++ == 0) { advanceGeneration(); }
	// Unknown/imported/alias registrations cannot inherit an earlier proof.
	group->preparationIdentities.erase(object);
}

void FixtureLiveList::remove(id object) {
	Group* group = getGroup(object);
	std::lock_guard<Lock> guard(group->lock);
	auto it = group->entries.find(object);
	if (it == group->entries.end())
		return;
	if (it->second <= 1) {
		group->preparationIdentities.erase(object);
		group->membershipIdentities.erase(object);
		group->entries.erase(it);
		advanceGeneration();
	} else {
		it->second--;
	}
}

void FixtureLiveList::advanceGeneration() {
	// Different groups mutate concurrently; one saturated atomic sequence covers
	// the complete list. Caller holds the affected membership group's lock.
	uint64_t current = _generation.load(std::memory_order_relaxed);
	while (current != UINT64_MAX && !_generation.compare_exchange_weak(current, current + 1,
			std::memory_order_release, std::memory_order_relaxed)) {}
}
void FixtureLiveList::addPrepared(id object, const MVKMetal4PreparedResourceProof* parent) {
	Group* group = getGroup(object);
	std::lock_guard<Lock> guard(group->lock);
	bool first = group->entries[object]++ == 0;
	if (first) { advanceGeneration(); }
	bool eligible = object && (!parent || (parent->valid() && parent->count < MVKMetal4PreparedResourceProof::kMaxOwners));
	if (!eligible) { group->preparationIdentities.erase(object); return; }
	// Never promote an object already registered by an unproved owner. Metal may
	// return the same immutable native object for multiple Vulkan owners.
	if (first) {
		MVKMetal4PreparedResourceIdentity identity;
		if (parent) { identity.parents = *parent; }
		group->preparationIdentities.emplace(object, std::move(identity));
	}
}

MVKMetal4PreparedResourceProof FixtureLiveList::preparationProof(id object, const IsLiveResult& guard) {
	Group* group = getGroup(object);
	if (!object || !guard.value || guard.lock != &group->lock) { return {}; }
	// The caller's original live guard already holds this exact group lock.
	auto it = group->preparationIdentities.find(object);
	return it == group->preparationIdentities.end() ? MVKMetal4PreparedResourceProof{} : it->second.proof();
}

MVKMetal4PreparedResourceProof FixtureLiveList::membershipProof(id object, const IsLiveResult& guard) {
	Group* group = getGroup(object);
	if (!object || !guard.value || guard.lock != &group->lock) { return {}; }
	// The original live guard pins this exact membership through fresh submission
	// retention. Final removal expires the token; same-address re-add gets a new
	// control block. Shared native owners preserve membership until final removal.
	auto it = group->membershipIdentities.find(object);
	if (it == group->membershipIdentities.end()) {
		if (group->entries.find(object) == group->entries.end()) { return {}; }
		it = group->membershipIdentities.emplace(object, std::make_shared<uint8_t>(0)).first;
	}
	MVKMetal4PreparedResourceProof proof;
	proof.owners[0] = it->second;
	proof.count = 1;
	return proof;
}

enum MVKDescriptorBindingFlagBits {
	MVK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT           = VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT,
	MVK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT = VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT,
	MVK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT   = VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT,
	MVK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT             = VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT,
	MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS            = 0x0f,
	/** If set, this binding uses immutable samplers, stored on the descriptor set layout. */
	MVK_DESCRIPTOR_BINDING_USES_IMMUTABLE_SAMPLERS_BIT     = 0x80,
};
struct MVKMetal4DescriptorPreparationStamp {
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
struct MVKMetal4DescriptorPreparationCache {
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
using Snapshots=MVKMetal4PreparedBindingSnapshots;
using Group=MVKMetal4PreparedGroupSnapshot;
enum class MVKDescriptorCPULayout {Normal,InlineData};
struct Counts {uint32_t buffer=0,texture=0,sampler=0;};
struct Binding {
    uint32_t n=0,cpuOffset=0,immSamplerIndex=0;Counts perDescriptorResourceCount;
    MVKDescriptorCPULayout cpuLayout=MVKDescriptorCPULayout::Normal;
    uint32_t getDescriptorCount(uint32_t)const{return n;}bool hasImmutableSamplers()const{return false;}
};
struct DummySampler {id getMTLSamplerState(){return nil;}};
struct Layout {std::array<Binding,1>b;std::array<DummySampler*,0>s;auto&bindings(){return b;}auto&immutableSamplers(){return s;}};
struct PipelineLayout {Layout*l;size_t getDescriptorSetCount(){return 1;}Layout*getDescriptorSetLayout(size_t){return l;}};
struct Set {Layout*layout;uint32_t variableDescriptorCount=0,cpuBufferSize=0;char*cpuBuffer=nullptr;MVKMetal4DescriptorPreparationStamp metal4Preparation{};};
struct Resources {struct {struct {bool get(size_t){return true;}} descriptorSetData;} resources;};
struct Common {PipelineLayout*_layout;std::array<Set*,1>_descriptorSets;};
struct Used {uint32_t set=0,bindingIdx=0;};
struct Stats {uint64_t textureBindingVisits=0,textureCacheEligible=0,textureCacheHits=0,textureHitResourceSlots=0,textureCacheMisses=0,textureProofAttempts=0,textureNegativeMemoSkips=0,textureProofReady=0,textureProofRejected=0;};
constexpr size_t kMVKMaxDescriptorSetCount=16;
static thread_local size_t fixtureStride=sizeof(id);
size_t descriptorCPUSize(MVKDescriptorCPULayout){return fixtureStride;}
struct MVKMetal4Submission {static uint64_t drawableRegistrationGeneration(id){return 0;}};
struct LiveResources {FixtureLiveList buffers,textures,samplers;auto isLive(id v){return samplers.isLive(v);}};
struct State {
    MVKMetal4DescriptorPreparationCache buffers;MVKMetal4PreparedTextureBindingCache textures;
    auto&metal4DescriptorPreparationCache(){return buffers;}auto&metal4TexturePreparationCache(){return textures;}
};
struct Device {LiveResources live;auto&getLiveResources(){return live;}};
struct Encoder {State state;Device device;auto&getState(){return state;}auto*getDevice(){return &device;}};
struct Trace {id value;unsigned kind;bool operator==(const Trace&r)const{return value==r.value&&kind==r.kind;}};
struct Metal4BindingSink {
    Encoder encoder;std::array<Trace,128>trace{};size_t traceCount=0;size_t failAt=0;
    bool add(id v,unsigned kind){trace[traceCount++]={v,kind};return traceCount!=failAt;}
    bool bufferResource(id v){return add(v,0);}bool resource(id v){return add(v,1);}bool object(id v){return add(v,2);}
};
static bool metal4Failure(Encoder&,const char*){return false;}
struct Env {
    Layout layout;PipelineLayout pipeline{&layout};Set set{&layout};Common common{&pipeline,{&set}};
    Resources resources;Used used;Metal4BindingSink sink;Snapshots snapshots;
    std::array<id,40>payload{};std::vector<Snapshots::Resource>groupResources;
    bool captureBinding=false;uint64_t capturedRevision=0;
    struct Observation {size_t inserts=0,growth=0,maxCapacity=0;const void*data=nullptr;size_t capacity=0;};
    std::array<Observation,3>observed{};
    unsigned mode;size_t n;
    Env(unsigned mode_,size_t n_,bool snapshotsOn=true):mode(mode_),n(n_){
        auto&b=layout.b[0];b.n=n;
        if(mode==0)b.perDescriptorResourceCount.buffer=1;
        if(mode==1||mode==3)b.perDescriptorResourceCount.texture=1;
        if(mode==2||mode==3)b.perDescriptorResourceCount.sampler=1;
        set.metal4Preparation.initialize(true);set.metal4Preparation.incarnation=7;
        set.metal4Preparation.snapshots=snapshotsOn?&snapshots:nullptr;
        fixtureStride=sizeof(id)*(mode==3?2:1);
        for(size_t i=0;i<n*(mode==3?2:1);++i){
            payload[i]=reinterpret_cast<id>((i+1)*16);
            auto&l=list(i);l.addPrepared(payload[i]);auto guard=l.isLive(payload[i]);l.membershipProof(payload[i],guard);
        }
        set.cpuBuffer=reinterpret_cast<char*>(payload.data());set.cpuBufferSize=n*fixtureStride;
    }
    FixtureLiveList&list(size_t i){return mode==0?sink.encoder.device.live.buffers:mode==2||(mode==3&&i%2)?sink.encoder.device.live.samplers:sink.encoder.device.live.textures;}
    Snapshots::Kind kind(size_t i){return mode==0?Snapshots::Kind::Buffer:mode==2||(mode==3&&i%2)?Snapshots::Kind::Sampler:Snapshots::Kind::Texture;}
    MVKMetal4PreparedResourceProof proof(size_t i){auto&l=list(i);auto guard=l.isLive(payload[i]);return mode==0?l.membershipProof(payload[i],guard):l.preparationProof(payload[i],guard);}
    void preseed(){
        std::vector<Snapshots::Resource>v;
        for(size_t i=0;i<n*(mode==3?2:1);++i)v.push_back({payload[i],kind(i),proof(i),true});
        snapshots.remember(0,1,std::move(v));
    }
    void resetObservation(){observed={};sink.traceCount=0;capturedRevision=0;}
};
template<class V>void observe(Env&e,size_t which,const V&v){
    auto&o=e.observed[which];++o.inserts;if(o.capacity!=v.capacity())++o.growth;
    o.capacity=v.capacity();o.maxCapacity=std::max(o.maxCapacity,v.capacity());o.data=v.data();
}
static MVKMetal4PreparedBindingSnapshots::Result replayMetal4Resource(
        Metal4BindingSink& sink, const MVKMetal4PreparedBindingSnapshots::Resource& resource) {
	using Snapshots = MVKMetal4PreparedBindingSnapshots;
	auto& liveResources = sink.encoder.getDevice()->getLiveResources();
	id value = (id)resource.identity;
	// Keep the same live guard through identity validation and submission retain.
	// Comparing weak owners under that guard also rejects native-address reuse.
	if (resource.kind == Snapshots::Kind::Buffer) {
		auto live = liveResources.buffers.isLive(value);
		if (!live || !resource.proof.matches(liveResources.buffers.membershipProof(value, live))) { return Snapshots::Result::Miss; }
		return sink.bufferResource(value) ? Snapshots::Result::Hit : Snapshots::Result::Failed;
	}
	if (resource.kind == Snapshots::Kind::Texture) {
		auto live = liveResources.textures.isLive(value);
		if (!live || !resource.proof.matches(liveResources.textures.preparationProof(value, live))) { return Snapshots::Result::Miss; }
		return sink.resource(value) ? Snapshots::Result::Hit : Snapshots::Result::Failed;
	}
	auto live = liveResources.samplers.isLive(value);
	if (!live || !resource.proof.matches(liveResources.samplers.preparationProof(value, live))) { return Snapshots::Result::Miss; }
	return sink.object(value) ? Snapshots::Result::Hit : Snapshots::Result::Failed;
}
bool run_reference(Env&e){auto&common=e.common;auto&resources=e.resources;auto&used=e.used;auto&sink=e.sink;auto&liveResources=sink.encoder.device.live;Stats*stats=nullptr;auto&groupResources=e.groupResources;const size_t groupStart=groupResources.size();auto&captureBinding=e.captureBinding;auto&capturedRevision=e.capturedRevision;auto appendGroupBinding=[&](const MVKMetal4DescriptorPreparationStamp&stamp,uint32_t binding,uint64_t revision){if(captureBinding&&(!stamp.snapshots||!stamp.snapshots->append(binding,revision,groupResources,Group::kMaxResources)))captureBinding=false;};
auto prepareCurrentPayload = [&]() -> bool {
					if (used.set >= common._layout->getDescriptorSetCount() || used.set >= kMVKMaxDescriptorSetCount ||
					    !resources.resources.descriptorSetData.get(used.set) || !common._descriptorSets[used.set]) {
						return metal4Failure(sink.encoder, "Native indirect binding has no argument-buffer root.");
					}
					auto* set = common._descriptorSets[used.set];
					auto* layout = common._layout->getDescriptorSetLayout(used.set);
					if (used.bindingIdx >= layout->bindings().size()) { return metal4Failure(sink.encoder, "Native indirect binding is outside its layout."); }
					const auto& binding = layout->bindings()[used.bindingIdx];
					uint32_t count = binding.getDescriptorCount(set->variableDescriptorCount);
					const auto& counts = binding.perDescriptorResourceCount;
					if (stats && count && (counts.texture || counts.sampler)) { ++stats->textureBindingVisits; }
					auto& preparation = sink.encoder.getState().metal4DescriptorPreparationCache();
					uint64_t bindingRevision = set->metal4Preparation.bindingRevision(used.bindingIdx);
					capturedRevision = bindingRevision;
					// Layout identity is only an eligibility check; cache identity is a fresh
					// pool incarnation + binding + revision, never a descriptor-set pointer.
					bool cacheEligible = set->layout == layout && set->metal4Preparation.incarnation &&
					                     bindingRevision && count && counts.buffer == 1 &&
					                     !counts.texture && !counts.sampler && !binding.hasImmutableSamplers();
					uint64_t generation = cacheEligible ? liveResources.buffers.generation() : UINT64_MAX;
					if (cacheEligible && preparation.matches(set->metal4Preparation, used.bindingIdx, generation,
						[&] { return liveResources.buffers.generation(); })) {
						appendGroupBinding(set->metal4Preparation, used.bindingIdx, bindingRevision);
						return true;
					}
					bool allBuffersLive = cacheEligible;
					bool allBuffersProven = cacheEligible && count <= Snapshots::kMaxResources;
					std::vector<MVKMetal4PreparedResourceProof> bufferProofs;
					auto& texturePreparation = sink.encoder.getState().metal4TexturePreparationCache();
					bool textureCacheEligible = set->layout == layout && set->metal4Preparation.incarnation &&
					                            bindingRevision && count && !counts.buffer &&
					                            (counts.texture || counts.sampler) && !binding.hasImmutableSamplers() &&
					                            uint64_t(count) * (counts.texture + counts.sampler) <= MVKMetal4PreparedTextureBindingCache::kMaxResources;
					if (textureCacheEligible) {
						if (stats) { ++stats->textureCacheEligible; }
						auto textureLookup = texturePreparation.lookup(set->metal4Preparation.incarnation,
							bindingRevision, used.bindingIdx);
						if (textureLookup == MVKMetal4PreparedTextureBindingCache::Result::Hit) {
							if (stats) {
								++stats->textureCacheHits;
								stats->textureHitResourceSlots += uint64_t(count) * (counts.texture + counts.sampler);
							}
							appendGroupBinding(set->metal4Preparation, used.bindingIdx, bindingRevision);
							return true;
						}
						if (stats) { ++stats->textureCacheMisses; }
						textureCacheEligible = textureLookup == MVKMetal4PreparedTextureBindingCache::Result::Attempt;
						if (stats) {
							if (textureCacheEligible) { ++stats->textureProofAttempts; }
							else { ++stats->textureNegativeMemoSkips; }
						}
					}
					std::vector<MVKMetal4PreparedResourceProof> textureProofs;
					bool allTexturesProven = textureCacheEligible;
					uint64_t resourceCount = uint64_t(count) * (counts.buffer + counts.texture + counts.sampler);
					bool snapshotEligible = bindingRevision && set->metal4Preparation.snapshots &&
					                        set->layout == layout && resourceCount && resourceCount <= Snapshots::kMaxResources &&
					                        binding.cpuLayout != MVKDescriptorCPULayout::InlineData && !binding.hasImmutableSamplers();
					uint64_t snapshotGeneration = liveResources.buffers.generation();
					if (snapshotEligible) {
						auto result = set->metal4Preparation.snapshots->replay(used.bindingIdx, bindingRevision,
							[&](const Snapshots::Resource& resource) {
								auto result = replayMetal4Resource(sink, resource);
								if (result == Snapshots::Result::Hit && allTexturesProven) { textureProofs.push_back(resource.proof); observe(e,1,textureProofs); }
								if (result == Snapshots::Result::Hit && allBuffersProven &&
								    resource.kind == Snapshots::Kind::Buffer) { bufferProofs.push_back(resource.proof); observe(e,0,bufferProofs); }
								if (result == Snapshots::Result::Hit && captureBinding) {
									if (groupResources.size() < Group::kMaxResources) { groupResources.push_back(resource); }
									else { captureBinding = false; }
								}
								return result;
							});
						if (result == Snapshots::Result::Failed) { return false; }
						if (result == Snapshots::Result::Hit) {
							if (cacheEligible && snapshotGeneration == liveResources.buffers.generation()) {
								if (!allBuffersProven || bufferProofs.size() != count) { bufferProofs.clear(); }
								preparation.remember(set->metal4Preparation, used.bindingIdx, snapshotGeneration, std::move(bufferProofs));
							}
							if (allTexturesProven) { texturePreparation.remember(set->metal4Preparation.incarnation,
								bindingRevision, used.bindingIdx, std::move(textureProofs)); }
							return true;
						}
						groupResources.resize(groupStart);
						textureProofs.clear();
						bufferProofs.clear();
					}
					if (!snapshotEligible) { captureBinding = false; }
					std::vector<Snapshots::Resource> snapshotResources;
					auto captureSnapshot = [&](id value, Snapshots::Kind kind, const MVKMetal4PreparedResourceProof& proof) {
						if (!snapshotEligible) { return; }
						if (!value || !proof.valid()) { snapshotEligible = false; return; }
						bool ordinary = kind == Snapshots::Kind::Texture &&
						    MVKMetal4Submission::drawableRegistrationGeneration((id)value) == 0;
						snapshotResources.push_back({(const void*)value, kind, proof, ordinary}); observe(e,2,snapshotResources);
				};
				if (binding.hasImmutableSamplers()) {
					const auto& samplers = layout->immutableSamplers();
					if (binding.immSamplerIndex > samplers.size() || count > samplers.size() - binding.immSamplerIndex) {
						return metal4Failure(sink.encoder, "Native indirect immutable sampler range is invalid.");
					}
					for (uint32_t i = 0; i < count; ++i) {
						if (!sink.object(samplers[binding.immSamplerIndex + i]->getMTLSamplerState())) { return false; }
					}
				}
				if (binding.cpuLayout == MVKDescriptorCPULayout::InlineData || !count) { return true; }
				size_t stride = descriptorCPUSize(binding.cpuLayout);
				if (!stride) { captureBinding = false; return true; }
				uint64_t span = uint64_t(stride) * count;
				if (binding.cpuOffset > set->cpuBufferSize || span > set->cpuBufferSize - binding.cpuOffset || !set->cpuBuffer) {
					return metal4Failure(sink.encoder, "Native indirect descriptor range exceeds CPU payload.");
				}
				for (uint32_t i = 0; i < count; ++i) {
					const char* data = set->cpuBuffer + binding.cpuOffset + size_t(i) * stride;
					for (uint32_t t = 0; t < counts.texture; ++t) {
						id value = nil;
						if ((t + 1) * sizeof(id) > stride) { return metal4Failure(sink.encoder, "Native indirect texture layout is invalid."); }
						memcpy(&value, data + t * sizeof(id), sizeof(value));
						auto live = liveResources.textures.isLive(value);
						if (live && !sink.resource(value)) { return false; }
						if (snapshotEligible || allTexturesProven) {
							auto proof = liveResources.textures.preparationProof(value, live);
							if (snapshotEligible) { captureSnapshot(live ? value : nil, Snapshots::Kind::Texture, proof); }
							if (allTexturesProven) {
								if (proof.valid()) { textureProofs.push_back(std::move(proof)); observe(e,1,textureProofs); }
								else { allTexturesProven = false; }
							}
						}
					}
					if (counts.buffer || (counts.sampler && !binding.hasImmutableSamplers())) {
						if ((counts.texture + 1) * sizeof(id) > stride) { return metal4Failure(sink.encoder, "Native indirect descriptor layout is invalid."); }
						id value = nil;
						memcpy(&value, data + counts.texture * sizeof(id), sizeof(value));
						if (counts.buffer) {
							auto live = liveResources.buffers.isLive(value);
							if (live && !sink.bufferResource(value)) { return false; }
							if (snapshotEligible || allBuffersProven) {
								auto proof = liveResources.buffers.membershipProof(value, live);
								captureSnapshot(live ? value : nil, Snapshots::Kind::Buffer, proof);
								if (allBuffersProven) {
									if (proof.valid()) { bufferProofs.push_back(std::move(proof)); observe(e,0,bufferProofs); }
									else { allBuffersProven = false; }
								}
							}
							if (!value || !live) { allBuffersLive = false; }
						} else {
							auto live = liveResources.isLive(static_cast<id>(value));
							if (live && !sink.object(value)) { return false; }
							if (snapshotEligible || allTexturesProven) {
								auto proof = liveResources.samplers.preparationProof(value, live);
								if (snapshotEligible) { captureSnapshot(live ? value : nil, Snapshots::Kind::Sampler, proof); }
								if (allTexturesProven) {
									if (proof.valid()) { textureProofs.push_back(std::move(proof)); observe(e,1,textureProofs); }
									else { allTexturesProven = false; }
								}
							}
						}
					}
				}
				// Each initial live guard pinned the exact object in this submission.
				// Weak exact membership proofs reject removal/address reuse at replay.
				// Unrelated buffer membership changes do not discard prepared payloads.
				if (snapshotEligible && snapshotResources.size() == resourceCount) {
					if (captureBinding) {
						if (snapshotResources.size() <= Group::kMaxResources - groupResources.size()) {
							groupResources.insert(groupResources.end(), snapshotResources.begin(), snapshotResources.end());
						} else { captureBinding = false; }
					}
					set->metal4Preparation.snapshots->remember(used.bindingIdx, bindingRevision,
						std::move(snapshotResources));
				} else { captureBinding = false; }
				if (allBuffersLive && generation == liveResources.buffers.generation()) {
					if (!allBuffersProven || bufferProofs.size() != count) { bufferProofs.clear(); }
					preparation.remember(set->metal4Preparation, used.bindingIdx, generation, std::move(bufferProofs));
				}
				if (allTexturesProven && textureProofs.size() == uint64_t(count) * (counts.texture + counts.sampler)) {
					if (stats) { ++stats->textureProofReady; }
					texturePreparation.remember(set->metal4Preparation.incarnation, bindingRevision,
					                            used.bindingIdx, std::move(textureProofs));
		        } else if (textureCacheEligible) {
					if (stats) { ++stats->textureProofRejected; }
		            texturePreparation.reject(set->metal4Preparation.incarnation, bindingRevision, used.bindingIdx);
				}
				return true;
				};
return prepareCurrentPayload();}
bool run_candidate(Env&e){auto&common=e.common;auto&resources=e.resources;auto&used=e.used;auto&sink=e.sink;auto&liveResources=sink.encoder.device.live;Stats*stats=nullptr;auto&groupResources=e.groupResources;const size_t groupStart=groupResources.size();auto&captureBinding=e.captureBinding;auto&capturedRevision=e.capturedRevision;auto appendGroupBinding=[&](const MVKMetal4DescriptorPreparationStamp&stamp,uint32_t binding,uint64_t revision){if(captureBinding&&(!stamp.snapshots||!stamp.snapshots->append(binding,revision,groupResources,Group::kMaxResources)))captureBinding=false;};
auto prepareCurrentPayload = [&]() -> bool {
					if (used.set >= common._layout->getDescriptorSetCount() || used.set >= kMVKMaxDescriptorSetCount ||
					    !resources.resources.descriptorSetData.get(used.set) || !common._descriptorSets[used.set]) {
						return metal4Failure(sink.encoder, "Native indirect binding has no argument-buffer root.");
					}
					auto* set = common._descriptorSets[used.set];
					auto* layout = common._layout->getDescriptorSetLayout(used.set);
					if (used.bindingIdx >= layout->bindings().size()) { return metal4Failure(sink.encoder, "Native indirect binding is outside its layout."); }
					const auto& binding = layout->bindings()[used.bindingIdx];
					uint32_t count = binding.getDescriptorCount(set->variableDescriptorCount);
					const auto& counts = binding.perDescriptorResourceCount;
					if (stats && count && (counts.texture || counts.sampler)) { ++stats->textureBindingVisits; }
					auto& preparation = sink.encoder.getState().metal4DescriptorPreparationCache();
					uint64_t bindingRevision = set->metal4Preparation.bindingRevision(used.bindingIdx);
					capturedRevision = bindingRevision;
					// Layout identity is only an eligibility check; cache identity is a fresh
					// pool incarnation + binding + revision, never a descriptor-set pointer.
					bool cacheEligible = set->layout == layout && set->metal4Preparation.incarnation &&
					                     bindingRevision && count && counts.buffer == 1 &&
					                     !counts.texture && !counts.sampler && !binding.hasImmutableSamplers();
					uint64_t generation = cacheEligible ? liveResources.buffers.generation() : UINT64_MAX;
					if (cacheEligible && preparation.matches(set->metal4Preparation, used.bindingIdx, generation,
						[&] { return liveResources.buffers.generation(); })) {
						appendGroupBinding(set->metal4Preparation, used.bindingIdx, bindingRevision);
						return true;
					}
					bool allBuffersLive = cacheEligible;
					bool allBuffersProven = cacheEligible && count <= Snapshots::kMaxResources;
					std::vector<MVKMetal4PreparedResourceProof> bufferProofs;
					auto& texturePreparation = sink.encoder.getState().metal4TexturePreparationCache();
					bool textureCacheEligible = set->layout == layout && set->metal4Preparation.incarnation &&
					                            bindingRevision && count && !counts.buffer &&
					                            (counts.texture || counts.sampler) && !binding.hasImmutableSamplers() &&
					                            uint64_t(count) * (counts.texture + counts.sampler) <= MVKMetal4PreparedTextureBindingCache::kMaxResources;
					if (textureCacheEligible) {
						if (stats) { ++stats->textureCacheEligible; }
						auto textureLookup = texturePreparation.lookup(set->metal4Preparation.incarnation,
							bindingRevision, used.bindingIdx);
						if (textureLookup == MVKMetal4PreparedTextureBindingCache::Result::Hit) {
							if (stats) {
								++stats->textureCacheHits;
								stats->textureHitResourceSlots += uint64_t(count) * (counts.texture + counts.sampler);
							}
							appendGroupBinding(set->metal4Preparation, used.bindingIdx, bindingRevision);
							return true;
						}
						if (stats) { ++stats->textureCacheMisses; }
						textureCacheEligible = textureLookup == MVKMetal4PreparedTextureBindingCache::Result::Attempt;
						if (stats) {
							if (textureCacheEligible) { ++stats->textureProofAttempts; }
							else { ++stats->textureNegativeMemoSkips; }
						}
					}
					std::vector<MVKMetal4PreparedResourceProof> textureProofs;
					bool allTexturesProven = textureCacheEligible;
					uint64_t resourceCount = uint64_t(count) * (counts.buffer + counts.texture + counts.sampler);
					// Call only after an item is accepted. Each eligible capture is bounded
					// to 16 resources and still moves its storage into the existing cache.
					auto reserveCapture = [](auto& values, size_t expectedCount) {
						if (expectedCount > 1 && values.empty() && values.capacity() < expectedCount) {
							values.reserve(expectedCount);
						}
					};
					bool snapshotEligible = bindingRevision && set->metal4Preparation.snapshots &&
					                        set->layout == layout && resourceCount && resourceCount <= Snapshots::kMaxResources &&
					                        binding.cpuLayout != MVKDescriptorCPULayout::InlineData && !binding.hasImmutableSamplers();
					uint64_t snapshotGeneration = liveResources.buffers.generation();
					if (snapshotEligible) {
						auto result = set->metal4Preparation.snapshots->replay(used.bindingIdx, bindingRevision,
							[&](const Snapshots::Resource& resource) {
								auto result = replayMetal4Resource(sink, resource);
								if (result == Snapshots::Result::Hit && allTexturesProven) {
									reserveCapture(textureProofs, resourceCount);
									textureProofs.push_back(resource.proof); observe(e,1,textureProofs);
								}
								if (result == Snapshots::Result::Hit && allBuffersProven &&
								    resource.kind == Snapshots::Kind::Buffer) {
									reserveCapture(bufferProofs, count);
									bufferProofs.push_back(resource.proof); observe(e,0,bufferProofs);
								}
								if (result == Snapshots::Result::Hit && captureBinding) {
									if (groupResources.size() < Group::kMaxResources) { groupResources.push_back(resource); }
									else { captureBinding = false; }
								}
								return result;
							});
						if (result == Snapshots::Result::Failed) { return false; }
						if (result == Snapshots::Result::Hit) {
							if (cacheEligible && snapshotGeneration == liveResources.buffers.generation()) {
								if (!allBuffersProven || bufferProofs.size() != count) { bufferProofs.clear(); }
								preparation.remember(set->metal4Preparation, used.bindingIdx, snapshotGeneration, std::move(bufferProofs));
							}
							if (allTexturesProven) { texturePreparation.remember(set->metal4Preparation.incarnation,
								bindingRevision, used.bindingIdx, std::move(textureProofs)); }
							return true;
						}
						groupResources.resize(groupStart);
						textureProofs.clear();
						bufferProofs.clear();
					}
					if (!snapshotEligible) { captureBinding = false; }
					std::vector<Snapshots::Resource> snapshotResources;
					auto captureSnapshot = [&](id value, Snapshots::Kind kind, const MVKMetal4PreparedResourceProof& proof) {
						if (!snapshotEligible) { return; }
						if (!value || !proof.valid()) { snapshotEligible = false; return; }
						bool ordinary = kind == Snapshots::Kind::Texture &&
						    MVKMetal4Submission::drawableRegistrationGeneration((id)value) == 0;
						reserveCapture(snapshotResources, resourceCount);
						snapshotResources.push_back({(const void*)value, kind, proof, ordinary}); observe(e,2,snapshotResources);
				};
				if (binding.hasImmutableSamplers()) {
					const auto& samplers = layout->immutableSamplers();
					if (binding.immSamplerIndex > samplers.size() || count > samplers.size() - binding.immSamplerIndex) {
						return metal4Failure(sink.encoder, "Native indirect immutable sampler range is invalid.");
					}
					for (uint32_t i = 0; i < count; ++i) {
						if (!sink.object(samplers[binding.immSamplerIndex + i]->getMTLSamplerState())) { return false; }
					}
				}
				if (binding.cpuLayout == MVKDescriptorCPULayout::InlineData || !count) { return true; }
				size_t stride = descriptorCPUSize(binding.cpuLayout);
				if (!stride) { captureBinding = false; return true; }
				uint64_t span = uint64_t(stride) * count;
				if (binding.cpuOffset > set->cpuBufferSize || span > set->cpuBufferSize - binding.cpuOffset || !set->cpuBuffer) {
					return metal4Failure(sink.encoder, "Native indirect descriptor range exceeds CPU payload.");
				}
				for (uint32_t i = 0; i < count; ++i) {
					const char* data = set->cpuBuffer + binding.cpuOffset + size_t(i) * stride;
					for (uint32_t t = 0; t < counts.texture; ++t) {
						id value = nil;
						if ((t + 1) * sizeof(id) > stride) { return metal4Failure(sink.encoder, "Native indirect texture layout is invalid."); }
						memcpy(&value, data + t * sizeof(id), sizeof(value));
						auto live = liveResources.textures.isLive(value);
						if (live && !sink.resource(value)) { return false; }
						if (snapshotEligible || allTexturesProven) {
							auto proof = liveResources.textures.preparationProof(value, live);
							if (snapshotEligible) { captureSnapshot(live ? value : nil, Snapshots::Kind::Texture, proof); }
							if (allTexturesProven) {
								if (proof.valid()) { reserveCapture(textureProofs, resourceCount); textureProofs.push_back(std::move(proof)); observe(e,1,textureProofs); }
								else { allTexturesProven = false; }
							}
						}
					}
					if (counts.buffer || (counts.sampler && !binding.hasImmutableSamplers())) {
						if ((counts.texture + 1) * sizeof(id) > stride) { return metal4Failure(sink.encoder, "Native indirect descriptor layout is invalid."); }
						id value = nil;
						memcpy(&value, data + counts.texture * sizeof(id), sizeof(value));
						if (counts.buffer) {
							auto live = liveResources.buffers.isLive(value);
							if (live && !sink.bufferResource(value)) { return false; }
							if (snapshotEligible || allBuffersProven) {
								auto proof = liveResources.buffers.membershipProof(value, live);
								captureSnapshot(live ? value : nil, Snapshots::Kind::Buffer, proof);
								if (allBuffersProven) {
									if (proof.valid()) { reserveCapture(bufferProofs, count); bufferProofs.push_back(std::move(proof)); observe(e,0,bufferProofs); }
									else { allBuffersProven = false; }
								}
							}
							if (!value || !live) { allBuffersLive = false; }
						} else {
							auto live = liveResources.isLive(static_cast<id>(value));
							if (live && !sink.object(value)) { return false; }
							if (snapshotEligible || allTexturesProven) {
								auto proof = liveResources.samplers.preparationProof(value, live);
								if (snapshotEligible) { captureSnapshot(live ? value : nil, Snapshots::Kind::Sampler, proof); }
								if (allTexturesProven) {
									if (proof.valid()) { reserveCapture(textureProofs, resourceCount); textureProofs.push_back(std::move(proof)); observe(e,1,textureProofs); }
									else { allTexturesProven = false; }
								}
							}
						}
					}
				}
				// Each initial live guard pinned the exact object in this submission.
				// Weak exact membership proofs reject removal/address reuse at replay.
				// Unrelated buffer membership changes do not discard prepared payloads.
				if (snapshotEligible && snapshotResources.size() == resourceCount) {
					if (captureBinding) {
						if (snapshotResources.size() <= Group::kMaxResources - groupResources.size()) {
							groupResources.insert(groupResources.end(), snapshotResources.begin(), snapshotResources.end());
						} else { captureBinding = false; }
					}
					set->metal4Preparation.snapshots->remember(used.bindingIdx, bindingRevision,
						std::move(snapshotResources));
				} else { captureBinding = false; }
				if (allBuffersLive && generation == liveResources.buffers.generation()) {
					if (!allBuffersProven || bufferProofs.size() != count) { bufferProofs.clear(); }
					preparation.remember(set->metal4Preparation, used.bindingIdx, generation, std::move(bufferProofs));
				}
				if (allTexturesProven && textureProofs.size() == uint64_t(count) * (counts.texture + counts.sampler)) {
					if (stats) { ++stats->textureProofReady; }
					texturePreparation.remember(set->metal4Preparation.incarnation, bindingRevision,
					                            used.bindingIdx, std::move(textureProofs));
		        } else if (textureCacheEligible) {
					if (stats) { ++stats->textureProofRejected; }
		            texturePreparation.reject(set->metal4Preparation.incarnation, bindingRevision, used.bindingIdx);
				}
				return true;
				};
return prepareCurrentPayload();}

static unsigned assertions=0,cases=0;
void require(bool v,const char*m){++assertions;if(!v)throw std::runtime_error(m);}
using Run=bool(*)(Env&);
struct Outcome {
    bool ok;size_t allocs,bytes;std::array<Env::Observation,3>obs;
    std::array<Trace,128>trace;size_t traceCount;std::array<size_t,3>stored{};
    std::array<bool,3>sameStorage{};bool textureNegative=false;uint64_t capturedRevision=0;
    std::array<uint64_t,4>contents{};size_t groupSize=0;
};
uint64_t proofDigest(const MVKMetal4PreparedResourceProof&p){return p.count*2u+unsigned(p.valid());}
void digest(uint64_t&h,uint64_t v){h=h*1099511628211ull+v+1;}
void digestResource(uint64_t&h,const Snapshots::Resource&r){digest(h,reinterpret_cast<uintptr_t>(r.identity));digest(h,unsigned(r.kind));digest(h,proofDigest(r.proof));digest(h,r.drawableIndependent);}
Outcome execute(Run fn,Env&e){
    e.resetObservation();allocations=allocationBytes=0;counting=true;bool ok=fn(e);counting=false;
    Outcome r{ok,allocations,allocationBytes,e.observed,e.sink.trace,e.sink.traceCount};
    r.capturedRevision=e.capturedRevision;
    for(auto&x:e.sink.encoder.state.buffers._bindings){r.stored[0]+=x.second.proofs.size();r.sameStorage[0]=x.second.proofs.data()==r.obs[0].data;}
    for(auto&x:e.sink.encoder.state.textures._bindings){r.stored[1]+=x.second.proofs.size();r.sameStorage[1]=x.second.proofs.data()==r.obs[1].data;r.textureNegative=x.second.proofs.empty();}
    for(auto&x:e.snapshots._bindings){r.stored[2]+=x.second.resources.size();r.sameStorage[2]=x.second.resources.data()==r.obs[2].data;}
    for(auto&x:e.sink.encoder.state.buffers._bindings)for(auto&p:x.second.proofs)digest(r.contents[0],proofDigest(p));
    for(auto&x:e.sink.encoder.state.textures._bindings)for(auto&p:x.second.proofs)digest(r.contents[1],proofDigest(p));
    for(auto&x:e.snapshots._bindings)for(auto&v:x.second.resources)digestResource(r.contents[2],v);
    r.groupSize=e.groupResources.size();for(auto&v:e.groupResources)digestResource(r.contents[3],v);
    return r;
}
void equivalent(const Outcome&a,const Outcome&b){
    require(a.ok==b.ok,"return parity");require(a.traceCount==b.traceCount,"native retain count parity");
    for(size_t i=0;i<a.traceCount;++i)require(a.trace[i]==b.trace[i],"native retention order parity");
    require(a.stored==b.stored,"persistent cardinality parity");require(a.textureNegative==b.textureNegative,"negative memo parity");
    require(a.capturedRevision==b.capturedRevision,"revision parity");
    require(a.contents==b.contents&&a.groupSize==b.groupSize,"stored contents/order and group prefix parity");
    for(size_t i=0;i<3;++i)require(a.obs[i].inserts==b.obs[i].inserts,"collected cardinality parity");
}
void setup(Env&e,unsigned scenario){
    const auto total=e.n*(e.mode==3?2:1);
    if(scenario==1||scenario==2)e.preseed();
    if(scenario==2&&total>1){auto&l=e.list(1);l.remove(e.payload[1]);l.addPrepared(e.payload[1]);auto g=l.isLive(e.payload[1]);l.membershipProof(e.payload[1],g);}
    if(scenario==2&&total){e.captureBinding=true;e.groupResources.push_back({e.payload[0],e.kind(0),e.proof(0),true});}
    if(scenario==3&&total){e.list(0).remove(e.payload[0]);if(e.mode!=0)e.list(0).add(e.payload[0]);}
    if(scenario==4&&total>1){e.list(1).remove(e.payload[1]);if(e.mode!=0)e.list(1).add(e.payload[1]);}
    if(scenario==5)e.sink.failAt=1;
    if(scenario==6)e.sink.failAt=total>1?2:1;
    if(scenario==7||scenario==8)e.sink.encoder.state.textures.reject(7,1,0);
}
int main(){try{
    unsigned lateFailureExamples=0;
    for(unsigned mode=0;mode<4;++mode)for(size_t n:{0u,1u,2u,3u,8u,16u,17u}){
        const size_t total=n*(mode==3?2:1);if(total>34)continue;
        for(unsigned scenario=0;scenario<9;++scenario){
            if((scenario==7||scenario==8)&&mode==0)continue;
            if((scenario==1||scenario==2)&&(!total||total>16))continue;
            Env a(mode,n,scenario!=7),b(mode,n,scenario!=7);setup(a,scenario);setup(b,scenario);
            auto x=execute(run_reference,a),y=execute(run_candidate,b);equivalent(x,y);++cases;
            if(total<=1||total>16||scenario==3||scenario==5||scenario==7)
                require(y.allocs==x.allocs,"no extra allocations for singleton/empty/ineligible/first failure/negative-only");
            if(scenario==0&&total>1&&total<=16){
                require(y.allocs<x.allocs,"successful multi-entry capture reduces actual allocations");
                for(size_t k=0;k<3;++k)if(y.stored[k]){require(y.sameStorage[k],"persistent cache takes original vector storage");require(y.obs[k].growth==1,"one capture storage growth");}
            }
            if(scenario==1&&total>1){require(y.allocs<x.allocs,"snapshot Hit is positive collection and has reduced growth");}
            if(scenario==2){
                for(size_t k=0;k<2;++k)if(y.obs[k].inserts)require(y.obs[k].growth==1,"partial replay clear preserves reserved capacity for fallback");
            }
            if((scenario==4||scenario==6)&&total==16){
                ++lateFailureExamples;
                require(y.obs[mode==0?0:1].maxCapacity<=16,"late failure capacity remains bounded");
                std::printf("{\"case\":\"late_failure\",\"mode\":%u,\"scenario\":%u,\"referenceAllocations\":%zu,\"candidateAllocations\":%zu,\"referenceBytes\":%zu,\"candidateBytes\":%zu,\"referenceCapacity\":%zu,\"candidateCapacity\":%zu}\n",mode,scenario,x.allocs,y.allocs,x.bytes,y.bytes,x.obs[mode==0?0:1].maxCapacity,y.obs[mode==0?0:1].maxCapacity);
            }
            if(scenario==0&&total>0&&total<=16){
                auto hitA=execute(run_reference,a),hitB=execute(run_candidate,b);equivalent(hitA,hitB);
                require(hitA.traceCount==0&&hitB.allocs==0,"recording cache Hit skips collection and allocations");
                // Cache entries remain weak: removing native identity invalidates proofs.
                for(size_t i=0;i<total;++i){a.list(i).remove(a.payload[i]);b.list(i).remove(b.payload[i]);}
                if(!b.snapshots._bindings.empty())require(!b.snapshots._bindings.begin()->second.resources.front().proof.valid(),"moved snapshot does not own native identity");
                a.sink.encoder.state.buffers.clear();b.sink.encoder.state.buffers.clear();
                a.sink.encoder.state.textures.clear();b.sink.encoder.state.textures.clear();
                a.snapshots.clear();b.snapshots.clear();
                require(b.snapshots._bindings.empty(),"destination clear releases metadata");
            }
            if(scenario==0&&total==16)std::printf("{\"case\":\"success16\",\"mode\":%u,\"referenceAllocations\":%zu,\"candidateAllocations\":%zu,\"referenceBytes\":%zu,\"candidateBytes\":%zu}\n",mode,x.allocs,y.allocs,x.bytes,y.bytes);
        }
    }
    require(lateFailureExamples>0,"late failure examples exercised");
    std::printf("{\"passed\":true,\"cases\":%u,\"assertions\":%u,\"sizeofProof\":%zu,\"sizeofResource\":%zu,\"gpuExecuted\":false}\n",cases,assertions,sizeof(MVKMetal4PreparedResourceProof),sizeof(Snapshots::Resource));
    return 0;
}catch(const std::exception&e){counting=false;std::fprintf(stderr,"FAIL %s\n",e.what());return 1;}}
