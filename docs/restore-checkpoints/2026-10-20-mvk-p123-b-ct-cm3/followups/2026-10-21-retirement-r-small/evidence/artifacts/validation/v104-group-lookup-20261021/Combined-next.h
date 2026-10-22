/* SPDX-License-Identifier: Apache-2.0 */
#pragma once

#include <array>
#include <memory>
#include <unordered_map>
#include <vector>
#include <cstdint>
#include <algorithm>
#include <atomic>
#include <mutex>
#include <utility>

// Recording-local identities with reusable, empty node storage. Retired nodes
// contain neither object addresses nor old residency/retention flags. Moving the
// empty cache to an idle pack never extends an object's ownership or proof.
template<class Identity, size_t MaxCachedNodes>
class MVKMetal4RecycledIdentityMap {
    using Map = std::unordered_map<const void*, Identity>;
    Map _values;
    std::vector<typename Map::node_type> _emptyNodes;
public:
    using iterator = typename Map::iterator;
    iterator find(const void* key) { return _values.find(key); }
    iterator end() { return _values.end(); }
    size_t size() const { return _values.size(); }
    size_t bucket_count() const { return _values.bucket_count(); }
    size_t cachedNodeCount() const { return _emptyNodes.size(); }
    std::pair<iterator, bool> try_emplace(const void* key) {
        if (_emptyNodes.empty()) { return _values.try_emplace(key); }
        return try_emplace_after_lookup(key, _values.find(key));
    }
    // Consume a fresh lookup of this map before any mutation or unlock. The
    // caller must use the returned iterator after insertion can rehash the map.
    std::pair<iterator, bool> try_emplace_after_lookup(const void* key, iterator found) {
        if (found != _values.end()) { return {found, false}; }
        if (_emptyNodes.empty()) { return _values.try_emplace(key); }
        auto node = std::move(_emptyNodes.back());
        _emptyNodes.pop_back();
        node.key() = key;
        // clear() reset the mapped value before caching this storage.
        auto inserted = _values.insert(std::move(node));
        return {inserted.position, inserted.inserted};
    }
    void clear() {
        while (!_values.empty() && _emptyNodes.size() < MaxCachedNodes) {
            auto node = _values.extract(_values.begin());
            node.key() = nullptr;
            node.mapped() = Identity{};
            _emptyNodes.push_back(std::move(node));
        }
        _values.clear();
    }
    void swap(MVKMetal4RecycledIdentityMap& other) {
        _values.swap(other._values);
        _emptyNodes.swap(other._emptyNodes);
    }
    uint64_t hostStorageBytes() const {
        // Known payload only, as with the existing bucket/vector accounting.
        // Implementation-private allocator/node overhead is not measured here.
        return (bucket_count() > 1 ? bucket_count() * sizeof(void*) : 0) +
            _emptyNodes.capacity() * sizeof(typename Map::node_type) +
            _emptyNodes.size() * sizeof(typename Map::value_type);
    }
};

// Every production preparation owner uses this token. Destruction covers heap
// overlap/export/removal and unproved registrations, including revocations that
// do not change a native resource's live-list membership.
class MVKMetal4PreparationEpoch {
    static std::atomic<uint64_t>& counter() { static std::atomic<uint64_t> value{1}; return value; }
public:
    static uint64_t current() { return counter().load(std::memory_order_acquire); }
    static void revoke() {
        uint64_t value = counter().load(std::memory_order_relaxed);
        while (value != UINT64_MAX && !counter().compare_exchange_weak(value, value + 1,
            std::memory_order_release, std::memory_order_relaxed)) {}
    }
    struct Token { ~Token() { revoke(); } };
    static std::shared_ptr<void> owner() { return std::make_shared<Token>(); }
    static uint64_t allocateScriptIdentity() {
        static std::atomic<uint64_t> next{0};
        uint64_t value = next.load(std::memory_order_relaxed);
        while (value != UINT64_MAX) {
            if (next.compare_exchange_weak(value, value + 1, std::memory_order_relaxed)) { return value + 1; }
        }
        return 0;
    }
};

