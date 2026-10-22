// Bounded opt-in timing capture; one binary write after normal process teardown.
#include "MVKBackendTimeline.h"
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
#include <atomic>
#include <chrono>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <limits>
#include <mutex>
#include <mach/mach_time.h>
#include <new>
#include <pthread.h>
#include <thread>
#include <sys/stat.h>
#include <unistd.h>

namespace {
constexpr uint64_t Capacity = 6 * 1024 * 1024;
constexpr uint64_t CostCapacity = 196608, ObjectCapacity = 8192;
constexpr uint64_t RootCapacity = 16384, GroupCapacity = 32768;
constexpr size_t ControlSlot = 512, HelperStack = 128 * 1024;
thread_local uint64_t currentCostTask = 0;
struct CostObject {
    uintptr_t key = 0;
    uint64_t id = 0, generation = 0;
    double begin = 0;
    uint32_t kind = 0, flags = 0, state = 0; // 0 empty, 1 live, 2 tombstone
};
// v2 sidecar/layout is unchanged. Extra metadata is allocated only under v3.
struct GenerationSeed {
    double begin = 0, end = 0;
    uint64_t beginThread = 0, endThread = 0, generation = 0, emitted = 0;
    uint32_t flags = 0;
    int32_t result = 0;
};
struct EpochRoot { uint64_t id = 0, parent = 0; uint32_t kind = 0, finished = 0; };
struct EpochGroup { uint64_t id = 0, task = 0; };
struct Header {
    char magic[8];
    uint32_t version, recordBytes;
    uint64_t capacity, reserved, committed, dropped, invalid, incomplete;
    double originHost, originUnixMS;
};
static_assert(sizeof(Header) == 80, "timeline header layout");
struct CostHeader { Header base; uint64_t storageBytes, metadataFailures, late, activeRecords; };
static_assert(sizeof(CostHeader) == 112, "cost header layout");
struct EpochHeader {
    CostHeader cost;
    uint64_t phase, roots, groups, incompleteRoots, controlFailures, helperStackBytes,
             controlCount, armFrame, closeFrame;
    double armHost, closeHost, armRelative, closeRelative;
};
static_assert(sizeof(EpochHeader) == 216, "epoch header layout");
bool writeAll(int fd, const void* data, size_t size) {
    auto* bytes = static_cast<const char*>(data);
    while (size) {
        ssize_t n = write(fd, bytes, size);
        if (n < 0 && errno == EINTR) { continue; }
        if (n <= 0) { return false; }
        bytes += n; size -= size_t(n);
    }
    return true;
}
uint64_t threadID() {
    static thread_local const uint64_t id = [] {
        uint64_t value = 0;
        pthread_threadid_np(nullptr, &value);
        return value;
    }();
    return id;
}
}

