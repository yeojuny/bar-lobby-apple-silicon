"""Prepare partial preimages and sequential proposals; never modify product files."""
from pathlib import Path
import difflib, hashlib, json
R = Path(__file__).resolve().parents[3]
O = Path(__file__).resolve().parent
B = R / 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'
files = ['GPUObjects/MVKPipeline.h', 'GPUObjects/MVKPipeline.mm',
         'Commands/MVKCommandEncoderState.mm', 'GPUObjects/MVKRenderPass.h',
         'GPUObjects/MVKRenderPass.mm', 'Commands/MVKCommandBuffer.h',
         'Commands/MVKCommandBuffer.mm', 'Commands/MVKMetal4DependencyScopes.h',
         'GPUObjects/MVKMetal4Submission.h']
original = {f: (B / f).read_text() for f in files}
current = dict(original)
sha = lambda s: hashlib.sha256(s.encode()).hexdigest()
for f, s in original.items():
    p = O / 'preimage' / f
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.exists(): assert p.read_text() == s, f
    else: p.write_text(s)
def replace(f, old, new):
    assert current[f].count(old) == 1, (f, old[:90], current[f].count(old))
    current[f] = current[f].replace(old, new)
stages = []
def stage(name, previous):
    changed = [f for f in files if previous[f] != current[f]]
    patch = ''.join(''.join(difflib.unified_diff(previous[f].splitlines(True), current[f].splitlines(True),
        fromfile='a/'+f, tofile='b/'+f)) for f in changed)
    (O / (name+'.patch')).write_text(patch)
    stages.append(dict(name=name, files=changed, patchSHA256=sha(patch),
                       before={f:sha(previous[f]) for f in changed}, after={f:sha(current[f]) for f in changed}))
    return dict(current)

f='GPUObjects/MVKPipeline.h'
replace(f, 'struct MVKMetal4ResourceBinding {\n\tuint32_t set;\n\tuint32_t bindingIdx;\n};', '''// The pipeline retains its layout, which retains the descriptor-set layouts.
// Only immutable interpretation is prepared here; payloads and GPU leases stay live.
struct MVKMetal4ResourceBindingPlan {
	const MVKDescriptorSetLayout* layout = nullptr;
	uint32_t descriptorCount = 0, cpuOffset = 0, cpuStride = 0, immSamplerIndex = 0;
	MVKDescriptorResourceCount perDescriptorResourceCount = {};
	MVKDescriptorCPULayout cpuLayout = MVKDescriptorCPULayout::None;
	bool variable = false, immutable = false;
	MVKMetal4ResourceBindingPlan() = default;
	MVKMetal4ResourceBindingPlan(const MVKDescriptorSetLayout* owner, const MVKDescriptorBinding& binding)
		: layout(owner), descriptorCount(binding.getDescriptorCount(binding.descriptorCount)),
		  cpuOffset(binding.cpuOffset), cpuStride(descriptorCPUSize(binding.cpuLayout)),
		  immSamplerIndex(binding.hasImmutableSamplers() ? binding.immSamplerIndex : 0),
		  perDescriptorResourceCount(binding.perDescriptorResourceCount), cpuLayout(binding.cpuLayout),
		  variable(binding.descriptorType != VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK && binding.isVariable()),
		  immutable(binding.hasImmutableSamplers()) {}
	uint32_t getDescriptorCount(uint32_t variableCount) const { return variable ? variableCount : descriptorCount; }
	bool hasImmutableSamplers() const { return immutable; }
};

struct MVKMetal4ResourceBinding {
	uint32_t set;
	uint32_t bindingIdx;
	MVKMetal4ResourceBindingPlan preparation;
};''')
replace('GPUObjects/MVKPipeline.mm', '// Keep descriptor values live: only the immutable binding index is cached.',
        '// Keep descriptor values live: prepare only their immutable interpretation.')
replace('GPUObjects/MVKPipeline.mm', 'script.metal4ResourceBindings.push_back({set, descIdx});',
        'script.metal4ResourceBindings.push_back({set, descIdx, {layout, desc}});')
replace('Commands/MVKCommandEncoderState.mm', '''					if (used.bindingIdx >= layout->bindings().size()) { return metal4Failure(sink.encoder, "Native indirect binding is outside its layout."); }
					const auto& binding = layout->bindings()[used.bindingIdx];''', '''					MVKMetal4ResourceBindingPlan fallback;
					const auto* plan = &used.preparation;
					// Pointer equality selects prepared metadata, never resource ownership.
					// Different compatible layouts retain the original interpretation path.
					if (plan->layout != layout || set->layout != layout) {
						if (used.bindingIdx >= layout->bindings().size()) { return metal4Failure(sink.encoder, "Native indirect binding is outside its layout."); }
						fallback = {layout, layout->bindings()[used.bindingIdx]};
						plan = &fallback;
					}
					const auto& binding = *plan;''')
