// Opt-in, bounded host/GPU timing evidence. Does not change synchronization.
#pragma once
#include <cstdint>
#include <cstddef>

// Shipping excludes custom collectors; development fixtures opt in explicitly.
#ifndef MVK_ENABLE_CUSTOM_DIAGNOSTICS
#define MVK_ENABLE_CUSTOM_DIAGNOSTICS 0
#endif

enum class MVKBackendTimelineKind : uint32_t {
    QueueDelay = 1, QueueExecute, CommandReplay, NativeEnd,
    NativeSubmit, SubmitLock, TailSetup, WorkCommit, SignalPresent, TailCommit,
    GPUWork, GPUTail, CallbackEntry, MandatoryCleanup, CompletionHandlers,
    CacheRecycle, SemaphoreWait, FenceWait, QueueSignal, QueueFence, Present,
    SemaphoreSignal, WaitTarget, SubmitTarget, RetireReady,
    CostRecordBegin = 101, CostRecordEnd, CostRecordReset, CostQueueDelay,
    CostQueueExecute, CostReplay, CostCommitBegin, CostCommit, CostFeedback,
    CostHostWait, CostWaitTarget,
    CostEpochArm, CostEpochClose, CostRoot,
};

enum MVKBackendCostFlags : uint32_t {
    MVKCostPresent = 1u, MVKCostError = 2u, MVKCostUnavailable = 4u,
    MVKCostTail = 8u, MVKCostMixed = 16u, MVKCostCancelled = 32u,
    MVKCostSecondary = 64u, MVKCostPoll = 128u, MVKCostWaitAny = 256u,
    MVKCostFence = 512u, MVKCostEmulated = 1024u,
    MVKCostDependencySeed = 4096u,
};
struct MVKBackendCostObject { uint64_t id = 0, generation = 0; };
enum class MVKBackendCostObjectKind : uint32_t { CommandBuffer = 1, Queue, Fence };

// On-disk little-endian, native IEEE754 double. No pointers or object ownership.
struct MVKBackendTimelineEvent {
    double begin, end;
    uint64_t thread, entity, related, value;
    uint32_t kind, flags;
    double aux0, aux1;
};
static_assert(sizeof(MVKBackendTimelineEvent) == 72, "timeline record layout");

#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
class MVKBackendTimeline {
public:
    static double clock();
    uint64_t nextID();
    void record(MVKBackendTimelineKind kind, double begin, double end,
                uint64_t entity = 0, uint64_t related = 0, uint64_t value = 0,
                uint32_t flags = 0, double aux0 = 0, double aux1 = 0);
    // One terminal dump after Vulkan device/queue cleanup. Never in draw loops.
    void dump();
    // Fixed sidecar allocated only ON. No Vulkan/Metal object gains a field.
    MVKBackendCostObject object(const void* key, MVKBackendCostObjectKind kind, bool create = true);
    void forget(const void* key, MVKBackendCostObjectKind kind);
    void recordingBegin(const void* key, double begin, uint32_t flags);
    void recordingEnd(const void* key, int32_t result, bool cancel = false);
    void recordingReset(const void* key);
    void fenceReset(const void* key);
    void feedback(uint64_t group, uint64_t queue, uint64_t range, uint32_t flags,
                  double start, double end, double callback);
    bool isCostProfile() const;
    size_t storageBytes() const;
    // v3: only new roots are gated. Numeric descendants survive close.
    void admitRoot(uint64_t id, uint64_t queue, uint32_t kind, double begin);
    bool prepareCommit(uint64_t group, uint64_t task);
    MVKBackendCostObject replayDependency(const void* key, uint64_t task);
    static uint64_t taskContext(uint64_t task);
private:
    explicit MVKBackendTimeline(bool cost = false, bool epoch = false);
    void publish(MVKBackendTimelineKind kind, double begin, double end,
                 uint64_t entity, uint64_t related, uint64_t value,
                 uint32_t flags, double aux0, double aux1, uint64_t thread = 0);
    bool control(uint32_t sequence, uint64_t frame, double relative);
    static void* controlThread(void* capture);
    struct Storage;
    Storage* _storage;
    friend MVKBackendTimeline* mvkBackendTimeline();
    friend MVKBackendTimeline* mvkBackendTimelineIdentity();
};

