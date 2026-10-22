/* Copyright (c) 2026. Licensed under the Apache License, Version 2.0. */
#pragma once

#import <Metal/Metal.h>
#include <memory>
#include <cstdint>
#include <functional>
#include <array>
#include <mutex>
#include <vector>
#include "MVKBackendTimeline.h"
#include "../Commands/MVKMetal4DependencyScopes.h"

using MVKMetal4RecordingDependencies = MVKMetal4DependencyScopes<
    MTLStageVertex, MTLStageFragment, MTLStageDispatch, MTLStageBlit>;

struct MVKMetal4QueueState;
struct MVKMetal4SubmissionState;
struct MVKMetal4RecordingPoolState;
class MVKMetal4RecordingPool;
class MVKMetal4ArgumentTables;
class MVKMetal4PreparedGroupCache;

// Allocation owners register once. GPU recordings take leases whose final
// release, rather than the Vulkan wrapper's destruction, removes residency.
// Unknown allocations stay on the existing per-submission residency path.
class API_AVAILABLE(macos(26.0), ios(26.0)) MVKMetal4DeviceResidency {
public:
    static std::shared_ptr<MVKMetal4DeviceResidency> create(id<MTLDevice> device, NSError** error = nullptr);
    ~MVKMetal4DeviceResidency();
    bool registerAllocation(id<MTLAllocation> allocation, NSError** error = nullptr);
    void unregisterAllocation(id<MTLAllocation> allocation);
    std::shared_ptr<void> lease(id<MTLResource> resource) const;
    void commit();
    id<MTLDevice> device() const;
    id<MTLResidencySet> residencySet() const;
private:
    struct Storage;
    explicit MVKMetal4DeviceResidency(std::unique_ptr<Storage> storage);
    std::unique_ptr<Storage> _storage;
};

// Backend-neutral, private cost qualification. Off unless the exact environment
// value MVK_CONFIG_BACKEND_COST_STATS=1 is set before this process starts.
// No GPU commands, counter heaps, waits, or per-submission logging are added.
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
bool mvkBackendCostStatsEnabled();
#else
inline constexpr bool mvkBackendCostStatsEnabled() { return false; }
#endif

struct MVKMetal4Upload {
    id<MTLBuffer> buffer = nil;
    NSUInteger offset = 0;
};

// CPU bookkeeping only; successful object creation/reuse, not GPU timings.
struct MVKMetal4ResourcePoolStats {
    uint64_t primaryCreated = 0, primaryReused = 0;
    uint64_t tailCreated = 0, tailReused = 0;
    uint64_t allocatorCreated = 0, allocatorReused = 0, allocatorResets = 0;
    uint64_t allocatorDiscarded = 0, allocatorAvailable = 0;
    uint64_t primaryIdle = 0, tailIdle = 0, idleBytes = 0;
    uint64_t uploadSlabsCreated = 0, uploadSlabsReused = 0;
    uint64_t argumentTableGroupsCreated = 0, argumentTableGroupsReused = 0;
    uint64_t argumentTableGroupsIdle = 0;
    uint64_t hostStorageReused = 0, hostStorageIdleBytes = 0;
    // Foundation does not expose NSMutableArray backing capacity/bytes. Count
    // its retained high-water slots separately from measurable container bytes.
    uint64_t retainedObjectSlotsIdle = 0;
    static constexpr uint64_t maxIdlePacksPerKind = 8;
    static constexpr uint64_t maxIdleBytes = 64 * 1024 * 1024;
    // Native end returns exclusive recording service; all users still retain
    // command memory until cancellation or proven GPU retirement. Seal at either
    // count or capacity-growth bound, reset only after the last user. Existing
    // native heap capacity may survive reset and is charged to maxIdleBytes.
    static constexpr uint32_t maxAllocatorEpochRecordings = 32;
    static constexpr size_t maxAvailableAllocatorEpochs = 8;
    static constexpr uint64_t maxAllocatorEpochGrowthBytes = 2 * 1024 * 1024;
    static constexpr uint64_t maxUploadSlabsPerPack = 8;
    // Metal does not expose table allocatedSize; bound their count separately.
    static constexpr uint64_t maxArgumentTableGroupsPerPack = 16;
    static constexpr size_t maxHostIdentityBuckets = 2048;
    static constexpr size_t maxRetainedHostObjects = 1024;
    static constexpr size_t maxHostVectorEntries = 128;
    static constexpr uint64_t maxHostStoragePayloadBytes = 64 * 1024;
};