// Weak ownership, not native-address identity. A view also depends on its exact
// base allocation incarnation; an unproved registration revokes that identity.
struct MVKMetal4PreparedResourceProof {
    static constexpr uint32_t kMaxOwners = 4;
    std::array<std::weak_ptr<void>, kMaxOwners> owners;
    uint32_t count = 0;
    bool valid() const {
        if (!count || count > kMaxOwners) { return false; }
        for (uint32_t i = 0; i < count; ++i) { if (owners[i].expired()) { return false; } }
        return true;
    }
    bool matches(const MVKMetal4PreparedResourceProof& other) const {
        if (count != other.count || !valid() || !other.valid()) { return false; }
        for (uint8_t i = 0; i < count; ++i) {
            if (owners[i].owner_before(other.owners[i]) || other.owners[i].owner_before(owners[i])) { return false; }
        }
        return true;
    }
};

// Descriptor-pool-owned CPU preparation, independent of native recordings.
// Native identities are never retained here. Replay must validate each identity
// under its live-list lock and acquire fresh submission ownership before use.
class MVKMetal4PreparedBindingSnapshots {
public:
    enum class Kind : uint8_t { Buffer, Texture, Sampler };
    enum class Result : uint8_t { Miss, Hit, Failed };
    struct Resource {
        const void* identity;
        Kind kind;
        MVKMetal4PreparedResourceProof proof;
        // Captured only after successful native registration of this texture.
        // Buffer/sampler resources do not depend on drawable registration.
        bool drawableIndependent = false;
    };
    static constexpr size_t kMaxResources = 16;
    static constexpr size_t kMaxBindings = 64;
private:
    struct Entry {
        uint64_t revision;
        std::vector<Resource> resources;
    };
    std::mutex _mutex;
    std::unordered_map<uint32_t, Entry> _bindings;
public:
    void clear() { std::lock_guard<std::mutex> lock(_mutex); _bindings.clear(); }
    // Copy CPU identities only. The caller already retained this binding in its
    // current recording; a later recording must still validate and retain them.
    bool append(uint32_t binding, uint64_t revision, std::vector<Resource>& resources, size_t limit) {
        std::lock_guard<std::mutex> lock(_mutex);
        auto it = _bindings.find(binding);
        if (!revision || it == _bindings.end() || it->second.revision != revision ||
            resources.size() > limit || it->second.resources.size() > limit - resources.size()) { return false; }
        for (const auto& resource : it->second.resources) { if (!resource.proof.valid()) { return false; } }
        resources.insert(resources.end(), it->second.resources.begin(), it->second.resources.end());
        return true;
    }
    template<class Retain>
    Result replay(uint32_t binding, uint64_t revision, const Retain& retain) {
        std::lock_guard<std::mutex> lock(_mutex);
        auto it = _bindings.find(binding);
        if (!revision || it == _bindings.end() || it->second.revision != revision) { return Result::Miss; }
        for (const auto& resource : it->second.resources) {
            auto result = retain(resource);
            if (result != Result::Hit) {
                if (result == Result::Miss) { _bindings.erase(it); }
                return result;
            }
        }
        return Result::Hit;
    }
    void remember(uint32_t binding, uint64_t revision, std::vector<Resource>&& resources) {
        if (!revision || resources.empty() || resources.size() > kMaxResources) { return; }
        for (const auto& resource : resources) {
            if (!resource.identity || !resource.proof.valid()) { return; }
        }
        std::lock_guard<std::mutex> lock(_mutex);
        auto it = _bindings.find(binding);
        if (it != _bindings.end()) { it->second = {revision, std::move(resources)}; }
        else if (_bindings.size() < kMaxBindings) { _bindings.emplace(binding, Entry{revision, std::move(resources)}); }
    }
};

struct MVKMetal4PreparedResourceIdentity {
    std::shared_ptr<void> owner = MVKMetal4PreparationEpoch::owner();
    MVKMetal4PreparedResourceProof parents;
    MVKMetal4PreparedResourceProof proof() const {
        MVKMetal4PreparedResourceProof result;
        if (parents.count >= result.kMaxOwners || (parents.count && !parents.valid())) { return result; }
        result.owners[result.count++] = owner;
        for (uint32_t i = 0; i < parents.count; ++i) { result.owners[result.count++] = parents.owners[i]; }
        return result;
    }
};