struct MVKBackendTimeline::Storage {
    MVKBackendTimelineEvent* events = nullptr;
    std::atomic<uint8_t>* ready = nullptr;
    char* path = nullptr;
    std::atomic<uint64_t> next {0}, ids {1}, invalid {0}, writers {0};
    std::atomic<uint64_t> late {0}, metadataFailures {0}, activeRecords {0};
    std::atomic<bool> sealed {false};
    // Minimal profile keeps its exclusive output descriptor until process exit.
    // Late events saturate the header's rejection flag; payload stays immutable.
    std::atomic<int> snapshotFD {-1};
    std::atomic<bool> lateWriteFailed {false};
    double originHost = 0, originUnixMS = 0;
    uint64_t capacity = Capacity;
    bool cost = false;
    CostObject* objects = nullptr;
    std::mutex objectMutex;
    std::mutex dumpMutex;
    bool epoch = false;
    GenerationSeed* seeds = nullptr;
    EpochRoot* roots = nullptr;
    EpochGroup* groups = nullptr;
    std::mutex epochMutex;
    uint64_t phase = 0, rootCount = 0, groupCount = 0, controlCount = 0;
    uint64_t armFrame = 0, closeFrame = 0;
    std::atomic<uint64_t> helperBytes {0};
    double armHost = 0, closeHost = 0, armRelative = 0, closeRelative = 0;
    std::atomic<uint64_t> controlFailures {0};
    std::atomic<bool> stopHelper {false};
    pthread_t helper {};
    bool helperStarted = false;
    int controlFD = -1, ackFD = -1;
    char* controlPath = nullptr;
    char token[65] {}, acceptedRequest[2][ControlSlot] {};
    EpochRoot* root(uint64_t id, bool create = false) {
        if (!id) { return nullptr; }
        for (uint64_t i = 0; i < RootCapacity; ++i) {
            auto& r = roots[(id + i) % RootCapacity];
            if (r.id == id) { return &r; }
            if (!r.id) { if (create) { r.id = id; ++rootCount; return &r; } return nullptr; }
        }
        if (create) { metadataFailures.fetch_add(1); }
        return nullptr;
    }
    EpochGroup* group(uint64_t id, bool create = false) {
        if (!id) { return nullptr; }
        for (uint64_t i = 0; i < GroupCapacity; ++i) {
            auto& g = groups[(id + i) % GroupCapacity];
            if (g.id == id) { return &g; }
            if (!g.id) { if (create) { g.id = id; ++groupCount; return &g; } return nullptr; }
        }
        if (create) { metadataFailures.fetch_add(1); }
        return nullptr;
    }
    void markLate() {
        late.fetch_add(1, std::memory_order_relaxed);
        int fd = snapshotFD.load(std::memory_order_acquire);
        if (fd < 0) { return; }
        const uint64_t one = 1;
        ssize_t written;
        do { written = pwrite(fd, &one, sizeof(one), offsetof(CostHeader, late)); }
        while (written < 0 && errno == EINTR);
        if (written != ssize_t(sizeof(one)) && !lateWriteFailed.exchange(true)) {
            std::fprintf(stderr, "[mvk-backend-timeline] late-header-update-failed\n");
        }
    }
    CostObject* find(const void* key, MVKBackendCostObjectKind kind, bool create, uint64_t fresh) {
        uintptr_t address = reinterpret_cast<uintptr_t>(key);
        size_t firstFree = ObjectCapacity;
        size_t start = ((address >> 4) ^ (address >> 19) ^ uint32_t(kind)) % ObjectCapacity;
        for (size_t i = 0; i < ObjectCapacity; ++i) {
            size_t slot = (start + i) % ObjectCapacity;
            auto& item = objects[slot];
            if (item.state == 1 && item.key == address && item.kind == uint32_t(kind)) { return &item; }
            if (item.state != 1 && firstFree == ObjectCapacity) { firstFree = slot; }
            if (!item.state) { break; }
        }
        if (!create) { return nullptr; }
        if (firstFree == ObjectCapacity || !fresh) { metadataFailures.fetch_add(1); return nullptr; }
        auto& item = objects[firstFree];
        item = {address, fresh, 1, 0, uint32_t(kind), 0, 1};
        return &item;
    }
};

double MVKBackendTimeline::clock() {
#ifdef MVK_BACKEND_TIMELINE_TEST_HOOK
    extern void mvkTimelineTestAction(uint32_t, uint64_t);
    mvkTimelineTestAction(1, 0);
#endif
    static const double scale = [] {
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        return double(info.numer) / double(info.denom) * 1e-9;
    }();
    return double(mach_absolute_time()) * scale;
}

