#include <metal_stdlib>
using namespace metal;
typedef struct alignas(8) {
	uint32_t count;
	uint32_t countHigh;
} VisibilityBuffer;

typedef struct alignas(8) {
	atomic_uint count;
	atomic_uint countHigh;
} AtomicVisibilityBuffer;

typedef struct alignas(8) {
	uint32_t dst;
	uint32_t src;
} QueryResultOffsets;

kernel void accumulateOcclusionQueryResults(uint pos [[thread_position_in_grid]],
                                            const device QueryResultOffsets* offsets  [[buffer(0)]],
                                            device AtomicVisibilityBuffer* dst_buffer [[buffer(1)]],
                                            device VisibilityBuffer* src_buffer [[buffer(2)]])
{
	VisibilityBuffer src = src_buffer[offsets[pos].src];
	// Each consumed native slot appears once in this batch. Recycle it in the
	// existing accumulation pass, before the next render pass can reuse it.
	src_buffer[offsets[pos].src] = VisibilityBuffer{0, 0};
	device AtomicVisibilityBuffer& dst = dst_buffer[offsets[pos].dst];
	uint32_t prev_lo = atomic_fetch_add_explicit(&dst.count, src.count, memory_order_relaxed);
	uint32_t next_lo = prev_lo + src.count;
	atomic_fetch_add_explicit(&dst.countHigh, src.countHigh, memory_order_relaxed);
	if (next_lo < prev_lo)
		atomic_fetch_add_explicit(&dst.countHigh, 1, memory_order_relaxed);
}