// Cached OFF unless both ENV flag=1 and an absolute new output path are present.
// Enabled collector storage has process lifetime, avoiding teardown callback UAF.
MVKBackendTimeline* mvkBackendTimeline();
// Historical hooks return nullptr under cost-minimal-v2, before clocks or IDs.
MVKBackendTimeline* mvkBackendCostTimeline();
MVKBackendTimeline* mvkBackendTimelineIdentity();

// Construct immediately before the existing commit call, destroy immediately
// after. Feedback can precede the rows: analysis joins by numeric IDs, not order.
class MVKBackendCostCommitScope {
public:
    MVKBackendCostCommitScope(MVKBackendTimeline* capture, uint64_t group, uint64_t queue,
                              uint64_t range, uint32_t flags, uint64_t task)
        : _capture(capture && capture->prepareCommit(group, task) ? capture : nullptr),
          _group(group), _queue(queue), _range(range), _task(task), _flags(flags),
          _begin(_capture ? _capture->clock() : 0) {}
    ~MVKBackendCostCommitScope() {
        if (!_capture) { return; }
        double end = _capture->clock();
        _capture->record(MVKBackendTimelineKind::CostCommitBegin, _begin, _begin,
                         _group, _queue, _range, _flags, double(_task));
        _capture->record(MVKBackendTimelineKind::CostCommit, _begin, end,
                         _group, _queue, _range, _flags, double(_task));
    }
private:
    MVKBackendTimeline* _capture;
    uint64_t _group, _queue, _range, _task;
    uint32_t _flags;
    double _begin;
};

class MVKBackendCostTaskContext {
public:
    explicit MVKBackendCostTaskContext(uint64_t task)
        : _previous(task ? MVKBackendTimeline::taskContext(task) : 0), _enabled(task != 0) {}
    ~MVKBackendCostTaskContext() { if (_enabled) { MVKBackendTimeline::taskContext(_previous); } }
private:
    uint64_t _previous;
    bool _enabled;
};

#else
// No clocks, storage, TLS, control files, or environment opt-in in this build.
class MVKBackendTimeline {
public:
    static constexpr double clock() { return 0; }
    constexpr uint64_t nextID() { return 0; }
    void record(MVKBackendTimelineKind, double, double, uint64_t = 0, uint64_t = 0,
                uint64_t = 0, uint32_t = 0, double = 0, double = 0) {}
    void dump() {}
    MVKBackendCostObject object(const void*, MVKBackendCostObjectKind, bool = true) { return {}; }
    void forget(const void*, MVKBackendCostObjectKind) {}
    void recordingBegin(const void*, double, uint32_t) {}
    void recordingEnd(const void*, int32_t, bool = false) {}
    void recordingReset(const void*) {}
    void fenceReset(const void*) {}
    void feedback(uint64_t, uint64_t, uint64_t, uint32_t, double, double, double) {}
    constexpr bool isCostProfile() const { return false; }
    constexpr size_t storageBytes() const { return 0; }
    void admitRoot(uint64_t, uint64_t, uint32_t, double) {}
    constexpr bool prepareCommit(uint64_t, uint64_t) { return false; }
    MVKBackendCostObject replayDependency(const void*, uint64_t) { return {}; }
    static constexpr uint64_t taskContext(uint64_t) { return 0; }
};
inline constexpr MVKBackendTimeline* mvkBackendTimeline() { return nullptr; }
inline constexpr MVKBackendTimeline* mvkBackendCostTimeline() { return nullptr; }
inline constexpr MVKBackendTimeline* mvkBackendTimelineIdentity() { return nullptr; }
class MVKBackendCostCommitScope {
public:
    MVKBackendCostCommitScope(MVKBackendTimeline*, uint64_t, uint64_t, uint64_t, uint32_t, uint64_t) {}
};
class MVKBackendCostTaskContext {
public:
    explicit MVKBackendCostTaskContext(uint64_t) {}
};
#endif
