class MVKMetal4PreparedGroupCache {
    using Proof = MVKMetal4PreparedGroupSnapshot::RecordingProofRef;
    struct Entry { MVKMetal4PreparedGroupStamp stamp; Proof proof; };
    std::unordered_map<uint64_t, Entry> _groups;
public:
    struct Lookup { bool complete = false; Proof partial; };
    void clear() { _groups.clear(); }
    template<class Revision, class StableStamp>
    Lookup lookup(const MVKMetal4PreparedGroupStamp& stamp, const Revision& revision, const StableStamp& stableStamp) {
        if (!stamp.script || !stamp.setMask || (stamp.setMask >> MVKMetal4PreparedGroupStamp::kMaxSets)) { return {}; }
        auto entry = _groups.find(stamp.script);
        // Every stored stamp passed valid() at admission or stabilized refresh.
        // Exact equality therefore needs no repeat validity scan, shared_ptr
        // copy, proof scan or callback. Nonexact paths keep full validation.
        if (entry != _groups.end() && entry->second.stamp == stamp) { return {true, {}}; }
        if (!stamp.valid() || entry == _groups.end()) { return {}; }
        const auto& proof = entry->second.proof;
        if (!proof || !entry->second.stamp.sameIdentity(stamp) ||
            (!proof->drawableIndependent && entry->second.stamp.epochs[4] != stamp.epochs[4]) ||
            !proof->matchesBindings(stamp, revision)) { return {}; }
        for (const auto& resource : proof->resources) {
            if (!resource.proof.valid()) { return {}; }
        }
        // Changes during validation cannot publish a refreshed epoch stamp.
        if (!(stamp == stableStamp())) { return {}; }
        // Covered resources are already retained. Residual bindings must run
        // before remember() can publish a complete preparation for this stamp.
        if (!proof->residual.empty()) { return {false, proof}; }
        entry->second.stamp = stamp;
        return {true, {}};
    }
    void remember(const MVKMetal4PreparedGroupStamp& before, const MVKMetal4PreparedGroupStamp& after,
                  Proof proof = {}) {
        if (!before.valid() || !(before == after)) { return; }
        if (proof && !proof->stamp.sameIdentity(before)) { return; }
        auto entry = _groups.find(before.script);
        if (entry != _groups.end()) { entry->second = {before, std::move(proof)}; }
        else if (_groups.size() < 128) { _groups.emplace(before.script, Entry{before, std::move(proof)}); }
    }
};
