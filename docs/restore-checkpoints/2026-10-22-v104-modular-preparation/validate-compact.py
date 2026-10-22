#!/usr/bin/env python3
"""Source-derived CPU contracts for the unapplied compact-only State capsule."""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
spec = importlib.util.spec_from_file_location('compact_extract', OUT / 'validate-rebind.py')
extract = importlib.util.module_from_spec(spec); spec.loader.exec_module(extract)
BASE = ROOT / 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def command_class(text):
    return extract.function(text, 'class MVKCmdPushDescriptorSetWithTemplate :').rstrip() + ';\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', choices=['R-and-Small', 'after02'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(); output = args.output.resolve()
    if output.parent != OUT or output.exists():
        raise ValueError('Output must be a new direct evidence directory')
    manifest_path = OUT / 'modules/04-compact-cpu-state/module.json'
    manifest_raw = manifest_path.read_bytes(); manifest = json.loads(manifest_raw)
    data = {}; pins = []
    for entry in manifest['variants'][args.variant]['files']:
        filename = Path(entry['target']).name; data[filename] = {}
        for role in ('before', 'after'):
            spec = entry[role]; path = (OUT / spec['path']).resolve()
            assert path.is_relative_to(OUT / 'payload')
            raw = path.read_bytes(); assert sha(raw) == spec['sha256'] and len(raw) == spec['bytes']
            data[filename][role] = raw.decode(); pins.append(dict(target=entry['target'], role=role, **spec))
    design = json.loads((OUT / 'design-deepening-04.json').read_text())
    design_pins = {p['path']:p['sha256'] for p in design['readPins']}
    production = {}
    for relative in ('Commands/MVKCommandBuffer.mm','Commands/MVKCommandEncoderState.mm','GPUObjects/MVKDescriptorSet.mm'):
        path=BASE/relative; raw=path.read_bytes()
        assert sha(raw)==design_pins[str(path.relative_to(ROOT))]
        production[relative]=raw.decode();pins.append({'path':str(path.relative_to(ROOT)),'sha256':sha(raw),'bytes':len(raw)})
    segments=[]
    header, cpp=data['MVKCmdPipeline.h'],data['MVKCmdPipeline.mm']
    methods=('VkResult MVKCmdPushDescriptorSetWithTemplate::captureUniforms(',
             'VkResult MVKCmdPushDescriptorSetWithTemplate::setContent(',
             'void MVKCmdPushDescriptorSetWithTemplate::encode(',
             'MVKCmdPushDescriptorSetWithTemplate::~MVKCmdPushDescriptorSetWithTemplate(')
    for role in ('before','after'):
        parts=[command_class(header[role])]
        parts.extend(extract.function(cpp[role], marker) for marker in methods)
        parts.append('MVKCommandTypePool<MVKCommand>* MVKCmdPushDescriptorSetWithTemplate::getTypePool(MVKCommandPool*) { return &commandPool; }\n')
        code='\n'.join(parts)
        if role=='before':
            code='#define MVKCmdPushDescriptorSetWithTemplate ReferenceCompact\n'+code+'\n#undef MVKCmdPushDescriptorSetWithTemplate\n'
        segments.append((role+' exact compact class and methods; type-pool mock only',code))
    descriptor=production['GPUObjects/MVKDescriptorSet.mm']
    begin=descriptor.index('template <MVKDescriptorCPULayout Layout>\nstatic void writeDescriptorSetCPUBuffer(')
    original=extract.function(descriptor[begin:],'case MVKDescriptorCPULayout::OneID2Meta:')
    case_body=original[original.index('{'):].rstrip()
    segments.append(('exact OneID2Meta case with explicit UBO-only dispatch wrapper',
        'static void convertOneElement(char* dst,const void* src) {\n'
        '    const auto srcType=MVKDescriptorUpdateSourceType::Buffer;\n    do '+case_body+' while(false);\n}\n'))
    segments.append(('exact mvkPushDescriptorSet',extract.function(descriptor,'void mvkPushDescriptorSet(')))
    state=production['Commands/MVKCommandEncoderState.mm']
    for marker in ('void MVKVulkanCommonEncoderState::ensurePushDescriptorSize(',
                   'void MVKCommandEncoderState::pushDescriptorSet(VkPipelineBindPoint'):
        segments.append((marker,extract.function(state,marker)))
    buffer=production['Commands/MVKCommandBuffer.mm']
    guarded=[]
    for marker in ('void MVKCommandEncoder::retainMetal4VulkanState(',
                   'void MVKCommandBuffer::addCommand(', 'void MVKCommandBuffer::releaseCommands(',
                   'void MVKCommandBuffer::releaseRecordedCommands(',
                   'void MVKCommandBuffer::releaseMetal4PreparedReplay(',
                   'void MVKCommandBuffer::restoreMetal4PreparedReplay('):
        guarded.append(extract.function(buffer,marker))
    begin_func=extract.function(buffer,'bool MVKCommandBuffer::beginMetal4PreparedRecording(')
    stamp_start=begin_func.index('    if (_metal4PreparedTimestamp) {')
    stamp=extract.function(begin_func[stamp_start:],'    if (_metal4PreparedTimestamp) {')
    # Native begin/allocation is intentionally mocked. Retained-timestamp list
    # manipulation and encode-before-transfer below are exact source bytes.
    guarded.append('bool MVKCommandBuffer::beginMetal4PreparedRecording(){\n'
                   '    if(_metal4PreparedEncoder)return wasConfigurationSuccessful();\n'
                   '    if(failBegin)return false;\n'
                   '    _metal4PreparedEncoder=new MVKCommandEncoder;\n'+stamp+'    return true;\n}\n')
    segments.append(('exact control/transfer and encoder retain; native begin mock',
                     '#if MVK_BUILD_METAL4_FOUNDATION\n'+'\n'.join(guarded)+'\n#endif\n'))
    generated='\n\n'.join('// SOURCE SEGMENT: '+marker+'\n'+body for marker,body in segments)
    fixture=(OUT/'compact-fixture.mm').read_bytes(); output.mkdir()
    (output/'compact-production.inc').write_text(generated);(output/'compact-fixture.mm').write_bytes(fixture)
    receipt={'createdUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'variant':args.variant,'moduleSHA256':sha(manifest_raw),'readPins':pins,
             'fixtureSHA256':sha(fixture),'validatorSHA256':sha(Path(__file__).read_bytes()),
             'sourceExtractSHA256':sha(generated.encode()),'originalBufferCaseSHA256':sha(original.encode()),
             'segments':[{'marker':m,'sha256':sha(t.encode())} for m,t in segments],
             'mockBoundaries':['Native buffer/layout/template wrappers and GPU encoder','Other CPU descriptor layouts/generic fallback',
                               'Native begin allocation, pause and clear; actual timestamp list-transfer body extracted',
                               'Query-like unknown command uses production Deferred control but no actual query pool'],
             'activeSourceWrites':0,'productBuilds':0,'actualGPU':False,'runs':[],
             'limits':'CPU shell proves copied descriptor/state/control contracts only. Real mapped GPU reads, query activation, native cancellation and BAR early reach remain unverified.'}
    for foundation in (0,1):
        label='foundation'+str(foundation)
        command=['/usr/bin/clang++','-std=c++17','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',
                 '-DMVK_BUILD_METAL4_FOUNDATION='+str(foundation),'-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0',
                 '-I'+str(ROOT/'build/run66-vulkan-headers-src-20260903/include'),'-I'+str(output),
                 str(output/'compact-fixture.mm'),'-framework','Foundation','-o',str(output/label)]
        compile_result=subprocess.run(command,capture_output=True,text=True,timeout=120)
        (output/(label+'-compile.log')).write_text(compile_result.stdout+compile_result.stderr)
        row={'foundation':foundation,'command':command,'compileExit':compile_result.returncode}
        if compile_result.returncode==0:
            run=subprocess.run([str(output/label)],capture_output=True,text=True,timeout=45)
            (output/(label+'-run.log')).write_text(run.stdout+run.stderr)
            row.update(runExit=run.returncode,outputSHA256=sha((run.stdout+run.stderr).encode()),passed=run.returncode==0 and 'PASS compact CPU' in run.stdout)
        else:row['passed']=False
        receipt['runs'].append(row)
        receipt['status']='running';(output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({'variant':args.variant,'foundation':foundation,**{k:v for k,v in row.items() if k!='command'}}),flush=True)
        if not row['passed']:break
    receipt['status']='passed-source-derived-cpu-only' if len(receipt['runs'])==2 and all(r['passed'] for r in receipt['runs']) else 'failed'
    (output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    raise SystemExit(0 if receipt['status'].startswith('passed') else 1)


if __name__=='__main__':main()
