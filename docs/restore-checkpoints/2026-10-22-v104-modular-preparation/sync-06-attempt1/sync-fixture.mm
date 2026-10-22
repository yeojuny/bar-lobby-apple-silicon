// Evidence-only CPU fixture. Generated production.inc supplies the actual
// feedback/retirement, publication, event mutator and public wait bodies.
// Storage/GPU objects are inert mock boundaries; no Metal device/queue is made.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

static std::atomic<unsigned> checks{0};
#define CHECK(x) do { ++checks; if (!(x)) { std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); std::abort(); } } while (0)
enum class Phase { Recording, Ended, Submitted, Retiring, Completed };
enum class SignalNotification { None, Pending, Succeeded, Failed };
enum class GPUStorage { InUse, Reclaiming, Reclaimed };
enum class MVKMetal4CounterProof { Unknown, Ordered };
static std::atomic<uint64_t> globalCompletedSubmissions{0};
static size_t relativeComparisons = 0; // Extraction-only observation, never product code.
static std::atomic<size_t> currentReads{0};

@interface SyncEvent : NSObject <MTLSharedEvent> { uint64_t _value; }
@property uint64_t signaledValue;
@end
@implementation SyncEvent
- (uint64_t)signaledValue { ++currentReads; return _value; }
- (void)setSignaledValue:(uint64_t)value { _value = value; }
- (id<MTLDevice>)device { return nil; }
- (NSString*)label { return nil; }
- (void)setLabel:(NSString*)label { (void)label; }
- (MTLSharedEventHandle*)newSharedEventHandle { return nil; }
- (void)notifyListener:(MTLSharedEventListener*)listener atValue:(uint64_t)value block:(MTLSharedEventNotificationBlock)block {
    (void)listener; (void)value; (void)block;
}
@end
@interface SyncFeedback : NSObject { NSError* _error; }
@property(retain) NSError* error;
@end
@implementation SyncFeedback
@synthesize error = _error;
- (void)dealloc { [_error release]; [super dealloc]; }
@end