MVKBackendTimeline::MVKBackendTimeline(bool cost, bool epoch) : _storage(new (std::nothrow) Storage) {
    if (!_storage) { return; }
    auto& s = *_storage;
    s.cost = cost; s.epoch = epoch; s.capacity = cost ? CostCapacity : Capacity;
#ifdef MVK_BACKEND_TIMELINE_TEST_HOOK
    extern void mvkTimelineTestAction(uint32_t, uint64_t);
    mvkTimelineTestAction(2, s.capacity);
#endif
    s.path = strdup(std::getenv("MVK_CONFIG_BACKEND_TIMELINE_FILE"));
    s.events = static_cast<MVKBackendTimelineEvent*>(std::malloc(s.capacity * sizeof(MVKBackendTimelineEvent)));
    s.ready = new (std::nothrow) std::atomic<uint8_t>[s.capacity];
    if (cost) { s.objects = new (std::nothrow) CostObject[ObjectCapacity]; }
    if (epoch) {
        s.seeds = new (std::nothrow) GenerationSeed[ObjectCapacity];
        s.roots = new (std::nothrow) EpochRoot[RootCapacity];
        s.groups = new (std::nothrow) EpochGroup[GroupCapacity];
    }
    if (!s.path || !s.events || !s.ready || (cost && !s.objects) ||
        (epoch && (!s.seeds || !s.roots || !s.groups))) {
        std::free(s.path); std::free(s.events); delete[] s.ready; delete[] s.objects;
        delete[] s.seeds; delete[] s.roots; delete[] s.groups;
        delete _storage; _storage = nullptr;
        return;
    }
    for (uint64_t i = 0; i < s.capacity; ++i) { s.ready[i].store(0, std::memory_order_relaxed); }
    s.originHost = clock();
    s.originUnixMS = std::chrono::duration<double, std::milli>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

MVKBackendTimeline* mvkBackendTimelineIdentity() {
    static MVKBackendTimeline* const capture = []() -> MVKBackendTimeline* {
        const char* flag = std::getenv("MVK_CONFIG_BACKEND_TIMELINE");
        const char* path = std::getenv("MVK_CONFIG_BACKEND_TIMELINE_FILE");
        if (!flag || std::strcmp(flag, "1") || !path || path[0] != '/' || std::strlen(path) > 4095) { return nullptr; }
        const char* profile = std::getenv("MVK_CONFIG_BACKEND_TIMELINE_PROFILE");
        bool cost = profile && !std::strcmp(profile, "cost-minimal-v2");
        bool epoch = profile && !std::strcmp(profile, "cost-epoch-window-v3");
        cost = cost || epoch;
        if (profile && profile[0] && !cost && std::strcmp(profile, "r46-timeline-v1")) { return nullptr; }
        // Conflicting diagnostics cannot silently qualify as the minimal profile.
        if (cost) {
            for (auto name : {"MVK_CONFIG_BACKEND_COST_STATS", "MVK_CONFIG_METAL4_STATS",
                              "MVK_CONFIG_METAL4_QUEUE_STATS", "MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE"}) {
                const char* v = std::getenv(name);
                if (v && v[0] && std::strcmp(v, "0")) { return nullptr; }
            }
            if (access(path, F_OK) == 0 || errno != ENOENT) { return nullptr; }
        }
        const char* controlPath = std::getenv("MVK_CONFIG_BACKEND_TIMELINE_CONTROL");
        const char* token = std::getenv("MVK_CONFIG_BACKEND_TIMELINE_TOKEN");
        if (epoch && (!controlPath || controlPath[0] != '/' || std::strlen(controlPath) > 4091 ||
                      !token || std::strlen(token) != 64 || std::strspn(token, "0123456789abcdef") != 64)) { return nullptr; }
        auto* value = new (std::nothrow) MVKBackendTimeline(cost, epoch);
        if (!value || !value->_storage) { delete value; return nullptr; }
        if (epoch) {
            auto& s = *value->_storage;
            s.controlPath = strdup(controlPath); std::memcpy(s.token, token, 65);
            struct stat info {};
            s.controlFD = open(controlPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
            char ackPath[4096]; std::snprintf(ackPath, sizeof(ackPath), "%s.ack", controlPath);
            if (!s.controlPath || s.controlFD < 0 || fstat(s.controlFD, &info) || !S_ISREG(info.st_mode) ||
                info.st_uid != getuid() || (info.st_mode & 0777) != 0600 || info.st_nlink != 1 || info.st_size != 2 * ControlSlot ||
                !std::strcmp(controlPath, path)) { s.controlFailures.fetch_add(1); }
            else {
                s.ackFD = open(ackPath, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
                if (s.ackFD < 0 || ftruncate(s.ackFD, 2 * ControlSlot)) { s.controlFailures.fetch_add(1); }
            }
            pthread_attr_t attr; bool attrReady = pthread_attr_init(&attr) == 0;
            const size_t guard = size_t(getpagesize());
            // Reserve a bounded margin for runtime stack alignment/instrumentation.
            // The helper reports its actual stack + requested guard before control.
            s.helperBytes = HelperStack + guard + 64 * 1024;
            if (!attrReady || s.controlFailures.load() || value->storageBytes() > 16 * 1024 * 1024 ||
                pthread_attr_setstacksize(&attr, HelperStack) || pthread_attr_setguardsize(&attr, guard) ||
                pthread_create(&s.helper, &attr, MVKBackendTimeline::controlThread, value)) { s.controlFailures.fetch_add(1); }
            else { s.helperStarted = true; }
            if (attrReady) { pthread_attr_destroy(&attr); }
        }
        if (std::atexit([] { if (auto* c = mvkBackendTimelineIdentity()) { c->dump(); } }) != 0) {
            // No capture is preferable to silently collecting data that cannot be emitted.
            value->_storage->sealed.store(true, std::memory_order_relaxed);
            return nullptr;
        }
        return value;
    }();
    return capture;
}

MVKBackendTimeline* mvkBackendTimeline() {
    auto* capture = mvkBackendTimelineIdentity();
    return capture && !capture->isCostProfile() ? capture : nullptr;
}
MVKBackendTimeline* mvkBackendCostTimeline() {
    auto* capture = mvkBackendTimelineIdentity();
    return capture && capture->isCostProfile() ? capture : nullptr;
}
bool MVKBackendTimeline::isCostProfile() const { return _storage->cost; }
size_t MVKBackendTimeline::storageBytes() const {
    auto& s = *_storage;
    return sizeof(*this) + sizeof(Storage) + std::strlen(s.path) + 1 +
        s.capacity * (sizeof(MVKBackendTimelineEvent) + sizeof(std::atomic<uint8_t>)) +
        (s.cost ? ObjectCapacity * sizeof(CostObject) : 0) +
        (s.epoch ? ObjectCapacity * sizeof(GenerationSeed) + RootCapacity * sizeof(EpochRoot) +
            GroupCapacity * sizeof(EpochGroup) + s.helperBytes.load() + (s.controlPath ? std::strlen(s.controlPath) + 1 : 0) +
            4 * ControlSlot + 4096 + sizeof(pthread_attr_t) + sizeof(struct stat) : 0) +
        (s.epoch ? sizeof(EpochHeader) : sizeof(CostHeader));
}

uint64_t MVKBackendTimeline::nextID() {
#ifdef MVK_BACKEND_TIMELINE_TEST_HOOK
    extern void mvkTimelineTestAction(uint32_t, uint64_t);
    mvkTimelineTestAction(3, 0);
#endif
    if (_storage->sealed.load(std::memory_order_acquire)) { return 0; }
    auto& ids = _storage->ids;
    uint64_t current = ids.load(std::memory_order_relaxed);
    const uint64_t limit = _storage->cost ? (uint64_t(1) << 53) : std::numeric_limits<uint64_t>::max();
    while (current != limit) {
        if (ids.compare_exchange_weak(current, current + 1, std::memory_order_relaxed)) { return current; }
    }
    _storage->invalid.fetch_add(1, std::memory_order_relaxed);
    return 0;
}

uint64_t MVKBackendTimeline::taskContext(uint64_t task) {
#ifdef MVK_BACKEND_TIMELINE_TEST_HOOK
    extern void mvkTimelineTestAction(uint32_t, uint64_t);
    mvkTimelineTestAction(5, task);
#endif
    uint64_t previous = currentCostTask; currentCostTask = task; return previous;
}

void MVKBackendTimeline::admitRoot(uint64_t id, uint64_t queue, uint32_t kind, double begin) {
    auto& s = *_storage;
    if (!s.epoch) { return; }
    std::lock_guard<std::mutex> lock(s.epochMutex);
    // A wait inside an admitted queue task is a descendant, even after close.
    auto* parent = kind == 2 ? s.root(currentCostTask) : nullptr;
    if (s.phase != 1 && !parent) { return; }
    if (s.sealed.load()) { s.markLate(); return; }
    auto* r = s.root(id, true);
    if (!r) { return; }
    if (r->kind) { s.metadataFailures.fetch_add(1); return; }
    r->kind = parent ? 3 : kind; r->parent = parent ? currentCostTask : queue;
    double admitted = clock();
    publish(MVKBackendTimelineKind::CostRoot, admitted, admitted, id, r->parent, r->kind, 0, begin, double(s.phase));
}

bool MVKBackendTimeline::prepareCommit(uint64_t group, uint64_t task) {
    auto& s = *_storage;
    if (!s.epoch) { return true; }
    std::lock_guard<std::mutex> lock(s.epochMutex);
    auto* root = s.root(task);
    if (!root || root->kind != 1) { return false; }
    auto* g = s.group(group, true);
    if (!g) { return false; }
    if (g->task && g->task != task) { s.metadataFailures.fetch_add(1); return false; }
    g->task = task; return true;
}

MVKBackendCostObject MVKBackendTimeline::replayDependency(const void* key, uint64_t task) {
    auto& s = *_storage;
    if (!s.epoch) { return object(key, MVKBackendCostObjectKind::CommandBuffer, false); }
    { std::lock_guard<std::mutex> lock(s.epochMutex); if (!s.root(task)) { return {}; } }
    std::lock_guard<std::mutex> lock(s.objectMutex);
    auto* item = s.find(key, MVKBackendCostObjectKind::CommandBuffer, false, 0);
    if (!item) { s.metadataFailures.fetch_add(1); return {}; }
    auto& seed = s.seeds[item - s.objects];
    if (item->begin || seed.generation != item->generation || !seed.end || seed.result ||
        (seed.flags & MVKCostCancelled)) { s.metadataFailures.fetch_add(1); return {item->id, item->generation}; }
    if (seed.emitted != seed.generation) {
        seed.emitted = seed.generation;
        publish(MVKBackendTimelineKind::CostRecordBegin, seed.begin, seed.begin,
            item->id, 0, seed.generation, seed.flags | MVKCostDependencySeed, 0, 0, seed.beginThread);
        publish(MVKBackendTimelineKind::CostRecordEnd, seed.begin, seed.end,
            item->id, 0, seed.generation, seed.flags | MVKCostDependencySeed, double(seed.result), 0, seed.endThread);
    }
    return {item->id, item->generation};
}

bool MVKBackendTimeline::control(uint32_t sequence, uint64_t frame, double relative) {
    auto& s = *_storage;
    std::lock_guard<std::mutex> lock(s.epochMutex);
    if (s.sealed.load() || sequence != s.controlCount + 1 || sequence > 2 ||
        frame != (sequence == 1 ? 480u : 840u) || !std::isfinite(relative) || relative < 0 ||
        (sequence == 2 && relative <= s.armRelative)) { s.controlFailures.fetch_add(1); return false; }
    double t = clock();
    if (sequence == 1) { s.armHost = t; s.armFrame = frame; s.armRelative = relative; }
    else { s.closeHost = t; s.closeFrame = frame; s.closeRelative = relative; }
    s.phase = sequence; s.controlCount = sequence;
    publish(sequence == 1 ? MVKBackendTimelineKind::CostEpochArm : MVKBackendTimelineKind::CostEpochClose,
        t, t, sequence, 0, frame, 0, relative, 0);
    return true;
}

void* MVKBackendTimeline::controlThread(void* context) {
    auto* capture = static_cast<MVKBackendTimeline*>(context); auto& s = *capture->_storage;
    const uint64_t actualStack = pthread_get_stacksize_np(pthread_self()) + size_t(getpagesize());
#ifdef MVK_BACKEND_TIMELINE_TEST_HOOK
    extern void mvkTimelineTestAction(uint32_t, uint64_t);
    mvkTimelineTestAction(4, actualStack);
#endif
    if (actualStack > s.helperBytes.load()) { s.controlFailures.fetch_add(1); return nullptr; }
    s.helperBytes.store(actualStack);
    if (capture->storageBytes() > 16 * 1024 * 1024) { s.controlFailures.fetch_add(1); return nullptr; }
    uint32_t next = 1;
    while (!s.stopHelper.load(std::memory_order_acquire)) {
        char first[ControlSlot], second[ControlSlot];
        const off_t offset = off_t(next - 1) * ControlSlot;
        ssize_t n = pread(s.controlFD, first, ControlSlot, offset);
        if (n == ssize_t(ControlSlot) && !std::memcmp(first + ControlSlot - 8, "READY03\n", 8)) {
            if (pread(s.controlFD, second, ControlSlot, offset) != n || std::memcmp(first, second, ControlSlot)) {
                std::this_thread::sleep_for(std::chrono::milliseconds(20)); continue;
            }
            char magic[8] {}, token[65] {}, action[8] {}, extra = 0;
            unsigned sequence = 0; unsigned long long frame = 0; double relative = 0;
            // The protocol body must be NUL terminated before the commit marker.
            if (!std::memchr(first, '\0', ControlSlot - 8) ||
                std::sscanf(first, "%7s %64s %u %7s %llu %lf %c", magic, token, &sequence, action, &frame, &relative, &extra) != 6 ||
                std::strcmp(magic, "R92E03") || std::strcmp(token, s.token) || sequence != next ||
                std::strcmp(action, next == 1 ? "arm" : "close") || !capture->control(sequence, frame, relative)) {
                s.controlFailures.fetch_add(1); break;
            }
            std::memcpy(s.acceptedRequest[next - 1], first, ControlSlot);
            char ack[ControlSlot] {};
            double host = next == 1 ? s.armHost : s.closeHost;
            std::snprintf(ack, ControlSlot - 8, "R92E03 %s %u %s %llu %.17g %.17g\n", s.token, next, action, frame, relative, host);
            // Publish the body before the completion marker; private reader accepts only the marker.
            if (pwrite(s.ackFD, ack, ControlSlot - 8, offset) != ssize_t(ControlSlot - 8) ||
                pwrite(s.ackFD, "READY03\n", 8, offset + ControlSlot - 8) != 8) { s.controlFailures.fetch_add(1); break; }
            if (++next > 2) {
                // Completed control stays read-only. Reject any later rewrite, no re-arm.
                while (!s.stopHelper.load(std::memory_order_acquire)) {
                    for (unsigned i = 0; i < 2; ++i) {
                        if (pread(s.controlFD, first, ControlSlot, off_t(i) * ControlSlot) != ssize_t(ControlSlot) ||
                            std::memcmp(first, s.acceptedRequest[i], ControlSlot)) {
                            s.controlFailures.fetch_add(1); return nullptr;
                        }
                    }
                    std::this_thread::sleep_for(std::chrono::milliseconds(20));
                }
                break;
            }
        } else if (n != ssize_t(ControlSlot)) { s.controlFailures.fetch_add(1); break; }
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    return nullptr;
}

void MVKBackendTimeline::record(MVKBackendTimelineKind kind, double begin, double end,
                               uint64_t entity, uint64_t related, uint64_t value,
                               uint32_t flags, double aux0, double aux1) {
    auto& s = *_storage;
    if (s.epoch) {
        std::lock_guard<std::mutex> lock(s.epochMutex);
        EpochRoot* root = nullptr;
        switch (kind) {
            case MVKBackendTimelineKind::CostQueueDelay:
            case MVKBackendTimelineKind::CostQueueExecute: root = s.root(entity); if (!root || root->kind != 1) { return; } break;
            case MVKBackendTimelineKind::CostReplay: root = s.root(related); if (!root || root->kind != 1) { return; } break;
            case MVKBackendTimelineKind::CostHostWait:
            case MVKBackendTimelineKind::CostWaitTarget: root = s.root(entity); if (!root || root->kind < 2) { return; } break;
            case MVKBackendTimelineKind::CostCommitBegin:
            case MVKBackendTimelineKind::CostCommit:
            case MVKBackendTimelineKind::CostFeedback: if (!s.group(entity)) { return; } break;
            default: return; // Recording sidecar publishes selected dependency seeds directly.
        }
        if (root && (kind == MVKBackendTimelineKind::CostQueueExecute || kind == MVKBackendTimelineKind::CostHostWait)) {
            if (root->finished++) { s.metadataFailures.fetch_add(1); }
        }
    }
    publish(kind, begin, end, entity, related, value, flags, aux0, aux1);
}

void MVKBackendTimeline::publish(MVKBackendTimelineKind kind, double begin, double end,
                               uint64_t entity, uint64_t related, uint64_t value,
                               uint32_t flags, double aux0, double aux1, uint64_t thread) {
    auto& s = *_storage;
    if (s.cost != (uint32_t(kind) >= 101)) { return; }
    if (s.sealed.load(std::memory_order_acquire)) { s.markLate(); return; }
    // Sequential order across the two admission atomics prevents dump and a
    // new writer from both observing the other side's old value.
    s.writers.fetch_add(1, std::memory_order_seq_cst);
#ifdef MVK_BACKEND_TIMELINE_TEST_HOOK
    extern void mvkTimelineTestAdmittedWriter();
    mvkTimelineTestAdmittedWriter();
#endif
    if (s.sealed.load(std::memory_order_seq_cst)) {
        s.markLate();
        s.writers.fetch_sub(1, std::memory_order_seq_cst); return;
    }
    if (!std::isfinite(begin) || !std::isfinite(end) || begin < 0 || end < begin ||
        !std::isfinite(aux0) || !std::isfinite(aux1)) {
        s.invalid.fetch_add(1, std::memory_order_relaxed);
    } else {
        uint64_t index = s.next.fetch_add(1, std::memory_order_relaxed);
        if (index < s.capacity) {
            s.events[index] = {begin, end, thread ? thread : threadID(), entity, related, value,
                               uint32_t(kind), flags, aux0, aux1};
            s.ready[index].store(1, std::memory_order_release);
        }
    }
    s.writers.fetch_sub(1, std::memory_order_seq_cst);
}

MVKBackendCostObject MVKBackendTimeline::object(const void* key, MVKBackendCostObjectKind kind, bool create) {
    auto& s = *_storage;
    if (!s.cost || !key || s.sealed.load(std::memory_order_acquire)) { return {}; }
    std::lock_guard<std::mutex> lock(s.objectMutex);
    auto* item = s.find(key, kind, false, 0);
    if (!item && create) { item = s.find(key, kind, true, nextID()); }
    return item ? MVKBackendCostObject{item->id, item->generation} : MVKBackendCostObject{};
}
void MVKBackendTimeline::forget(const void* key, MVKBackendCostObjectKind kind) {
    auto& s = *_storage;
    if (!s.cost) { return; }
    std::lock_guard<std::mutex> lock(s.objectMutex);
    if (auto* item = s.find(key, kind, false, 0)) {
        if (s.epoch) { s.seeds[item - s.objects] = {}; }
        item->state = 2;
    }
}
void MVKBackendTimeline::recordingBegin(const void* key, double begin, uint32_t flags) {
    auto info = object(key, MVKBackendCostObjectKind::CommandBuffer);
    if (!info.id) { return; }
    auto& s = *_storage;
    std::lock_guard<std::mutex> lock(s.objectMutex);
    auto* item = s.find(key, MVKBackendCostObjectKind::CommandBuffer, false, 0);
    if (item->begin) { s.metadataFailures.fetch_add(1); return; }
    if (++item->generation == 0) { s.metadataFailures.fetch_add(1); return; }
    item->begin = begin; item->flags = flags; s.activeRecords.fetch_add(1);
    if (s.epoch) {
        auto& seed = s.seeds[item - s.objects]; seed = {};
        seed.begin = begin; seed.beginThread = threadID();
    }
    record(MVKBackendTimelineKind::CostRecordBegin, begin, begin, item->id, 0, item->generation, flags);
}
void MVKBackendTimeline::recordingEnd(const void* key, int32_t result, bool cancel) {
    auto& s = *_storage;
    if (!s.cost || s.sealed.load(std::memory_order_acquire)) { return; }
    std::lock_guard<std::mutex> lock(s.objectMutex);
    auto* item = s.find(key, MVKBackendCostObjectKind::CommandBuffer, false, 0);
    if (!item || !item->begin) { return; }
    double end = clock();
    if (s.epoch) {
        auto& seed = s.seeds[item - s.objects]; seed.end = end; seed.endThread = threadID();
        seed.generation = item->generation; seed.result = result;
        seed.flags = item->flags | (cancel ? MVKCostCancelled : 0u) | (result ? MVKCostError : 0u);
    }
    record(MVKBackendTimelineKind::CostRecordEnd, item->begin, end, item->id, 0, item->generation,
           item->flags | (cancel ? MVKCostCancelled : 0u) | (result ? MVKCostError : 0u), double(result));
    item->begin = 0; s.activeRecords.fetch_sub(1);
}
void MVKBackendTimeline::recordingReset(const void* key) {
    recordingEnd(key, 0, true);
    auto info = object(key, MVKBackendCostObjectKind::CommandBuffer, false);
    if (_storage->epoch) {
        std::lock_guard<std::mutex> lock(_storage->objectMutex);
        if (auto* item = _storage->find(key, MVKBackendCostObjectKind::CommandBuffer, false, 0)) {
            _storage->seeds[item - _storage->objects].generation = 0;
        }
    }
    if (info.id) { double t = clock(); record(MVKBackendTimelineKind::CostRecordReset, t, t, info.id, 0, info.generation); }
}
void MVKBackendTimeline::fenceReset(const void* key) {
    auto info = object(key, MVKBackendCostObjectKind::Fence);
    if (!info.id) { return; }
    auto& s = *_storage;
    std::lock_guard<std::mutex> lock(s.objectMutex);
    auto* item = s.find(key, MVKBackendCostObjectKind::Fence, false, 0);
    if (++item->generation == 0) { s.metadataFailures.fetch_add(1); }
}
void MVKBackendTimeline::feedback(uint64_t group, uint64_t queue, uint64_t range, uint32_t flags,
                                  double start, double end, double callback) {
    bool valid = std::isfinite(start) && std::isfinite(end) && start > 0 && end >= start;
    if (!valid || (flags & MVKCostError)) { flags |= MVKCostUnavailable; start = end = callback; }
    record(MVKBackendTimelineKind::CostFeedback, start, end, group, queue, range, flags, callback);
}

void MVKBackendTimeline::dump() {
    auto& s = *_storage;
    std::lock_guard<std::mutex> dumpLock(s.dumpMutex);
    if (s.epoch && s.helperStarted) {
        s.stopHelper.store(true, std::memory_order_release);
        pthread_join(s.helper, nullptr); s.helperStarted = false;
    }
    if (s.sealed.exchange(true, std::memory_order_seq_cst)) { return; }
    // Only finish already-entered fixed-size writes. No GPU wait or callback is requested.
    double deadline = clock() + 1;
    while (s.writers.load(std::memory_order_seq_cst) && clock() < deadline) { std::this_thread::yield(); }
    bool writersPending = s.writers.load(std::memory_order_seq_cst) != 0;
    uint64_t attempted = s.next.load(std::memory_order_acquire);
    uint64_t reserved = attempted < s.capacity ? attempted : s.capacity;
    uint64_t committed = 0;
    for (uint64_t i = 0; i < reserved; ++i) {
        if (s.ready[i].load(std::memory_order_acquire)) { ++committed; }
    }
    uint64_t incomplete = reserved - committed;
    if (writersPending || incomplete) {
        // Never serialize a concurrently changing prefix as a complete timeline.
        committed = 0;
        incomplete = reserved ? reserved : 1;
    }
    Header h {{'R','4','6','T','L','N','0','1'}, 1, sizeof(MVKBackendTimelineEvent), s.capacity,
              reserved, committed, attempted - reserved, s.invalid.load(std::memory_order_relaxed),
              incomplete, s.originHost, s.originUnixMS};
    if (s.cost) { std::memcpy(h.magic, "R92CST02", 8); h.version = 2; }
    if (s.epoch) { std::memcpy(h.magic, "R92EPC03", 8); h.version = 3; }
    int fd = open(s.path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) { std::fprintf(stderr, "[mvk-backend-timeline] output-create-failed\n"); return; }
    CostHeader ch {h, storageBytes(), s.metadataFailures.load(), s.late.load(), s.epoch ? 0 : s.activeRecords.load()};
    EpochHeader eh {};
    if (s.epoch) {
        std::lock_guard<std::mutex> lock(s.epochMutex);
        uint64_t unfinished = 0;
        for (uint64_t i = 0; i < RootCapacity; ++i) { if (s.roots[i].id && !s.roots[i].finished) { ++unfinished; } }
        eh = {ch, s.phase, s.rootCount, s.groupCount, unfinished, s.controlFailures.load(), s.helperBytes.load(),
            s.controlCount, s.armFrame, s.closeFrame, s.armHost, s.closeHost, s.armRelative, s.closeRelative};
    }
    bool ok = s.epoch ? writeAll(fd, &eh, sizeof(eh)) : s.cost ? writeAll(fd, &ch, sizeof(ch)) : writeAll(fd, &h, sizeof(h));
    // Complete prefix only; an incomplete terminal snapshot emits no event payload.
    ok = ok && writeAll(fd, s.events, committed * sizeof(MVKBackendTimelineEvent));
    if (s.cost && ok) {
        s.snapshotFD.store(fd, std::memory_order_release);
        if (s.late.load(std::memory_order_acquire)) { s.markLate(); }
        ok = !s.lateWriteFailed.load();
    } else if (close(fd) != 0) { ok = false; }
    std::fprintf(stderr, "[mvk-backend-timeline] records=%llu dropped=%llu invalid=%llu incomplete=%llu write_ok=%d\n",
                 (unsigned long long)h.committed, (unsigned long long)h.dropped,
                 (unsigned long long)h.invalid, (unsigned long long)h.incomplete, int(ok));
}

#endif // MVK_ENABLE_CUSTOM_DIAGNOSTICS