replace('Commands/MVKCommandEncoderState.mm', '\t\t\t\tsize_t stride = descriptorCPUSize(binding.cpuLayout);',
        '\t\t\t\tsize_t stride = binding.cpuStride;')
previous = stage('E1', original)

# Share attachment interpretation with typed wrappers. Private legacy properties
# were never copied into MTL4, and remain solely in the legacy wrapper.
f='GPUObjects/MVKRenderPass.mm';s=current[f]
start=s.index('void MVKRenderSubpass::populateMTLRenderPassDescriptor(')
end=s.index('\nvoid MVKRenderSubpass::encodeStoreActions(',start)
method=s[start:end].rstrip()
private=method.index('\n#if MVK_USE_METAL_PRIVATE_API')
body=method[:private]+'\n}\n'
body='template<class Descriptor>\n'+body.replace('::populateMTLRenderPassDescriptor(', '::populateMTLRenderPassDescriptorImpl(',1).replace('MTLRenderPassDescriptor* mtlRPDesc','Descriptor* mtlRPDesc',1)
signature=method[:method.index('{')]
call='\tpopulateMTLRenderPassDescriptorImpl(cmdEncoder, mtlRPDesc, passIdx, framebuffer, attachments, clearValues, isRenderingEntireAttachment, loadOverride);\n'
legacy=signature+'{\n'+call+method[private:]+'\n'
native='#if MVK_BUILD_METAL4_FOUNDATION\n'+signature.replace('MTLRenderPassDescriptor*','MTL4RenderPassDescriptor*')+'{\n'+call+'}\n#endif\n'
current[f]=s[:start]+body+'\n'+legacy+'\n'+native+s[end:]
f='GPUObjects/MVKRenderPass.h';s=current[f]
start=s.index('\tvoid populateMTLRenderPassDescriptor(');end=s.index(';',start)+1
decl=s[start:end]
s=s[:end]+'\n#if MVK_BUILD_METAL4_FOUNDATION\n'+decl.replace('MTLRenderPassDescriptor*','MTL4RenderPassDescriptor*')+'\n#endif'+s[end:]
pos=s.index('protected:')+len('protected:')
impl=decl.replace('\tvoid populateMTLRenderPassDescriptor(', '\ttemplate<class Descriptor>\n\tvoid populateMTLRenderPassDescriptorImpl(').replace('MTLRenderPassDescriptor*', 'Descriptor*').replace(' = false','')
current[f]=s[:pos]+'\n'+impl+'\n'+s[pos:]
f='Commands/MVKCommandBuffer.h'
replace(f,'void beginMetal4RenderPass(MTLRenderPassDescriptor* descriptor','void beginMetal4RenderPass(MTL4RenderPassDescriptor* descriptor')
replace(f,'\tbool prepareVisibilityResultBuffer(MTLRenderPassDescriptor* descriptor);',
        '\ttemplate<class Descriptor> bool prepareVisibilityResultBuffer(Descriptor* descriptor);\n\ttemplate<class Descriptor> bool populateRenderPassDescriptor(Descriptor* descriptor, bool isRestart);')
f='Commands/MVKCommandBuffer.mm'
replace(f,'bool MVKCommandEncoder::prepareVisibilityResultBuffer(MTLRenderPassDescriptor* descriptor)',
        'template<class Descriptor>\nbool MVKCommandEncoder::prepareVisibilityResultBuffer(Descriptor* descriptor)')