// Instrument only the fixture CV surface. The original wait predicates and
// lock hand-off remain in extracted production methods, including spurious wakes.
struct ObservedCV {
    std::condition_variable cv;
    std::atomic<unsigned> notifications{0};
    std::atomic<bool> waiting{false};
    void notify_all() { ++notifications; cv.notify_all(); }
    template<class Clock, class Duration, class Predicate>
    bool wait_until(std::unique_lock<std::mutex>& lock,
                    const std::chrono::time_point<Clock, Duration>& until, Predicate predicate) {
        bool result = cv.wait_until(lock, until, [&] {
            bool ready = predicate();
            if (!ready) { waiting.store(true, std::memory_order_release); }
            return ready;
        });
        waiting.store(false, std::memory_order_release);
        return result;
    }
};
struct MVKMetal4SubmissionGroup;
struct Storage { std::atomic<bool> poisoned{false}; id<MTLDevice> device = nil; size_t released = 0, recycled = 0; };
struct MVKMetal4ResourcePack {};
struct MVKMetal4AllocatorUse { unsigned value = 0; };
struct MVKMetal4TailRecording {
    std::unique_ptr<MVKMetal4ResourcePack> pack;
    MVKMetal4AllocatorUse allocatorUse;
    explicit operator bool() const { return bool(pack); }
};
struct MVKMetal4EventValue { id<MTLEvent> event; uint64_t value; bool internalTimelineSignal = false; };
struct MVKMetal4QueueState {
    static constexpr unsigned notificationCapacity = 64;
    std::timed_mutex submitMutex;
    std::mutex stateMutex;
    ObservedCV idle;
    uint64_t pending = 0, completed = 0;
    NSError* firstError = nil;
    std::array<std::shared_ptr<MVKMetal4SubmissionGroup>, notificationCapacity> notificationOwners;
    uint64_t freeNotificationSlots = UINT64_MAX;
    MVKMetal4CounterProof counterProof = MVKMetal4CounterProof::Ordered;
    std::shared_ptr<Storage> storage = std::make_shared<Storage>();
    NSMutableArray* failedEvents = [NSMutableArray new];
    MTLSharedEventListener* signalListener = nil;
    ~MVKMetal4QueueState() { [firstError release]; [failedEvents release]; }
};
struct MVKMetal4SubmissionState {
    mutable std::mutex mutex;
    ObservedCV done;
    Phase phase = Phase::Recording;
    NSError* error = nil;
    std::shared_ptr<MVKMetal4QueueState> owner;
    std::shared_ptr<Storage> storage;
    std::vector<std::function<void()>> cleanup;
    std::vector<std::function<void(NSError*)>> errorHandlers, completedHandlers;
    std::vector<MVKMetal4EventValue> waits, signals;
    std::vector<id> retained, transientArgumentTables;
    std::unique_ptr<MVKMetal4ResourcePack> pack = std::make_unique<MVKMetal4ResourcePack>();
    std::unique_ptr<int> completionStorage = std::make_unique<int>(1);
    MVKMetal4AllocatorUse allocatorUse;
    id buffer = nil, allocator = nil, residency = nil;
    bool externalCounterWait = false;
    unsigned gpuClears = 0, operationClears = 0, cachedCompletion = 0;
    bool retainOperationUnique(id object) { retained.push_back([object retain]); return true; }
    void clearGPUReferences() { ++gpuClears; }
    void clearOperationReferences() {
        ++operationClears;
        for (id object : retained) { [object release]; }
        retained.clear(); waits.clear(); signals.clear();
    }
    void cacheEmptyHostStorage(MVKMetal4ResourcePack&) {}
    void cacheEmptyCompletionStorage() { ++cachedCompletion; }
    ~MVKMetal4SubmissionState() { for (id object : retained) { [object release]; } [error release]; }
};
template<class Access>
void releaseAllocatorUses(const std::shared_ptr<Storage>& storage, size_t count, Access access) {
    storage->released += count;
    for (size_t i = 0; i < count; ++i) { access(i).value = 0; }
}
void recyclePack(const std::shared_ptr<Storage>& storage, std::unique_ptr<MVKMetal4ResourcePack>, bool,
                 std::unique_ptr<int> completion = nullptr) { (void)completion; ++storage->recycled; }
void recycleCompletionStorage(const std::shared_ptr<Storage>& storage, std::unique_ptr<int>) { ++storage->recycled; }
bool fail(NSError** error, NSInteger code, NSString* description) {
    if (error) { *error = [NSError errorWithDomain:@"SyncCPU" code:code userInfo:@{NSLocalizedDescriptionKey: description}]; }
    return false;
}
bool report(NSError** error, NSError* existing) { if (error) { *error = existing; } return false; }
auto deadline(uint64_t milliseconds) { return std::chrono::steady_clock::now() + std::chrono::milliseconds(milliseconds); }
struct MVKMetal4Submission {
    std::shared_ptr<MVKMetal4SubmissionState> _state;
    bool wait(uint64_t milliseconds, NSError** error) const;
};
struct MVKMetal4Queue {
    std::shared_ptr<MVKMetal4QueueState> _state;
    bool waitIdle(uint64_t milliseconds, NSError** error) const;
};
#include "production.inc"