// Owned by one VkDeviceMemory and accessed only under its binding mutex. Proofs
// expire on overlapping later binds, owner removal, export or allocation death.
// This stores at most 256 admitted texture ranges, not a second binding registry.
class MVKMetal4PreparedHeapRanges {
    struct Entry {
        const void* binding;
        uint64_t offset, size;
        std::shared_ptr<void> owner;
    };
    std::vector<Entry> _entries;
public:
    static bool validRange(uint64_t offset, uint64_t size, uint64_t allocationSize) {
        return size && offset <= allocationSize && size <= allocationSize - offset;
    }
    static bool overlaps(uint64_t a, uint64_t as, uint64_t b, uint64_t bs) {
        // Callers validate ranges first, so these sums cannot wrap.
        return a < b + bs && b < a + as;
    }
    void clear() { _entries.clear(); }
    void remove(const void* binding) {
        _entries.erase(std::remove_if(_entries.begin(), _entries.end(),
            [=](const Entry& e) { return e.binding == binding; }), _entries.end());
    }
    void bound(uint64_t offset, uint64_t size, uint64_t allocationSize) {
        if (!validRange(offset, size, allocationSize)) { clear(); return; }
        _entries.erase(std::remove_if(_entries.begin(), _entries.end(), [&](const Entry& e) {
            return overlaps(offset, size, e.offset, e.size);
        }), _entries.end());
    }
    MVKMetal4PreparedResourceProof admit(const void* binding, uint64_t offset,
                                       uint64_t size, uint64_t allocationSize) {
        MVKMetal4PreparedResourceProof proof;
        if (!binding || !validRange(offset, size, allocationSize)) { return proof; }
        for (const auto& entry : _entries) {
            if (entry.binding == binding && entry.offset == offset && entry.size == size) {
                proof.owners[0] = entry.owner; proof.count = 1; return proof;
            }
        }
        if (_entries.size() >= 256) { return proof; }
        _entries.push_back({binding, offset, size, MVKMetal4PreparationEpoch::owner()});
        proof.owners[0] = _entries.back().owner; proof.count = 1;
        return proof;
    }
};

// Values only: never descriptor-set addresses, pool epoch-array pointers, or
// Vulkan pipeline addresses. The pipeline script has a fresh immutable identity.
struct MVKMetal4PreparedGroupStamp {
    static constexpr uint32_t kMaxSets = 16;
    uint64_t script = 0;
    uint32_t stage = 0, setMask = 0;
    struct Set {
        uint64_t incarnation = 0, revision = 0;
        bool operator==(const Set& rhs) const { return incarnation == rhs.incarnation && revision == rhs.revision; }
    };
    std::array<Set, kMaxSets> sets{};
    // Buffer/texture/sampler membership, weak-proof revocation, drawable mutation.
    std::array<uint64_t, 5> epochs{};
    bool valid() const {
        if (!script || !setMask || (setMask >> kMaxSets)) { return false; }
        for (uint64_t value : epochs) { if (!value || value == UINT64_MAX) { return false; } }
        for (uint32_t i = 0; i < kMaxSets; ++i) {
            if ((setMask & (1u << i)) && (!sets[i].incarnation || !sets[i].revision)) { return false; }
        }
        return true;
    }
    bool operator==(const MVKMetal4PreparedGroupStamp& rhs) const {
        return script == rhs.script && stage == rhs.stage && setMask == rhs.setMask && sets == rhs.sets && epochs == rhs.epochs;
    }
    bool sameDescriptors(const MVKMetal4PreparedGroupStamp& rhs) const {
        return script == rhs.script && stage == rhs.stage && setMask == rhs.setMask && sets == rhs.sets;
    }
    bool sameIdentity(const MVKMetal4PreparedGroupStamp& rhs) const {
        if (script != rhs.script || stage != rhs.stage || setMask != rhs.setMask) { return false; }
        for (uint32_t i = 0; i < kMaxSets; ++i) {
            if ((setMask & (1u << i)) && sets[i].incarnation != rhs.sets[i].incarnation) { return false; }
        }
        return true;
    }
};

