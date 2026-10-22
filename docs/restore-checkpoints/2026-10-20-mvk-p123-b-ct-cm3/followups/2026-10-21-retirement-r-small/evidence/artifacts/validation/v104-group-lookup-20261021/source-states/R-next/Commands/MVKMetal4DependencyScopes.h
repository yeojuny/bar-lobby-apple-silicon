/* Explicit cross-pass obligations. No inference from an encoder having work. */
#pragma once
#include <cstdint>

// TOP and BOTTOM have opposite meanings in the two Vulkan scopes. Other
// stages in the same mask remain intact, including unknown extension stages.
inline uint64_t mvkMetal4NormalizePipelineStages(uint64_t stages, uint64_t top,
        uint64_t bottom, uint64_t allCommands, bool source) {
    return (stages & ~(top | bottom)) |
        ((stages & (source ? bottom : top)) ? allCommands : 0);
}

template<uint64_t Vertex, uint64_t Fragment, uint64_t Dispatch, uint64_t Blit>
struct MVKMetal4DependencyScopes {
    static constexpr uint64_t all = Vertex | Fragment | Dispatch | Blit;
    static constexpr uint64_t stages[4] = {Vertex, Fragment, Dispatch, Blit};
    uint64_t sources[4] = {all, all, all, all};
    uint64_t memory[4] = {all, all, all, all};
    void add(uint64_t src, uint64_t dst, bool visible) {
        for (unsigned i = 0; i < 4; ++i) if (dst & stages[i]) {
            sources[i] |= src;
            if (visible) memory[i] |= src;
        }
    }
    uint64_t required(uint64_t dst) const {
        uint64_t src = 0;
        for (unsigned i = 0; i < 4; ++i) if (dst & stages[i]) src |= sources[i];
        return src;
    }
    bool needsVisibility(uint64_t dst) const {
        for (unsigned i = 0; i < 4; ++i) if ((dst & stages[i]) && memory[i]) return true;
        return false;
    }
    void merge(const MVKMetal4DependencyScopes& other) {
        for (unsigned i = 0; i < 4; ++i) {
            sources[i] |= other.sources[i];
            memory[i] |= other.memory[i];
        }
    }
    // Preserve stage pairs and visibility requirements at emission too. Only
    // identical source scopes are grouped; execution-only edges do not acquire
    // cache visibility merely because another destination has a memory edge.
    template<class Encode>
    void encode(uint64_t dst, Encode&& encodeBarrier) {
        for (unsigned kind = 0; kind < 2; ++kind) {
            const bool visible = kind == 0;
            uint64_t remaining = dst & all;
            for (unsigned i = 0; i < 4; ++i) {
                if (!(remaining & stages[i])) { continue; }
                const uint64_t src = visible ? memory[i] : sources[i] & ~memory[i];
                remaining &= ~stages[i];
                if (!src) { continue; }
                uint64_t consumers = stages[i];
                for (unsigned j = i + 1; j < 4; ++j) {
                    const uint64_t other = visible ? memory[j] : sources[j] & ~memory[j];
                    if ((remaining & stages[j]) && src == other) {
                        consumers |= stages[j]; remaining &= ~stages[j];
                    }
                }
                encodeBarrier(src, consumers, visible);
                satisfy(src, consumers);
            }
        }
    }
    // Call only after an actual queue barrier covers prior-pass sources.
    // Consumer barriers cover the selected destinations in subsequent passes too.
    void satisfy(uint64_t src, uint64_t dst) {
        for (unsigned i = 0; i < 4; ++i) if (dst & stages[i]) {
            sources[i] &= ~src;
            memory[i] &= ~src;
        }
    }
};

// A prepared prefix starts with empty local scopes because its actual queue
// input is not known yet. Record every destination request, including requests
// that emit no local barrier. For a fixed sequence of add/merge/consume
// operations, the entry waits for the incoming pairs consumed by that prefix;
// the exit carries the remaining incoming pairs plus its final local scopes.
// This summarizes dependency obligations, not encoder selection or GPU work.
template<uint64_t Vertex, uint64_t Fragment, uint64_t Dispatch, uint64_t Blit>
struct MVKMetal4PreparedDependencySummary {
    using Scopes = MVKMetal4DependencyScopes<Vertex, Fragment, Dispatch, Blit>;
    uint64_t consumedDestinations = 0;

    void recordConsumption(uint64_t dst) {
        consumedDestinations |= dst & Scopes::all;
    }

    Scopes resolveEntry(const Scopes& incoming) const {
        Scopes entry;
        for (unsigned i = 0; i < 4; ++i) {
            const bool consumed = consumedDestinations & Scopes::stages[i];
            entry.sources[i] = consumed ? incoming.sources[i] : 0;
            entry.memory[i] = consumed ? incoming.memory[i] : 0;
        }
        return entry;
    }

    Scopes resolveExit(const Scopes& incoming, const Scopes& local) const {
        Scopes out;
        for (unsigned i = 0; i < 4; ++i) {
            const bool consumed = consumedDestinations & Scopes::stages[i];
            out.sources[i] = (consumed ? 0 : incoming.sources[i]) | local.sources[i];
            out.memory[i] = (consumed ? 0 : incoming.memory[i]) | local.memory[i];
        }
        return out;
    }
};