// Successful unique registrations and registry traversals, not GPU timing.
struct MVKMetal4ResourceRegistrationStats {
    uint64_t retainedObjects = 0, residentResources = 0, drawableRegistryLookups = 0;
    uint64_t deviceResidencyLeases = 0;
};

// Optional CPU encoding counts, not GPU timing or completed-work counts.
// Conversion reasons overlap. Indirect counts are bound-derived upper limits;
// only directInputCountSum records CPU-known actual conversion input counts.
struct MVKMetal4EncodingStats {
    uint64_t drawCalls = 0, indirectDrawCalls = 0, converted = 0;
    uint64_t provokingVertex = 0, listRestart = 0, stripRestart = 0;
    uint64_t fan = 0, uint8Indices = 0, restartKernelCalls = 0;
    // Encoded dispatches using the explicit fused-restart experiment, not the
    // number of GPU no-sentinel branches or completed draws.
    uint64_t fusedRestartKernelCalls = 0;
    uint64_t batchedRestartDispatches = 0, batchedRestartDraws = 0;
    uint64_t maxInputCountSum = 0, maxInputCountMax = 0;
    uint64_t directInputCountSum = 0, indirectBoundCountSum = 0;
    uint64_t scratchBytes = 0, renderWasActive = 0;
    uint64_t prepassBatches = 0, preconvertedDraws = 0, renderPasses = 0;
    uint64_t prepassHandoffBatches = 0, prepassLeadingOrdinaryDraws = 0;
    uint64_t prepassDeferredWaits = 0, prepassHandoffFallbacks = 0;
    uint64_t fusedSignalSubmits = 0;
    uint64_t computePasses = 0, computeBarrierContinuations = 0;
    uint64_t independentCopyRegions = 0, clearHelperRestores = 0;
    uint64_t indirectConversionBatches = 0, indirectBatchedDraws = 0, indirectBatchFallbacks = 0;
    // MAB shader-used texture/sampler binding visits, not unique resources or
    // GPU texture accesses. Hits skip a previously validated payload walk.
    uint64_t textureBindingVisits = 0, textureCacheEligible = 0;
    uint64_t textureCacheHits = 0, textureCacheMisses = 0, textureHitResourceSlots = 0;
    uint64_t textureNegativeMemoSkips = 0, textureProofAttempts = 0;
    // ProofReady counts complete proof acquisition before remember(); it does
    // not claim insertion into the bounded cache or surviving token validity.
    uint64_t textureProofReady = 0, textureProofRejected = 0;
    uint64_t directTextureBindings = 0;
    uint64_t indirectGroupChecks = 0, indirectGroupHits = 0, indirectGroupPreparations = 0;
    // Mutually exclusive pipeline proof categories, in logical draw units.
    uint64_t invariantNoFlatDraws = 0, invariantAdmittedDraws = 0;
    uint64_t invariantExternalWritesDraws = 0, invariantBuiltinsDraws = 0;
    uint64_t invariantLayoutDraws = 0, invariantProofRejectedDraws = 0, invariantUnsupportedDraws = 0;
};

#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
class MVKBackendCostStats {
public:
    static constexpr size_t maxBins = 300;
    struct Bin {
        uint64_t cpuCount = 0, waitCount = 0, workCount = 0, tailCount = 0;
        double cpuSum = 0, cpuMax = 0, waitSum = 0;
        double workSum = 0, workMax = 0, tailSum = 0;
        double firstGPU = 0, lastGPU = 0, queueDelaySum = 0, feedbackLagSum = 0;
        uint64_t presentCount = 0;
        double presentSum = 0, presentMax = 0, presentFirstGPU = 0, presentLastGPU = 0;
        double presentQueueDelaySum = 0, presentFeedbackLagSum = 0;
        MVKMetal4EncodingStats encoding;
        uint64_t encodingCount = 0;
        double encodingFirstRecordHost = 0, encodingLastRecordHost = 0;
    };
    struct Snapshot {
        std::array<Bin, maxBins> bins{};
        uint64_t invalidCPU = 0, invalidGPU = 0, invalidEncoding = 0, outsideWindow = 0;
    };
    explicit MVKBackendCostStats(const char* backend);
    ~MVKBackendCostStats();
    static double hostSeconds(); // mach_absolute_time, scaled to seconds.
    void recordCPU(double start, double end, bool semaphoreWait = false);
    void recordGPU(double start, double end, double commit, double callback, bool tail,
                   bool presentation = false);
    // One merge per stats delivery: command-buffer data arrives after CPU
    // encoding; fusedSignalSubmits metadata arrives before queue commit.
    // Neither record counts nor bins denote GPU execution or completion.
    void recordEncoding(const MVKMetal4EncodingStats& stats, double recordHost);
    Snapshot snapshot() const;
    double originHostSeconds() const { return _originHost; }
private:
    const char* _backend;
    double _originHost = 0, _originUnixMS = 0;
    mutable std::mutex _mutex;
    Snapshot _data;
};
static_assert(sizeof(MVKBackendCostStats) < 256 * 1024, "Fixed 300-bin diagnostic storage is bounded.");