// One bounded CPU snapshot per pipeline stage. It neither owns Metal objects nor
// carries residency across recordings. Only a repeated descriptor combination
// is admitted, so descriptor churn does not allocate/copy resource vectors.
class MVKMetal4PreparedGroupSnapshot {
    using Resource = MVKMetal4PreparedBindingSnapshots::Resource;
    using Result = MVKMetal4PreparedBindingSnapshots::Result;
public:
    struct BindingVersion { uint32_t ordinal, set, binding, resourceCount; uint64_t revision; };
    struct RecordingProof {
        MVKMetal4PreparedGroupStamp stamp;
        std::vector<Resource> resources;
        std::vector<BindingVersion> covered;
        std::vector<uint32_t> residual;
        bool drawableIndependent;
        template<class Revision>
        bool matchesBindings(const MVKMetal4PreparedGroupStamp& current, const Revision& revision) const {
            if (!stamp.sameIdentity(current)) { return false; }
            if (stamp.sameDescriptors(current)) { return true; }
            for (const auto& binding : covered) {
                if (binding.revision != revision(binding.set, binding.binding)) { return false; }
            }
            return true;
        }
    };
    // Strong CPU metadata only. Every resource/allocation/membership owner in
    // the immutable entry remains weak; there are no native or pool owners.
    using RecordingProofRef = std::shared_ptr<const RecordingProof>;
private:
    using Entry = RecordingProof;
    std::mutex _mutex;
    std::shared_ptr<const Entry> _entry;
    MVKMetal4PreparedGroupStamp _observed;
    bool _rejected = false;
public:
    static constexpr size_t kMaxResources = 64;
    static constexpr size_t kMaxBindings = 64;
    template<class Revision, class Retain>
    Result replay(const MVKMetal4PreparedGroupStamp& stamp, const Revision& revision,
                  const Retain& retain, bool& capture, RecordingProofRef* retained = nullptr) {
        capture = false;
        if (retained) { retained->reset(); }
        if (!stamp.valid()) { return Result::Miss; }
        std::shared_ptr<const Entry> entry;
        {
            std::lock_guard<std::mutex> lock(_mutex);
            if (_entry && _entry->stamp.sameIdentity(stamp)) { entry = _entry; }
            if (_observed.sameDescriptors(stamp)) { capture = !_rejected; }
            else { _observed = stamp; _rejected = false; }
        }
        if (!entry || !entry->matchesBindings(stamp, revision)) { return Result::Miss; }
        // Do not hold the pipeline cache mutex while acquiring resource locks.
        // The immutable CPU entry survives concurrent cache replacement.
        for (const auto& resource : entry->resources) {
            auto result = retain(resource);
            if (result != Result::Hit) {
                if (result == Result::Miss) {
                    std::lock_guard<std::mutex> lock(_mutex);
                    if (_entry == entry) { _entry.reset(); }
                }
                return result;
            }
        }
        capture = false;
        // Publish only the immutable CPU entry actually validated and retained
        // by this replay. A cache replacement cannot substitute another proof.
        if (retained) { *retained = entry; }
        return Result::Hit;
    }
    void reject(const MVKMetal4PreparedGroupStamp& stamp) {
        std::lock_guard<std::mutex> lock(_mutex);
        if (_observed.sameDescriptors(stamp)) { _rejected = true; }
    }
    RecordingProofRef remember(const MVKMetal4PreparedGroupStamp& before, const MVKMetal4PreparedGroupStamp& after,
                               std::vector<Resource>&& resources, std::vector<BindingVersion>&& covered,
                               std::vector<uint32_t>&& residual, size_t bindingCount) {
        if (!before.valid() || !(before == after) || resources.empty() || resources.size() > kMaxResources ||
            covered.empty() || !bindingCount || bindingCount > kMaxBindings ||
            covered.size() + residual.size() != bindingCount) { return {}; }
        // Admission checks the complete plan once. Draws consume the immutable
        // vectors directly; an incomplete/overlapping plan is never published.
        uint64_t seen = 0;
        auto visit = [&](uint32_t ordinal) {
            if (ordinal >= bindingCount || (seen & (uint64_t(1) << ordinal))) { return false; }
            seen |= uint64_t(1) << ordinal; return true;
        };
        size_t resourceCount = 0;
        uint32_t previous = 0;
        bool first = true;
        for (const auto& binding : covered) {
            if (!binding.revision || binding.set >= MVKMetal4PreparedGroupStamp::kMaxSets ||
                !(before.setMask & (1u << binding.set)) || !binding.resourceCount ||
                binding.resourceCount > resources.size() - resourceCount ||
                (!first && binding.ordinal <= previous) || !visit(binding.ordinal)) { return {}; }
            resourceCount += binding.resourceCount;
            previous = binding.ordinal; first = false;
        }
        if (resourceCount != resources.size()) { return {}; }
        first = true;
        for (uint32_t ordinal : residual) {
            if ((!first && ordinal <= previous) || !visit(ordinal)) { return {}; }
            previous = ordinal; first = false;
        }
        bool drawableIndependent = true;
        for (const auto& resource : resources) {
            if (!resource.identity || !resource.proof.valid()) { return {}; }
            if (resource.kind == MVKMetal4PreparedBindingSnapshots::Kind::Texture &&
                !resource.drawableIndependent) { drawableIndependent = false; }
        }
        auto entry = std::make_shared<Entry>(Entry{before, std::move(resources), std::move(covered),
                                                  std::move(residual), drawableIndependent});
        std::lock_guard<std::mutex> lock(_mutex);
        _entry = std::move(entry);
        return _entry;
    }
};

