// R44 derivative of the preserved CPU-only collector checks. Links production helpers but creates no device,
// queue, command buffer, window or GPU work. Root owns compilation/execution.
#include "MVKMetal4Submission.h"
#include <cmath>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <vector>

static unsigned assertions = 0;
static void require(bool value, const char* message) {
    ++assertions;
    if (!value) { throw std::runtime_error(message); }
}
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
static bool near(double a, double b) { return std::abs(a - b) < 1e-7; }
#endif

int main(int argc, char** argv) {
    try {
        bool flagsOnly = argc == 2 && std::strcmp(argv[1], "--off-flags-only") == 0;
        require(!mvkMetal4QueueStatsEnabled(), "fixture leaves queue stats off");
        require(std::getenv("MVK_CONFIG_METAL4_STATS") && std::strcmp(std::getenv("MVK_CONFIG_METAL4_STATS"), "0") == 0, "fixture leaves per-batch stats off");
        if (flagsOnly) {
            require(!mvkBackendCostStatsEnabled() && !mvkMetal4StatsEnabled(), "ordinary OFF enables neither cost collector nor local encoding counts");
            std::printf("{\"suite\":\"r44_backend_cost_off_flags\",\"passed\":%u,\"gameExecuted\":false,\"gpuExecuted\":false}\n", assertions);
            return 0;
        }
#if MVK_ENABLE_CUSTOM_DIAGNOSTICS
        require(mvkBackendCostStatsEnabled() && mvkMetal4StatsEnabled(), "cost-only opt-in enables encoding counts without queue stats");
        MVKBackendCostStats cost("cpu-fixture");
        double t = cost.originHostSeconds(), nan = std::numeric_limits<double>::quiet_NaN();
        cost.recordCPU(t + .5, t + .502);
        cost.recordCPU(t + .6, t + .606, true);
        cost.recordGPU(t + .8, t + .809, t + .7, t + .810, false);
        cost.recordGPU(t + 1.2, t + 1.203, t + 1.19, t + 1.204, true, true);
        cost.recordGPU(t + .9, t + .912, t + .85, t + .913, false, true);
        auto s = cost.snapshot();
        require(s.bins[0].cpuCount == 1 && near(s.bins[0].cpuSum, .002) && near(s.bins[0].cpuMax, .002), "CPU duration sum/max");
        require(s.bins[0].waitCount == 1 && near(s.bins[0].waitSum, .006), "separate CPU wait duration");
        require(s.bins[0].workCount == 1 && near(s.bins[0].workSum, .009), "actual GPU property duration");
        require(near(s.bins[0].queueDelaySum, .1) && near(s.bins[0].feedbackLagSum, .001), "queue and callback latency remain separate");
        require(s.bins[1].tailCount == 1 && near(s.bins[1].tailSum, .003) && s.bins[1].workCount == 0, "synthetic tail is separate");
        require(s.bins[0].presentCount == 1 && near(s.bins[0].presentSum, .012) && near(s.bins[0].presentMax, .012) && s.bins[0].workCount == 1 && near(s.bins[0].workSum, .009), "presentation duration excludes ordinary work");
        require(near(s.bins[0].presentFirstGPU, t + .9) && near(s.bins[0].presentLastGPU, t + .912) && near(s.bins[0].presentQueueDelaySum, .05) && near(s.bins[0].presentFeedbackLagSum, .001), "presentation envelope and delays stay separate");
        require(s.bins[1].presentCount == 0 && s.bins[1].presentSum == 0, "presentation tail is counted only as tail");
        cost.recordCPU(t - 1, t);
        cost.recordCPU(nan, t);
        cost.recordCPU(t + 3, t + 2);
        cost.recordGPU(0, 0, t, t + 1, false);
        cost.recordGPU(t + 2, t + 1, t, t + 3, false);
        cost.recordGPU(nan, t + 1, t, t + 3, false);
        cost.recordGPU(t + 2, t + 3, t - 1, t + 4, false);
        cost.recordGPU(t + 2, t + 3, t + 1, t + 2, false);
        cost.recordCPU(t + 300, t + 301);
        cost.recordGPU(t + 300, t + 301, t + 299, t + 302, false);
        cost.recordCPU(t + 299.99, t + 300.01);
        cost.recordGPU(t + 2, t + 2.004, t + 1.9, t + 2.01, false);
        cost.recordGPU(t + 2.002, t + 2.006, t + 1.9, t + 2.01, false);
        s = cost.snapshot();
        require(s.invalidCPU == 3 && s.invalidGPU == 5 && s.outsideWindow == 2, "invalid/domain/out-of-window samples are counted");
        require(s.bins[299].cpuCount == 1 && near(s.bins[299].cpuSum, .02), "last bin groups by start without clipping duration");
        require(s.bins[2].workCount == 2 && near(s.bins[2].workSum, .008) && near(s.bins[2].lastGPU - s.bins[2].firstGPU, .006), "overlap sum is distinct from envelope/critical path");
        MVKMetal4EncodingStats a{}, b{};
        a.drawCalls = 5; b.drawCalls = 7;
        a.converted = 2; b.converted = 3;
        a.maxInputCountMax = 33; b.maxInputCountMax = 22;
        a.maxInputCountSum = 55; b.maxInputCountSum = 44;
        a.scratchBytes = UINT64_MAX - 1; b.scratchBytes = 9;
        a.textureBindingVisits = 10; b.textureBindingVisits = 4;
        a.textureCacheEligible = 8; b.textureCacheEligible = 4;
        a.textureCacheHits = 6; b.textureCacheHits = 2;
        a.textureCacheMisses = b.textureCacheMisses = 2;
        a.textureHitResourceSlots = 12; b.textureHitResourceSlots = 8;
        a.textureNegativeMemoSkips = b.textureNegativeMemoSkips = 1;
        a.textureProofAttempts = b.textureProofAttempts = 1;
        a.textureProofReady = 1; b.textureProofRejected = 1;
        a.directTextureBindings = 4; b.directTextureBindings = 2;
        a.invariantAdmittedDraws = 2; b.invariantProofRejectedDraws = 3;
        cost.recordEncoding(a, t + .95); cost.recordEncoding(b, t + .99);
        cost.recordEncoding(b, t + 1.01);
        s = cost.snapshot();
        require(s.bins[0].encodingCount == 2 && s.bins[1].encodingCount == 1, "encoding records use delivery-time bins, not earlier CPU/GPU bins");
        require(s.bins[0].encoding.drawCalls == 12 && s.bins[0].encoding.converted == 5 && s.bins[1].encoding.drawCalls == 7, "per-encoder stats merge once into the selected record bin");
        require(s.bins[0].encoding.maxInputCountMax == 33 && s.bins[0].encoding.maxInputCountSum == 99, "max stays maximum while sum stays sum");
        require(s.bins[0].encoding.scratchBytes == UINT64_MAX, "encoding additions saturate without overflow");
        require(s.bins[0].encoding.textureBindingVisits == 14 && s.bins[0].encoding.textureCacheEligible == 12 && s.bins[0].encoding.textureCacheHits == 8 && s.bins[0].encoding.textureCacheMisses == 4, "texture eligibility and actual hit/miss counts retain separate denominators");
        require(s.bins[0].encoding.textureHitResourceSlots == 20 && s.bins[0].encoding.textureNegativeMemoSkips == 2 && s.bins[0].encoding.textureProofAttempts == 2 && s.bins[0].encoding.textureProofReady == 1 && s.bins[0].encoding.textureProofRejected == 1 && s.bins[0].encoding.directTextureBindings == 6, "proof-ready, rejection and negative-memo paths remain distinct");
        require(s.bins[0].encoding.invariantAdmittedDraws == 2 && s.bins[0].encoding.invariantProofRejectedDraws == 3, "primitive applicability fields share encoding bins");
        require(near(s.bins[0].encodingFirstRecordHost, t + .95) && near(s.bins[0].encodingLastRecordHost, t + .99), "record timestamp envelope is separate from GPU start/end");
        cost.recordEncoding(a, t - 1); cost.recordEncoding(a, nan);
        cost.recordEncoding(a, std::numeric_limits<double>::infinity());
        cost.recordEncoding(a, t + 300); cost.recordEncoding(a, t + 299.99);
        std::vector<std::thread> writers;
        for (unsigned i = 0; i < 4; ++i) writers.emplace_back([&] {
            MVKMetal4EncodingStats one{}; one.drawCalls = 1;
            for (unsigned n = 0; n < 1000; ++n) cost.recordEncoding(one, t + 3.5);
        });
        for (auto& writer : writers) writer.join();
        s = cost.snapshot();
        require(s.invalidEncoding == 3 && s.outsideWindow == 3, "invalid/nonfinite/outside encoding records are counted without attribution");
        require(s.bins[299].encodingCount == 1 && s.bins[299].encoding.drawCalls == 5, "last fixed encoding bin remains accepted");
        require(s.bins[3].encodingCount == 4000 && s.bins[3].encoding.drawCalls == 4000, "concurrent end-record merges remain exact");
        require(sizeof(MVKBackendCostStats) < 256 * 1024, "fixed collector with all encoding fields stays below 256 KiB");
        std::printf("{\"suite\":\"r44_backend_cost_cpu\",\"passed\":%u,\"collectorBytes\":%zu,\"gameExecuted\":false,\"gpuExecuted\":false}\n", assertions, sizeof(MVKBackendCostStats));
        return 0;
#else
        throw std::runtime_error("collector cases require MVK_ENABLE_CUSTOM_DIAGNOSTICS=1");
#endif
    } catch (const std::exception& error) {
        std::fprintf(stderr, "backend cost CPU failure: %s\n", error.what());
        return 1;
    }
}
