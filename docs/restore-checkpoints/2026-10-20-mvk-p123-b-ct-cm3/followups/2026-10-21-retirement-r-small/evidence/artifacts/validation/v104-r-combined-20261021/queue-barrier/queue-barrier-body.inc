void MVKCommandEncoder::encodeMetal4PendingDependencies(id<MTL4CommandEncoder> encoder,
        MTLStages destinations, MTLStages conservativeSources) {
    if (_metal4CollectPreparedDependencies) { _metal4PreparedSummary.recordConsumption(destinations); }
    _metal4Dependencies.add(conservativeSources, destinations, true);
    if (encoder && encoder == _mtl4ComputeEncoder) {
        // The prior-pass prefix is unchanged inside this encoder. Its own
        // producers remain covered by separate encoder-local dependencies.
        _metal4Dependencies.satisfyAlreadyEmitted(_metal4ComputeQueueDependencies,
            destinations & (MTLStageDispatch | MTLStageBlit));
    }
    _metal4Dependencies.encode(destinations, [&](uint64_t sources, uint64_t consumers, bool visible) {
        auto visibility = visible ? MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias
                                  : MTL4VisibilityOptionNone;
        [encoder barrierAfterQueueStages:sources beforeStages:consumers visibilityOptions:visibility];
        if (encoder == _mtl4ComputeEncoder) {
            _metal4ComputeQueueDependencies.add(sources, consumers, visible);
        }
    });
}

void MVKCommandEncoder::computeBarrier(MTLStages sourceStages, MTLStages destinationStages, bool memoryDependency) {
const MTL4VisibilityOptions visibility = memoryDependency ? MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias : MTL4VisibilityOptionNone;
_metal4Dependencies.add(sourceStages,destinationStages,memoryDependency);
if (_mtl4ComputeEncoder) {
		const MTLStages local = MTLStageDispatch | MTLStageBlit;
		encodeMetal4PendingDependencies(_mtl4ComputeEncoder, destinationStages & local);
		// Queue scope excludes this encoder. Preserve local work separately,
		// and retain its sources for all future consumer stages.
		_metal4EncoderDependencies.add(sourceStages & local, destinationStages, memoryDependency);
		if ((sourceStages & local) && (destinationStages & local)) {
			[_mtl4ComputeEncoder barrierAfterEncoderStages:(sourceStages & local)
				beforeEncoderStages:(destinationStages & local) visibilityOptions:visibility];
		}
		if (auto* stats = getMetal4EncodingStats()) { ++stats->computeBarrierContinuations; }
		return;
	}
}