// One full preparation per unchanged stage/set group in a GPU recording. Roots
// and direct/dynamic binding operations remain outside this cache.
class MVKMetal4PreparedGroupCache {
    using Proof = MVKMetal4PreparedGroupSnapshot::RecordingProofRef;
    struct Entry { MVKMetal4PreparedGroupStamp stamp; Proof proof; };
    std::unordered_map<uint64_t, Entry> _groups;
    struct RecentEntry { uint64_t script = 0; Entry* entry = nullptr; };
    // Locations only, never a cached validation result. Node references survive
    // unordered_map rehash; this map erases entries only at recording clear.
    std::array<RecentEntry, 6> _recent{};
    Entry* findEntry(uint64_t script, uint32_t stage) {
        RecentEntry* recent = stage < _recent.size() ? &_recent[stage] : nullptr;
        if (recent && recent->script == script && recent->entry) { return recent->entry; }
        auto found = _groups.find(script);
        if (found == _groups.end()) { return nullptr; }
        Entry* entry = &found->second;
        if (recent) { *recent = {script, entry}; }
        return entry;
    }
public:
    MVKMetal4PreparedGroupCache() = default;
    // Cached locations belong to this recording's map, never to a copied owner.
    MVKMetal4PreparedGroupCache(const MVKMetal4PreparedGroupCache&) = delete;
    MVKMetal4PreparedGroupCache& operator=(const MVKMetal4PreparedGroupCache&) = delete;
    MVKMetal4PreparedGroupCache(MVKMetal4PreparedGroupCache&&) = delete;
    MVKMetal4PreparedGroupCache& operator=(MVKMetal4PreparedGroupCache&&) = delete;
    struct Lookup { bool complete = false; Proof partial; };
    void clear() { _recent = {}; _groups.clear(); }
    template<class Revision, class StableStamp>
    Lookup lookup(const MVKMetal4PreparedGroupStamp& stamp, const Revision& revision, const StableStamp& stableStamp) {
        if (!stamp.script || !stamp.setMask || (stamp.setMask >> MVKMetal4PreparedGroupStamp::kMaxSets)) { return {}; }
        auto* entry = findEntry(stamp.script, stamp.stage);
        // Every stored stamp passed valid() at admission or stabilized refresh.
        // Exact equality therefore needs no repeat validity scan, shared_ptr
        // copy, proof scan or callback. Nonexact paths keep full validation.
        if (entry && entry->stamp == stamp) { return {true, {}}; }
        if (!stamp.valid() || !entry) { return {}; }
        const auto& proof = entry->proof;
        if (!proof || !entry->stamp.sameIdentity(stamp) ||
            (!proof->drawableIndependent && entry->stamp.epochs[4] != stamp.epochs[4]) ||
            !proof->matchesBindings(stamp, revision)) { return {}; }
        for (const auto& resource : proof->resources) {
            if (!resource.proof.valid()) { return {}; }
        }
        // Changes during validation cannot publish a refreshed epoch stamp.
        if (!(stamp == stableStamp())) { return {}; }
        // Covered resources are already retained. Residual bindings must run
        // before remember() can publish a complete preparation for this stamp.
        if (!proof->residual.empty()) { return {false, proof}; }
        entry->stamp = stamp;
        return {true, {}};
    }
    void remember(const MVKMetal4PreparedGroupStamp& before, const MVKMetal4PreparedGroupStamp& after,
                  Proof proof = {}) {
        if (!before.valid() || !(before == after)) { return; }
        if (proof && !proof->stamp.sameIdentity(before)) { return; }
        auto* entry = findEntry(before.script, before.stage);
        if (entry) { *entry = {before, std::move(proof)}; }
        else if (_groups.size() < 128) { _groups.emplace(before.script, Entry{before, std::move(proof)}); }
    }
};