#else
class MVKBackendCostStats {
public:
    static constexpr double hostSeconds() { return 0; }
    void recordCPU(double, double, bool = false) {}
    void recordGPU(double, double, double, double, bool, bool = false) {}
    void recordEncoding(const MVKMetal4EncodingStats&, double) {}
};
#endif

struct MVKMetal4QueueEncodingStats {
    MVKMetal4EncodingStats encoding;
    uint64_t endedBatches = 0, submittedBatches = 0, completedBatches = 0;
};

// Internal experimental backend selection. Only the exact value "1" enables it;
// callers must still validate native queue creation and device support.
bool mvkUseMetal4();
// Enables local counting for an explicit batch, queue or backend-cost mode.
// Cost-only mode emits neither per-submission nor queue-stats lines.
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
bool mvkMetal4StatsEnabled();
#else
inline constexpr bool mvkMetal4StatsEnabled() { return false; }
#endif
// MVK_CONFIG_METAL4_QUEUE_STATS=1: aggregate encoded work, one teardown line.
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
bool mvkMetal4QueueStatsEnabled();
#else
inline constexpr bool mvkMetal4QueueStatsEnabled() { return false; }
#endif
// Integration proof for callers above Vulkan that cannot obtain its VkQueue.
// Counts terminal native submission retirement, not environment selection.
extern "C" uint64_t mvkGetMetal4GlobalCompletedSubmissionCount();

// A presentable image registers its current drawable's base texture and removes
// it before releasing that drawable. Views are resolved through parentTexture.
// Registration owns a drawable reference; each referencing batch owns its own.
bool mvkRegisterMetal4Drawable(id<MTLTexture> texture, id<MTLDrawable> drawable, NSError** error = nullptr);
void mvkUnregisterMetal4Drawable(id<MTLTexture> texture, id<MTLDrawable> drawable);
// Only for newly created device/heap/buffer textures, never imported handles or
// CAMetalLayer textures. Texture views inherit their actual parent's metadata.
void mvkMarkMetal4OrdinaryTexture(id<MTLTexture> texture);
void mvkInheritMetal4TextureOwnership(id<MTLTexture> texture, id<MTLTexture> parent);

// Explicitly eligible, Metal-owned nonheap buffer allocations only. These hooks
// track owner incarnations; they never mutate a GPU-visible residency set.
void mvkRegisterMetal4StableBuffer(id<MTLBuffer> buffer);
void mvkUnregisterMetal4StableBuffer(id allocation);

// Native Metal 4 encoding lifetime. This does not implement or impersonate any
// legacy Metal command protocol. The Vulkan encoder will consume this directly.
// Recording is confined to one thread. Every encoder must end before end().
class API_AVAILABLE(macos(26.0), ios(26.0)) MVKMetal4Submission {
public:
    ~MVKMetal4Submission();
    MVKMetal4Submission(const MVKMetal4Submission&) = delete;
    MVKMetal4Submission& operator=(const MVKMetal4Submission&) = delete;