s=current[f];start=s.index('void MVKCommandEncoder::beginMetal4RenderPass(');end=s.index('\tauto keepAttachment',start)
current[f]=s[:start]+'''void MVKCommandEncoder::beginMetal4RenderPass(MTL4RenderPassDescriptor* desc, MVKCommandUse cmdUse,
		uint64_t capturedEpoch, uint64_t leadingOrdinaryDraws) {
	if (_metal4EncodingFailed) { return; }
'''+s[end:]
s=current[f];start=s.index('\tgetSubpass()->populateMTLRenderPassDescriptor(this, mtlRPDesc,',s.index('void MVKCommandEncoder::beginMetalRenderPass('));end=s.index('\n#if MVK_BUILD_METAL4_FOUNDATION\n\tif (isUsingMetal4()) {',start)
helper='template<class Descriptor>\nbool MVKCommandEncoder::populateRenderPassDescriptor(Descriptor* mtlRPDesc, bool isRestart) {\n'+s[start:end].replace('if (!prepareVisibilityResultBuffer(mtlRPDesc)) { return; }','if (!prepareVisibilityResultBuffer(mtlRPDesc)) { return false; }')+'\n\treturn true;\n}\n\n'
s=s[:start]+s[end:]
begin=s.index('// Creates _mtlRenderEncoder and marks cached render state')
s=s[:begin]+helper+s[begin:]
old='\tbool isRestart = cmdUse == kMVKCommandUseRestartSubpass;\n    MTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];\n\n#if MVK_BUILD_METAL4_FOUNDATION\n\tif (isUsingMetal4()) {\n\t\tbeginMetal4RenderPass'
new='\tbool isRestart = cmdUse == kMVKCommandUseRestartSubpass;\n#if MVK_BUILD_METAL4_FOUNDATION\n\tif (isUsingMetal4()) {\n\t\tMTL4RenderPassDescriptor* mtlRPDesc = [[MTL4RenderPassDescriptor new] autorelease];\n\t\tif (!populateRenderPassDescriptor(mtlRPDesc, isRestart)) { return; }\n\t\tbeginMetal4RenderPass'
assert s.count(old)==1;s=s.replace(old,new)
old='\n#endif\n    _mtlRenderEncoder = [_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];'
new='\n#endif\n\tMTLRenderPassDescriptor* mtlRPDesc = [MTLRenderPassDescriptor renderPassDescriptor];\n\tif (!populateRenderPassDescriptor(mtlRPDesc, isRestart)) { return; }\n    _mtlRenderEncoder = [_mtlCmdBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];'
assert s.count(old)==1;s=s.replace(old,new)
current[f]=s
previous=stage('E2', previous)

replace('Commands/MVKMetal4DependencyScopes.h', '    // Call only after an actual queue barrier covers prior-pass sources.', '''    // Reuse only actual prior-pass barriers in the same active encoder. A
    // memory edge needs memory coverage; execution-only coverage cannot upgrade it.
    void satisfyAlreadyEmitted(const MVKMetal4DependencyScopes& emitted, uint64_t dst) {
        for (unsigned i = 0; i < 4; ++i) if (dst & stages[i]) {
            const uint64_t covered = (memory[i] & emitted.memory[i]) |
                ((sources[i] & ~memory[i]) & emitted.sources[i]);
            satisfy(covered, stages[i]);
        }
    }
    // Call only after an actual queue barrier covers prior-pass sources.''')
replace('Commands/MVKCommandBuffer.mm', '    _metal4Dependencies.add(conservativeSources, destinations, true);\n    _metal4Dependencies.encode', '''    _metal4Dependencies.add(conservativeSources, destinations, true);
    if (encoder && encoder == _mtl4ComputeEncoder) {
        // The prior-pass prefix is unchanged inside this encoder. Its own
        // producers remain covered by separate encoder-local dependencies.
        _metal4Dependencies.satisfyAlreadyEmitted(_metal4ComputeQueueDependencies,
            destinations & (MTLStageDispatch | MTLStageBlit));
    }
    _metal4Dependencies.encode''')
previous=stage('E3',previous)
e32=dict(current)
replace('GPUObjects/MVKMetal4Submission.h','static constexpr uint32_t maxAllocatorEpochRecordings = 32;',
        'static constexpr uint32_t maxAllocatorEpochRecordings = 64;')
stage('E64-count-only',previous)
for label,state in [('E32',e32),('E64',current)]:
    patch=''.join(''.join(difflib.unified_diff(original[f].splitlines(True),state[f].splitlines(True),fromfile='a/'+f,tofile='b/'+f)) for f in files if original[f]!=state[f])
    (O/(label+'-combined.patch')).write_text(patch)
(O/'proposal.json').write_text(json.dumps(dict(status='unapplied-proposal', source=str(B),
    stages=stages,originalPins={f:sha(s) for f,s in original.items()},
    E32Pins={f:sha(s) for f,s in e32.items()},E64Pins={f:sha(s) for f,s in current.items()},
    allocatorDiagnosticCancelled=True,diagnosticsCompile=0,
    validation={'E1':'immutable count/stride/layout fallback, existing descriptor mutation and registration',
    'E2':'real descriptor defaults + production attachment/resolve parity; typed visibility/extent/sample; M3/M4 relevant offscreen cases',
    'E3':'exact stage-pair visibility coverage and common emission; encoder-local RAW/WAR retained; native/Vulkan existing cases',
    'E64':'count boundary, growth, cancellation, in-flight completion; only one constant differs from E32'},
    gate='root-source-build-grant.json; no product/fixture/build/app modification before grant'),indent=2)+'\n')
print('Prepared E1/E2/E3 and E32/E64 proposal patches; product files untouched.')