// Only successful full validation and recording retention may admit a binding.
// Recording changes clear this cache. No Metal objects are retained here.
class MVKMetal4PreparedTextureBindingCache {
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
    struct Entry { uint64_t revision; std::vector<MVKMetal4PreparedResourceProof> proofs; };
    std::unordered_map<Key, Entry, Hash> _bindings;
public:
    static constexpr uint32_t kMaxResources = 16;
    enum class Result { Hit, Attempt, Negative };
    void clear() { _bindings.clear(); }
    Result lookup(uint64_t incarnation, uint64_t revision, uint32_t binding) {
        if (!incarnation || !revision) { return Result::Attempt; }
        auto it = _bindings.find({incarnation, binding});
        if (it == _bindings.end()) { return Result::Attempt; }
        if (it->second.revision != revision) { _bindings.erase(it); return Result::Attempt; }
        if (it->second.proofs.empty()) { return Result::Negative; }
        for (const auto& proof : it->second.proofs) {
            if (!proof.valid()) { _bindings.erase(it); return Result::Attempt; }
        }
        return Result::Hit;
    }
    bool matches(uint64_t incarnation, uint64_t revision, uint32_t binding) {
        return lookup(incarnation, revision, binding) == Result::Hit;
    }
    bool shouldAttempt(uint64_t incarnation, uint64_t revision, uint32_t binding) const {
        auto it = _bindings.find({incarnation, binding});
        return it == _bindings.end() || it->second.revision != revision || !it->second.proofs.empty();
    }
    // A negative memo suppresses only proof acquisition, never the original
    // payload/live/retention path. Revision or recording changes permit retry.
    void reject(uint64_t incarnation, uint64_t revision, uint32_t binding) {
        if (!incarnation || !revision) { return; }
        Key key{incarnation, binding};
        auto it = _bindings.find(key);
        if (it != _bindings.end()) { it->second = {revision, {}}; }
        else if (_bindings.size() < 256) { _bindings.emplace(key, Entry{revision, {}}); }
    }
    void remember(uint64_t incarnation, uint64_t revision, uint32_t binding,
                  std::vector<MVKMetal4PreparedResourceProof> proofs) {
        if (!incarnation || !revision || proofs.empty() || proofs.size() > kMaxResources) { return; }
        for (const auto& proof : proofs) { if (!proof.valid()) { return; } }
        Key key{incarnation, binding};
        auto it = _bindings.find(key);
        if (it != _bindings.end()) { it->second = {revision, std::move(proofs)}; }
        else if (_bindings.size() < 256) { _bindings.emplace(key, Entry{revision, std::move(proofs)}); }
    }
};