    // Borrowed, recording-only handle; the submission owns buffer and allocator.
    id<MTL4CommandBuffer> commandBuffer() const;
    // All encoders must be ended. Counter writes have no MTLStages identity.
    // Establish the prior queue prefix once, then use command-buffer timestamp
    // ordering. Only a first timestamp may reuse a submitted opaque-write
    // completion proof with a real All-to-Blit marker bridge. Resolves retain
    // the full queue wait, including writes in this recording.
    // The native splits keep one exclusive allocator writer and one resource
    // owner; no work is committed until the whole submission is adopted.
    bool writeTimestamp(id<MTL4CounterHeap> heap, NSUInteger index, NSError** error = nullptr);
    bool resolveCounterHeap(id<MTL4CounterHeap> heap, NSRange range,
                            MTL4BufferRange destination, NSError** error = nullptr,
                            bool resultsAlreadyComplete = false);
    // Conservative recording hint only: it can require a full wait, never
    // authorize elision. Call before recording the first counter boundary.
    void requireFullCounterEntry();
    // Private 4-byte completion storage, reused only after both native work/tail
    // feedbacks and submit scheduling finish. Actual signal observation may lag.
    // Borrowed recording-only handle; reserved for the queue completion fill.
    id<MTLBuffer> completionMarker(NSError** error = nullptr);
    // Recording-only proof that native signals and their retirement proof
    // cover all prior queue GPU work. Requires at least one signal and no
    // event waits, drawable waits or presentations. The Vulkan caller must also
    // exclude its own wait semaphores before omitting a primary completion fill.
    // Does not replace signal completion, work feedback or error quarantine.
    bool hasSignalTailCompletionCoverage() const;
    // Immutable diagnostic ID, zero when the optional timeline is disabled.
    uint64_t diagnosticIdentity() const;
    // Retains a GPU binding object through native work/tail feedback and submit
    // scheduling. Event/drawable registration separately owns queue-operation
    // objects through semantic completion; retainObject alone is not that proof.
    bool retainObject(id object, NSError** error = nullptr);
    // Keeps the resource alive AND includes it in this batch's residency set.
    // Indirectly referenced allocations must also be registered by the caller.
    bool addResource(id<MTLResource> resource, NSError** error = nullptr);
    // Creation/acquisition metadata supplies an exact drawable incarnation.
    // Zero identifies a proven non-drawable texture, whose recording retention
    // needs no drawable invalidation. Unknown/external textures keep the global
    // registry fallback; UINT64_MAX disables mutable-source memoization.
    static uint64_t drawableRegistrationGeneration(id<MTLTexture> texture = nil);
    static uint64_t drawableRegistryEpoch();
    MVKMetal4ResourceRegistrationStats resourceRegistrationStats() const;
    // Recording-thread state, shared only by sequential Vulkan encoders in
    // this native recording. A new submission starts with an unknown prefix.
    MVKMetal4RecordingDependencies& dependencyScopes();
    // Borrowed recording-only table lease, unique within this submission.
    // It must not be deleted or accessed after retirement/cancellation. Exact
    // limits/stages are reused only from this queue's retired ResourcePack;
    // overflow remains transient. GPU referenced resources still need residency.
    MVKMetal4ArgumentTables* acquireArgumentTables(NSUInteger bufferCount, NSUInteger textureCount,
                                                  NSUInteger samplerCount, bool computeOnly,
                                                  NSError** error = nullptr);
    // Return only a full-stage primary lease after ALL of its CPU encoders end.
    // Metal snapshots table entries at draw/dispatch. Clearing entries here does
    // not release the table, immutable uploads or batch-owned GPU resources.
    // A cached group may be reacquired in this recording; transient overflow is
    // acknowledged once but retained without reuse until GPU storage retirement.
    // Never return compute-only helper leases, whose recording lifetimes overlap.
    bool releaseArgumentTables(MVKMetal4ArgumentTables* tables, NSError** error = nullptr);
    // Queue-level timeline operations; register while recording. A nil-device
    // shared event is permitted; other events must belong to this device.
    // Values are strictly increasing timeline values (including binary tickets).
    // Signal callers must obey Metal/Vulkan ordering, including host signals
    // below every pending queue signal. Observable already-high signals reject
    // before queue mutation; concurrent invalid host advancement is unsupported.
    // Only MVK-owned, non-imported/non-exportable Vulkan semaphores may preserve
    // the existing local counter proof. Their wait still executes in full; it
    // never closes an open proof. Generic/imported waits remain conservative.
    bool addWaitEvent(id<MTLEvent> event, uint64_t value, NSError** error = nullptr,
                      bool internalSemaphoreWait = false);
    // Only MVK's non-imported/non-exportable Vulkan timeline semaphore path may
    // supply internalTimelineSignal=true. One such signal without waits or
    // drawables may use actual-value notification instead of a retirement tail.
    // Generic events, binary signals and all other submissions keep the tail.
    bool addSignalEvent(id<MTLEvent> event, uint64_t value, NSError** error = nullptr,
                        bool internalTimelineSignal = false);
    // Queues signalDrawable and then present only after the workload commit.
    // beforePresent installs handlers and applies presentation mode immediately
    // before present. It must not throw, block, submit, or wait on the queue.
    bool addPresentation(id<MTLDrawable> drawable, double timeSeconds,
                         std::function<void()> beforePresent, NSError** error = nullptr);
    // Called once on GPU completion, or cancellation of an unsubmitted batch.
    // Must not throw, block, submit, or wait on this queue/batch. Capture an owning
    // pool lease when returning pooled memory; a raw pool pointer is insufficient.
    bool deferRelease(std::function<void()> cleanup, NSError** error = nullptr);
    // Submitted batches only. Error handlers run once on the first GPU error;
    // completed handlers retain the actual event/tail semantic gate, after GPU
    // resource retirement, mandatory cleanup and error handlers. When already
    // full-ready, they run before idle-cache reset/publication. GPU storage can
    // instead retire while an actual signal observer is pending; completion then
    // waits for that cleanup/cache owner to finish. wait()/waitIdle() still observe
    // Completed only after all mandatory cleanup and cache maintenance finishes.
    // NSError is borrowed during the call. Neither callback may block, throw,
    // submit, or wait on this queue/batch. Unsubmitted cancellation invokes none.
    bool addErrorHandler(std::function<void(NSError*)> handler, NSError** error = nullptr);
    bool addCompletedHandler(std::function<void(NSError*)> handler, NSError** error = nullptr);
    // Publish shared host state only after successful queue adoption, in submit
    // order and before native work is committed. Cancellation discards actions.
    // Actions must own their targets and must not throw, block, or call this batch.
    bool deferUntilSubmit(std::function<void()> action, NSError** error = nullptr);
    // +0 result, held through GPU storage retirement. Replaces inline bytes.
    id<MTLBuffer> uploadBytes(const void* bytes, NSUInteger length, NSError** error = nullptr);
    // Immutable CPU-uploaded data, backed by submission-owned shared slabs.
    // The 256-byte-aligned slice remains unchanged through GPU retirement.
    // Callers must use the returned offset and must not write into the slice.
    MVKMetal4Upload uploadBytesRange(const void* bytes, NSUInteger length, NSError** error = nullptr);
    // Direct primitive-helper inputs only: upload immutable parameters, retain
    // the pipeline object, and register argument/optional index buffers under
    // one recording lock. Callers already own these objects; no live-descriptor
    // lookup or drawable texture is accepted. Failure returns no upload.
    MVKMetal4Upload uploadBytesRangeWithPrimitiveInputs(const void* bytes, NSUInteger length,
        id pipelineObject, id<MTLBuffer> arguments, id<MTLBuffer> indices,
        NSError** error = nullptr);
    // Non-owning identity for submission-local immutable-slice caches. A retained
    // buffer alone does not preserve slice contents after retirement/reuse.
    // Weak ownership identity remains distinct even if state addresses are reused.
    std::weak_ptr<void> recordingToken() const;
    bool matchesRecordingToken(const std::weak_ptr<void>& token) const;
    // Values only, shared by sequential Vulkan encoders in this native recording.
    // Recording-thread access only; never reused by a later GPU recording.
    MVKMetal4PreparedGroupCache& preparedGroupCache();
    // Merge once per encoder while recording. Disabled diagnostics are a no-op.
    // A successful end() emits a line only with MVK_CONFIG_METAL4_STATS=1.
    void addEncodingStats(const MVKMetal4EncodingStats& stats);
    bool end(NSError** error = nullptr);
    // A GPU error may return before retirement; completed() then remains false
    // and GPU-referenced storage stays owned until terminal feedback arrives.
    bool wait(uint64_t timeoutMilliseconds, NSError** error = nullptr) const;
    bool completed() const;

private:
    friend class MVKMetal4Queue;
    friend class MVKMetal4RecordingPool;
    explicit MVKMetal4Submission(std::shared_ptr<MVKMetal4SubmissionState> state);
    // Caller holds the recording mutex and has checked Phase::Recording.
    MVKMetal4Upload uploadBytesRangeLocked(const void* bytes, NSUInteger length, NSError** error);
    bool splitForCounterCompletionLocked(bool timestampEntry, NSError** error);
    std::shared_ptr<MVKMetal4SubmissionState> _state;
};

