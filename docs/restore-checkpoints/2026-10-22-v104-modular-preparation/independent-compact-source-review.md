# Independent root source review —04 compact CPU State

Implementation author: existing independent_review agent. Reviewer: root. Source verdict: no blocking defect in the exact two-file capsule. Native activation remains open.

The override admits only a successful nonzero compact singleton-UBO capture; Foundation OFF and generic/mixed capture remain unchanged. setContent clears the compact count on pool reuse, and capture owns normalized info/write arrays without copying UBO bytes. encode now retains the pipeline layout through the prepared encoder before a command node can return to its pool. The existing helper is gated on independent prepared recording and deduplicates ownership; encoder destruction releases each owner. Push CPU descriptors are encoder-owned. No signal, query, allocator or queue state machine is changed.

Native buffer address resolution genuinely moves earlier. Valid already-bound resources and legal host visibility are required; this is not permission to destroy/rebind referenced objects early. Map/unmap/flush do not make a new snapshot of buffer contents. Existing State-only, early eligibility, Deferred-stop and timestamp prefix fallback rules remain.

Root read the exact patches, original capture/setContent/encode, retain helper and destructor, design and CPU/mock boundaries. Four final CPU runs passed(817 FoundationOFF and937 ON for both base/after02). The last source correction changes only the stale comment about encode timing and record policy; compact-comment-correction/completion.json proves the exact comment substitution with previous payloads preserved. The final combined source passed all-mvk-modules-syntax-final, including actual CmdPipeline/CommandBuffer TUs with02/03/04 composed and Foundation0/1.

The existing native compactUniformSnapshot case enters Deferred before compact push, so it does not exercise the new early route. The next functional check must use accepted regular set0 output plus compact UBO push set1, verify prepared work, mutate mapped contents after Ended, and cover cancellation, node/layout reuse, leading timestamps and fallback. No GPU correctness or FPS gain is claimed here.