static std::shared_ptr<MVKMetal4SubmissionGroup> makeGroup(size_t count = 2, bool submitted = true) {
    auto group = std::make_shared<MVKMetal4SubmissionGroup>();
    group->owner = std::make_shared<MVKMetal4QueueState>();
    group->phase = submitted ? Phase::Submitted : Phase::Ended;
    group->owner->pending = submitted ? 1 : 0;
    group->retirement.resize(count);
    for (size_t i = 0; i < count; ++i) {
        auto child = std::make_shared<MVKMetal4SubmissionState>();
        child->phase = group->phase;
        child->owner = group->owner;
        child->storage = group->owner->storage;
        group->children.push_back(child);
    }
    return group;
}
static void feedback(const std::shared_ptr<MVKMetal4SubmissionGroup>& group, bool tail = false,
                     size_t range = 0, NSError* error = nil) {
    SyncFeedback* item = [SyncFeedback new]; item.error = error;
    recordFeedback(group, (id<MTL4CommitFeedback>)item, tail, range);
    [item release];
}
static void finish(const std::shared_ptr<MVKMetal4SubmissionGroup>& group) {
    { std::lock_guard<std::mutex> lock(group->mutex); group->submitFinished = true; }
    retireIfReady(group);
}
static void waitArmed(ObservedCV& cv, std::mutex& mutex) {
    auto until = deadline(2000);
    while (!cv.waiting.load(std::memory_order_acquire) && std::chrono::steady_clock::now() < until) { std::this_thread::yield(); }
    CHECK(cv.waiting.load(std::memory_order_acquire));
    // Waiting publishes its flag while holding the same predicate mutex.
    // This acquire occurs only after the real wait has atomically unlocked.
    std::lock_guard<std::mutex> lock(mutex);
}
static void assertComplete(const std::shared_ptr<MVKMetal4SubmissionGroup>& group, unsigned count = 1) {
    CHECK(group->phase == Phase::Completed);
    CHECK(group->owner->pending == 0 && group->owner->completed == count);
    for (auto& child : group->children) {
        CHECK(child->phase == Phase::Completed);
        CHECK(child->gpuClears == 1 && child->operationClears == 1 && child->cachedCompletion == 1);
    }
}

static void gatePermutations() {
    std::array<int, 3> order{0, 1, 2};
    do {
        auto group = makeGroup(); unsigned cleanup = 0, completed = 0;
        for (auto& child : group->children) {
            child->cleanup.push_back([&]{ ++cleanup; });
            child->completedHandlers.push_back([&](NSError* error){ CHECK(error == nil); CHECK(cleanup == 2); ++completed; });
        }
        auto child = group->children.front();
        auto childWait = std::async(std::launch::async, [child] { @autoreleasepool {
            NSError* error = nil; CHECK(MVKMetal4Submission{child}.wait(3000, &error)); CHECK(error == nil);
        }});
        auto queueWait = std::async(std::launch::async, [group] { @autoreleasepool {
            NSError* error = nil; CHECK(MVKMetal4Queue{group->owner}.waitIdle(3000, &error)); CHECK(error == nil);
        }});
        waitArmed(child->done, child->mutex); waitArmed(group->owner->idle, group->owner->stateMutex);
        for (size_t i = 0; i < order.size(); ++i) {
            if (order[i] == 0) { feedback(group); }
            if (order[i] == 1) { feedback(group, true); }
            if (order[i] == 2) { finish(group); }
            if (i != 2) { CHECK(group->phase == Phase::Submitted); CHECK(cleanup == 0 && completed == 0); }
        }
        childWait.get(); queueWait.get(); assertComplete(group); CHECK(cleanup == 2 && completed == 2);
        CHECK(child->done.notifications == (SYNC_NOTIFY_REDUCED ? 1u : 3u));
        auto count = child->done.notifications.load();
        feedback(group); feedback(group, true); finish(group);
        CHECK(child->done.notifications == count); assertComplete(group);
    } while (std::next_permutation(order.begin(), order.end()));
}

static void rangesAndNotification() {
    auto group = makeGroup(); group->rangeFeedback.assign(3, 0); group->remainingRangeFeedback = 3;
    group->tailFeedbackDone = true; finish(group);
    feedback(group, false, 8); CHECK(group->remainingRangeFeedback == 3);
    feedback(group, false, 1); feedback(group, false, 1); CHECK(group->remainingRangeFeedback == 2);
    feedback(group, false, 2); CHECK(group->phase == Phase::Submitted);
    feedback(group, false, 0); assertComplete(group);
    CHECK(group->children.front()->done.notifications == (SYNC_NOTIFY_REDUCED ? 1u : 4u));

    group = makeGroup(); group->tailFeedbackDone = true;
    group->signalNotification = SignalNotification::Pending; group->notificationGeneration = 7;
    group->notificationSlot = 0; group->owner->notificationOwners[0] = group;
    group->owner->freeNotificationSlots &= ~uint64_t{1};
    finish(group); feedback(group);
    CHECK(group->gpuStorage == GPUStorage::Reclaimed && group->phase == Phase::Submitted);
    CHECK(group->owner->pending == 1);
    for (auto& child : group->children) { CHECK(child->gpuClears == 1 && child->operationClears == 0); }
    recordSignalNotification(group, 6); CHECK(group->phase == Phase::Submitted);
    recordSignalNotification(group, 7); assertComplete(group);
    CHECK(!group->owner->notificationOwners[0]);
    recordSignalNotification(group, 7); assertComplete(group);
}

