// CPU-only tests of the exact registry/cache policy used by native submissions.
// No Metal device, native resource, command buffer or GPU execution is created.
#include "../../build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4AllocationLifetime.h"
#include "../../build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4PreparedResource.h"
#include <array>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using Registry = MVKMetal4AllocationLifetimes;
using Cache = MVKMetal4StableAllocationCache;
static void require(bool condition, const char* message) {
    if (!condition) { throw std::runtime_error(message); }
}
static bool sameOwner(const Registry::Token& a, const Registry::Token& b) {
    return !a.owner_before(b) && !b.owner_before(a);
}

int main() {
    std::vector<std::string> passed;
    auto test = [&](const char* name, const std::function<void()>& run) {
        run(); passed.emplace_back(name);
    };
    try {
        test("retired_identity_nodes_reused_with_fresh_flags", [] {
            struct Identity { bool retained = false; uint64_t generation = 0; };
            MVKMetal4RecycledIdentityMap<Identity, 4> values;
            int a = 0, b = 0;
            auto inserted = values.try_emplace(&a);
            require(inserted.second && !inserted.first->second.retained && inserted.first->second.generation == 0, "cold insert did not create fresh identity");
            auto* storage = &inserted.first->second;
            storage->retained = true; storage->generation = 99;
            auto duplicate = values.try_emplace(&a);
            require(!duplicate.second && values.size() == 1 && &duplicate.first->second == storage, "duplicate identity replaced");
            require(duplicate.first->second.retained && duplicate.first->second.generation == 99, "cold duplicate reset ownership flags");
            values.clear();
            require(values.size() == 0 && values.cachedNodeCount() == 1 && values.find(&a) == values.end(), "retired key persisted");
            auto reused = values.try_emplace(&b);
            require(reused.second && &reused.first->second == storage, "empty node storage not reused");
            require(!reused.first->second.retained && reused.first->second.generation == 0, "stale flags survived retirement");
            values.clear();
            reused = values.try_emplace(&a);
            require(reused.second && !reused.first->second.retained, "same address acquired old identity");
        });
        test("identity_node_cache_is_bounded_and_survives_pack_transfer", [] {
            struct Identity { uint64_t marker = 0; };
            using Identities = MVKMetal4RecycledIdentityMap<Identity, 4>;
            Identities recording, idle; std::array<int, 64> keys{};
            auto first = recording.try_emplace(&keys[0]); auto* stable = &first.first->second;
            stable->marker = 7;
            for (size_t i = 1; i < keys.size(); ++i) { recording.try_emplace(&keys[i]); }
            require(&recording.find(&keys[0])->second == stable && stable->marker == 7, "rehash invalidated identity reference");
            recording.clear();
            require(recording.cachedNodeCount() == 4 && recording.size() == 0, "node cache exceeded bound");
            require(recording.hostStorageBytes() >= 4 * sizeof(Identity), "cached node payload unaccounted");
            idle.swap(recording);
            require(recording.cachedNodeCount() == 0 && idle.cachedNodeCount() == 4, "empty pack transfer lost storage");
            Identities next; next.swap(idle);
            for (unsigned cycle = 0; cycle < 32; ++cycle) {
                for (size_t i = 0; i < 4; ++i) {
                    auto entry = next.try_emplace(&keys[i]);
                    require(entry.second && entry.first->second.marker == 0, "fresh recording inherited identity");
                    entry.first->second.marker = cycle + 1;
                    const size_t cached = next.cachedNodeCount();
                    auto duplicate = next.try_emplace(&keys[i]);
                    require(!duplicate.second && &duplicate.first->second == &entry.first->second && duplicate.first->second.marker == cycle + 1,
                            "duplicate identity changed storage or flags");
                    require(next.cachedNodeCount() == cached, "duplicate consumed recycled storage");
                }
                require(next.cachedNodeCount() == 0, "recording did not exhaust reusable nodes");
                auto cold = next.try_emplace(&keys[4]);
                require(cold.second && cold.first->second.marker == 0 && next.size() == 5, "cache exhaustion broke fresh insert");
                next.clear();
                require(next.cachedNodeCount() == 4, "repeated retire lost bounded nodes");
            }
        });
        test("null_and_unknown_have_no_incarnation", [] {
            Registry registry; int object = 0;
            registry.add(nullptr); registry.remove(nullptr); registry.remove(&object);
            require(registry.get(nullptr).expired() && registry.get(&object).expired(), "unknown admitted");
        });
        test("paired_shared_owners_preserve_one_incarnation", [] {
            Registry registry; int object = 0;
            registry.add(&object); auto token = registry.get(&object);
            registry.add(&object); require(sameOwner(token, registry.get(&object)), "duplicate changed incarnation");
            registry.remove(&object); require(!token.expired(), "one owner removed shared allocation");
            registry.remove(&object); require(token.expired(), "last owner did not expire token");
            registry.remove(&object); require(registry.get(&object).expired(), "unpaired remove resurrected token");
        });
        test("same_address_reregistration_gets_fresh_incarnation", [] {
            Registry registry; int object = 0;
            registry.add(&object); auto old = registry.get(&object);
            registry.remove(&object); registry.add(&object); auto now = registry.get(&object);
            require(old.expired() && !now.expired() && !sameOwner(old, now), "address reuse confused incarnation");
        });
        test("invalid_or_unowned_cache_entries_stay_dynamic", [] {
            Registry registry; Cache cache; int object = 0;
            require(!cache.insert(&object, registry.get(&object), 64), "unknown cached");
            registry.add(&object); auto token = registry.get(&object);
            require(!cache.insert(nullptr, token, 64), "null cached");
            require(!cache.insert(&object, token, 0), "zero-sized cached");
            require(!cache.insert(&object, token, Cache::maxBytes + 1), "oversize cached");
            require(!cache.insert(&object, token, std::numeric_limits<uint64_t>::max()), "overflow cached");
            registry.remove(&object); require(!cache.insert(&object, token, 64), "expired cached");
            require(cache.bytes() == 0 && cache.entries().empty(), "rejection changed budget");
        });
        test("exact_256_entry_cap_preserves_overflow_fallback", [] {
            Registry registry; Cache cache; std::array<int, Cache::maxCount + 1> objects{};
            for (size_t i = 0; i < objects.size(); ++i) {
                registry.add(&objects[i]);
                require(cache.insert(&objects[i], registry.get(&objects[i]), 1) == (i < Cache::maxCount), "count cap wrong");
            }
            require(cache.entries().size() == Cache::maxCount && cache.bytes() == Cache::maxCount, "count budget wrong");
            require(cache.hostStorageBytes() >= Cache::maxCount * sizeof(Cache::Entry), "metadata absent from accounting");
        });
        test("exact_8MiB_budget_and_expiry_recovery", [] {
            Registry registry; Cache cache; int a = 0, b = 0, c = 0;
            for (auto object : {&a, &b, &c}) { registry.add(object); }
            require(cache.insert(&a, registry.get(&a), 1), "first entry rejected");
            require(cache.insert(&b, registry.get(&b), Cache::maxBytes - 1), "exact limit rejected");
            require(!cache.insert(&c, registry.get(&c), 1), "byte overflow admitted");
            registry.remove(&a); size_t removals = 0;
            cache.beginRecording([&](const void* object) { require(object == &a, "wrong removal"); ++removals; });
            require(removals == 1 && cache.bytes() == Cache::maxBytes - 1, "expired bytes not returned");
            require(cache.insert(&c, registry.get(&c), 1), "released budget not reusable");
        });
        test("reused_recording_marks_usage_without_duplicate_membership", [] {
            Registry registry; Cache cache; int object = 0;
            registry.add(&object); require(cache.insert(&object, registry.get(&object), 64), "initial insert failed");
            size_t removals = 0;
            cache.beginRecording([&](const void*) { ++removals; });
            require(cache.touch(&object) && cache.touch(&object), "cache hit lost");
            require(!cache.insert(&object, registry.get(&object), 64), "duplicate membership admitted");
            cache.beginRecording([&](const void*) { ++removals; });
            require(removals == 0 && cache.bytes() == 64, "used entry pruned or double-counted");
        });
        test("unused_prior_recording_is_evicted_on_next_acquire", [] {
            Registry registry; Cache cache; int object = 0;
            registry.add(&object); cache.insert(&object, registry.get(&object), 64);
            size_t removals = 0;
            cache.beginRecording([&](const void*) { ++removals; }); // Previously used; retain once.
            cache.beginRecording([&](const void* p) { require(p == &object, "wrong unused pointer"); ++removals; });
            require(removals == 1 && cache.entries().empty() && cache.bytes() == 0, "unused cache persisted");
        });
        test("owner_expiry_during_recording_keeps_owned_object_until_next_acquire", [] {
            Registry registry; Cache cache; int object = 0;
            registry.add(&object); auto token = registry.get(&object);
            cache.insert(&object, token, 64); registry.remove(&object);
            require(token.expired(), "cache illegally owns incarnation");
            require(cache.touch(&object) && cache.bytes() == 64, "recording changed residency after owner removal");
            std::vector<const void*> removed;
            cache.beginRecording([&](const void* p) { removed.push_back(p); });
            require(removed.size() == 1 && removed.front() == &object && cache.bytes() == 0, "next acquire failed to prune");
        });
        test("old_incarnation_is_pruned_before_same_address_new_admission", [] {
            Registry registry; Cache cache; int object = 0;
            registry.add(&object); auto old = registry.get(&object); cache.insert(&object, old, 64);
            registry.remove(&object); registry.add(&object); auto now = registry.get(&object);
            require(cache.touch(&object), "recording lost owned old object");
            size_t removals = 0;
            cache.beginRecording([&](const void*) { ++removals; });
            require(removals == 1 && old.expired() && !now.expired(), "old incarnation confused with new owner");
            require(cache.insert(&object, now, 128) && cache.bytes() == 128, "new incarnation not admitted");
        });
        test("all_prune_callbacks_precede_caller_release_phase", [] {
            Registry registry; Cache cache; int a = 0, b = 0;
            for (auto p : {&a, &b}) { registry.add(p); cache.insert(p, registry.get(p), 64); registry.remove(p); }
            std::vector<const void*> pendingRelease;
            cache.beginRecording([&](const void* p) { pendingRelease.push_back(p); });
            require(pendingRelease.size() == 2 && cache.entries().empty(), "prune lost staged removals");
            // The production caller commits its Metal set at this boundary,
            // then releases this list. This tests callback staging, not Metal.
            bool committed = true;
            for (auto p : pendingRelease) { require(committed && (p == &a || p == &b), "release preceded removal phase"); }
        });
        test("concurrent_registry_owners_preserve_outer_lifetime", [] {
            Registry registry; int object = 0; registry.add(&object); auto token = registry.get(&object);
            std::array<std::thread,4> workers;
            for (auto& worker : workers) {
                worker = std::thread([&] {
                    for (unsigned i = 0; i < 2000; ++i) {
                        registry.add(&object); require(!registry.get(&object).expired(), "live owner missing"); registry.remove(&object);
                    }
                });
            }
            for (auto& worker : workers) { worker.join(); }
            require(!token.expired(), "concurrent remove consumed outer owner");
            registry.remove(&object); require(token.expired(), "registry leaked owner");
        });
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
    std::cout << "{\"scope\":\"exact production CPU allocation registry and bounded cache policy\",\"passed\":" << passed.size()
              << ",\"gpuExecuted\":false,\"tests\":[";
    for (size_t i=0; i<passed.size(); ++i) { std::cout << (i ? "," : "") << '"' << passed[i] << '"'; }
    std::cout << "]}\n";
}