// Device storage, independent of any queue or Vulkan command pool. A recording
// exclusively owns its pack until cancellation or terminal GPU retirement.
// Ended recordings may share allocator memory while their resource packs remain
// exclusive. Open native recordings require distinct allocators; no GPU wait.
class API_AVAILABLE(macos(26.0), ios(26.0)) MVKMetal4RecordingPool {
public:
    static std::shared_ptr<MVKMetal4RecordingPool> create(id<MTLDevice> device,
        NSError** error = nullptr, std::shared_ptr<MVKMetal4DeviceResidency> residency = {});
    ~MVKMetal4RecordingPool();
    std::shared_ptr<MVKMetal4Submission> begin(NSError** error = nullptr, bool presentation = false);
    MVKMetal4ResourcePoolStats resourcePoolStats() const;
private:
    friend class MVKMetal4Queue;
    explicit MVKMetal4RecordingPool(std::shared_ptr<MVKMetal4RecordingPoolState> state);
    std::shared_ptr<MVKMetal4RecordingPoolState> _state;
};

// Owns a real MTL4CommandQueue. Outstanding work owns its queue state and all
// referenced objects even if the caller destroys the queue/submission wrappers.
// waitIdle observes all submitted batches (not unsubmitted recording batches).
// Normal event references retire with their owning batch: work feedback follows
// input waits and signal-wait tail feedback or an eligible actual-value
// notification follows valid signals. Notification callbacks own only weak
// references; a fixed-capacity queue owner table holds outstanding batches.
// Failed outstanding batches quarantine events until native queue teardown;
// a poisoned queue accepts no new work, so normal churn cannot grow quarantine.
class API_AVAILABLE(macos(26.0), ios(26.0)) MVKMetal4Queue {
public:
    static std::unique_ptr<MVKMetal4Queue> create(id<MTLDevice> device, NSError** error = nullptr,
        std::shared_ptr<MVKMetal4DeviceResidency> residency = {},
        std::shared_ptr<MVKMetal4RecordingPool> recordingPool = {});
    ~MVKMetal4Queue();
    MVKMetal4Queue(const MVKMetal4Queue&) = delete;
    MVKMetal4Queue& operator=(const MVKMetal4Queue&) = delete;
    // Cost classification only. Queue-present primary feedback is separate
    // from ordinary Vulkan command work; its synthetic tails stay tails.
    std::shared_ptr<MVKMetal4Submission> begin(NSError** error = nullptr, bool presentation = false);
    std::shared_ptr<MVKMetal4RecordingPool> recordingPool() const;
    bool counterEntryNeedsFullWait() const;
    bool submit(const std::shared_ptr<MVKMetal4Submission>& submission, NSError** error = nullptr,
                uint64_t costTask = 0, uint64_t costQueue = 0);
    // Adopt ended, distinct recordings atomically in their Vulkan submit order.
    // Every child must use this queue's recording storage; dependency boundaries
    // are encoded by the caller. Ordinary records use one native array commit.
    // Counter completion splits retain array ranges; only a proven first
    // timestamp entry may omit its queue signal/wait pair. Every range's
    // feedback protects the group's single retirement gate.
    // Metadata may reside in a final empty child.
    // Preparation failure leaves all children unsubmitted and host actions
    // unpublished. A published group is never rolled back to Ended.
    bool submit(const std::vector<std::shared_ptr<MVKMetal4Submission>>& submissions,
                NSError** error = nullptr, uint64_t costTask = 0, uint64_t costQueue = 0);
    bool waitIdle(uint64_t timeoutMilliseconds, NSError** error = nullptr) const;
    uint64_t completedSubmissionCount() const;
    MVKMetal4ResourcePoolStats resourcePoolStats() const;
    // Queue diagnostic snapshot. Encoding includes ended-but-cancelled batches;
    // submitted/completed counts are separate. No GPU timing is collected.
    MVKMetal4QueueEncodingStats encodingStats() const;
    // Shared collector survives outstanding feedback; null in ordinary launches.
    std::shared_ptr<MVKBackendCostStats> costStats() const;
    // Poison future submissions and wake idle waiters without signaling GPU
    // events. Fail owned notifications and deliver their error handlers; each
    // batch still requires its work feedback and finished submit before resource
    // retirement and any workload completion handler.
    void notifyDeviceLost();

private:
    explicit MVKMetal4Queue(std::shared_ptr<MVKMetal4QueueState> state);
    std::shared_ptr<MVKMetal4QueueState> _state;
};