static void errorsWakeBeforeRetirement() {
    for (bool handler : {false, true}) {
        auto group = makeGroup(); auto child = group->children.front();
        std::promise<void> handlerEntered, releaseHandler;
        auto release = releaseHandler.get_future();
        unsigned handled = 0;
        if (handler) { child->errorHandlers.push_back([&](NSError*) { ++handled; handlerEntered.set_value(); release.wait(); }); }
        auto childWait = std::async(std::launch::async, [child] { @autoreleasepool {
            NSError* error = nil; CHECK(!MVKMetal4Submission{child}.wait(3000, &error)); CHECK(error.code == 19);
        }});
        auto queueWait = std::async(std::launch::async, [group] { @autoreleasepool {
            NSError* error = nil; CHECK(!MVKMetal4Queue{group->owner}.waitIdle(3000, &error)); CHECK(error.code == 19);
        }});
        waitArmed(child->done, child->mutex); waitArmed(group->owner->idle, group->owner->stateMutex);
        auto callback = std::async(std::launch::async, [group] { @autoreleasepool {
            NSError* error = [NSError errorWithDomain:@"SyncCPU" code:19 userInfo:nil]; feedback(group, false, 0, error);
        }});
        if (handler) { CHECK(handlerEntered.get_future().wait_for(std::chrono::seconds(2)) == std::future_status::ready); }
        CHECK(childWait.wait_for(std::chrono::seconds(2)) == std::future_status::ready);
        CHECK(queueWait.wait_for(std::chrono::seconds(2)) == std::future_status::ready);
        childWait.get(); queueWait.get();
        CHECK(child->gpuClears == 0 && group->owner->pending == 1);
        CHECK(group->owner->storage->poisoned.load());
        if (handler) { CHECK(handled == 1 && group->errorHandlersRunning); releaseHandler.set_value(); }
        callback.get(); CHECK(!group->errorHandlersRunning);
        feedback(group); CHECK(group->owner->pending == 1);
        finish(group); CHECK(group->phase == Phase::Submitted);
        feedback(group, true); assertComplete(group);
    }
    // A different group's error poisons/detaches pending signal owners. Its GPU
    // cleanup still requires that group's own actual feedback gates.
    auto pending = makeGroup(); pending->signalNotification = SignalNotification::Pending;
    pending->notificationSlot = 0; pending->owner->notificationOwners[0] = pending;
    pending->owner->freeNotificationSlots &= ~uint64_t{1};
    NSError* error = [NSError errorWithDomain:@"SyncCPU" code:21 userInfo:nil];
    failSignalNotificationOwners(pending->owner, error);
    CHECK(pending->error.code == 21 && pending->signalNotification == SignalNotification::Failed);
    CHECK(pending->gpuStorage == GPUStorage::InUse && pending->owner->pending == 1);
    finish(pending); feedback(pending); feedback(pending, true); assertComplete(pending);
}

static void addSignal(const std::shared_ptr<MVKMetal4SubmissionState>& child, SyncEvent* event, uint64_t value) {
    child->phase = Phase::Recording; NSError* error = nil;
    CHECK(addEvent(child, event, value, true, &error)); CHECK(error == nil); child->phase = Phase::Ended;
}
static bool publish(const std::shared_ptr<MVKMetal4SubmissionGroup>& group, NSError** error
#if SYNC_HAS_PROOF
                    , const GroupSignalOrderProof* proof = nullptr
#endif
                    ) {
    SubmissionChildLocks locks(group->children); NotificationSlotReservation slot(group->owner);
    return publishPreparedSubmission(group, locks, {}, false, slot, error
#if SYNC_HAS_PROOF
                                     , proof
#endif
                                     );
}
static void signalCases() {
    SyncEvent* first = [SyncEvent new]; SyncEvent* second = [SyncEvent new]; NSError* error = nil;
    // Different events, repeated signals, and zero signals all retain live checks.
    for (unsigned count : {0u, 1u, 4u, 16u}) {
        auto group = makeGroup(2, false);
        for (unsigned i = 0; i < count; ++i) { addSignal(group->children[i % 2], i % 3 ? first : second, i + 1); }
        // Populate in each child's work order, so assign strictly increasing
        // values in the actual child-major traversal before proving.
        uint64_t value = 1;
        for (auto& child : group->children) { for (auto& signal : child->signals) { signal.value = value++; } }
        relativeComparisons = 0; currentReads = 0;
#if SYNC_HAS_PROOF
        GroupSignalOrderProof proof;
        CHECK(validateAndProveGroupSignals(*group, &error, proof)); CHECK(proof.covers(*group));
#else
        CHECK(validGroupSignals(*group, &error));
#endif
        size_t firstPairs = relativeComparisons;
        CHECK(currentReads == count);
        CHECK(publish(group, &error
#if SYNC_HAS_PROOF
                      , &proof
#endif
                      ));
        CHECK(currentReads == count * 2);
        CHECK(relativeComparisons == firstPairs * (SYNC_HAS_PROOF ? 1 : 2));
        // Legal mutator rejection, including after proof's Ended claim.
        CHECK(!addEvent(group->children.front(), first, 999, true, &error));
    }
    for (uint64_t bad : {uint64_t{0}, uint64_t{4}, uint64_t{3}}) {
        auto group = makeGroup(2, false);
        addSignal(group->children[0], first, 4);
        if (bad) { addSignal(group->children[1], first, bad); }
        else { group->children[1]->signals.push_back({first, 0, false}); }
        CHECK(!publish(group, &error)); CHECK(error.code == 3 && group->owner->pending == 0);
    }
#if SYNC_HAS_PROOF
    auto valid = makeGroup(1, false); addSignal(valid->children[0], first, 2);
    GroupSignalOrderProof proof, empty;
    CHECK(validateAndProveGroupSignals(*valid, &error, proof));
    // Current event value can change legally outside the signal-array proof.
    first.signaledValue = 2; CHECK(!publish(valid, &error, &proof));
    CHECK(error.code == 3 && valid->phase == Phase::Ended && valid->owner->pending == 0);
    first.signaledValue = 0;
    auto invalid = makeGroup(2, false); addSignal(invalid->children[0], first, 7); addSignal(invalid->children[1], first, 6);
    CHECK(!publish(invalid, &error, &proof)); // Wrong-group proof falls back.
    CHECK(!publish(invalid, &error, &empty)); // Default proof falls back.
    CHECK(!validateAndProveGroupSignals(*invalid, &error, proof));
    CHECK(!proof.covers(*valid) && !proof.covers(*invalid));
    CHECK(validateAndProveGroupSignals(*valid, &error, proof));
    auto child = valid->children.front();
    CHECK(!addEvent(child, first, 3, true, &error)); // Ended API immutability.
    CHECK(child->signals.size() == 1);
    child->phase = Phase::Recording; CHECK(!publish(valid, &error, &proof)); child->phase = Phase::Ended;
    child->owner.reset(); CHECK(!publish(valid, &error, &proof)); child->owner = valid->owner;
    CHECK(publish(valid, &error, &proof));
#endif
    [first release]; [second release];
}

int main() { @autoreleasepool {
    gatePermutations(); rangesAndNotification(); errorsWakeBeforeRetirement(); signalCases();
    std::printf("PASS sync CPU checks=%u proof=%d reducedNotify=%d; no GPU or Metal queue created\n",
                checks.load(), SYNC_HAS_PROOF, SYNC_NOTIFY_REDUCED);
} return 0; }
