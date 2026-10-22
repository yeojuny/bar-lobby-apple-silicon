#!/usr/bin/env python3
"""Extract proposal bodies and run an isolated CPU fixture in a fresh evidence dir.

No active source, build directory, product fixture, application, or GPU is used.
The coordinator, not the independent author, executes this validator.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def function(source, marker):
    """Return exact source bytes through a balanced function/block closing brace."""
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 0
    pos = brace
    quote = None
    while pos < len(source):
        ch = source[pos]
        if quote:
            if ch == '\\':
                pos += 2
                continue
            if ch == quote:
                quote = None
        elif source.startswith('//', pos):
            end = source.find('\n', pos)
            pos = len(source) if end < 0 else end
            continue
        elif source.startswith('/*', pos):
            pos = source.index('*/', pos + 2) + 2
            continue
        elif ch in ('"', "'"):
            quote = ch
        elif ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if not depth:
                return source[start:pos + 1] + '\n'
        pos += 1
    raise ValueError('Unbalanced proposal body: ' + marker)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', choices=['R', 'Small'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', default='/usr/bin/clang++')
    args = parser.parse_args()
    out = args.output.absolute().resolve()
    if out == ROOT or not out.is_relative_to(ROOT):
        raise ValueError('Output must be a new evidence subdirectory')
    if out.is_relative_to(ROOT / 'modules') or out.is_relative_to(ROOT / 'payload'):
        raise ValueError('Do not write inside immutable modules or payloads')
    if out.exists():
        raise FileExistsError('Output must not already exist')
    manifest_path = ROOT / 'modules/08a-conservative-rebind/module.json'
    manifest = json.loads(manifest_path.read_text())
    variant = manifest['variants'][args.variant]
    state = next(f for f in variant['files'] if f['target'].endswith('State.mm'))
    sources = {}
    pins = []
    for entry in variant['files']:
        for role in ('before', 'after'):
            spec = entry[role]
            path = ROOT / spec['path']
            if not path.resolve().is_relative_to(ROOT / 'payload'):
                raise ValueError('Unexpected payload location')
            data = path.read_bytes()
            assert len(data) == spec['bytes'] and sha(data) == spec['sha256']
            pins.append(dict(target=entry['target'], role=role, **spec))
            if entry is state:
                sources[role] = data.decode()
    before, after = sources['before'], sources['after']
    metadata = after[after.index('enum class ImplicitBufferData {'):
                     after.index('static bool bindDescriptorSets(MVKImplicitBufferData&')]
    segments = [('descriptor-metadata-production-body', metadata)]
    old_helper = function(before, 'static void bindDescriptorSets(MVKImplicitBufferData&')
    segments.append(('reference-before-helper', 'namespace reference_before {\n' + old_helper + '}\n'))
    for marker in (
        'static bool bindDescriptorSets(MVKImplicitBufferData&',
        'bool MVKVulkanGraphicsCommandEncoderState::bindDescriptorSets(',
        'bool MVKVulkanComputeCommandEncoderState::bindDescriptorSets(',
        'void MVKCommandEncoderState::bindGraphicsPipeline(',
        'void MVKCommandEncoderState::bindComputePipeline(',
        'void MVKCommandEncoderState::bindDescriptorSets(',
    ):
        segments.append((marker, function(after, marker)))
    segments.append(('active-Metal-stage-filter', 'template <typename Fn>\n' +
                     function(after, 'void MVKCommandEncoderState::applyToActiveMTLState(')))
    # Preserve actual production limit/clamp logic, with an explicit mock array view.
    segments.append(('implicit-payload-limit', 'template <typename T, int N>\n' +
                     function(after, 'static MVKArrayRef<const T> getImplicitBindingData(')))
    # Objective-C encoding is deliberately not compiled. Exact transition blocks
    # are placed in mock Metal methods so their reset/invalidation branches run.
    compute = function(after, 'void MVKMetalComputeCommandEncoderState::prepareComputeDispatch(')
    render = function(after, 'void MVKMetalComputeCommandEncoderState::prepareRenderDispatch(')
    segments.append(('compute-transition-production-block',
                     'void MockMetalCompute::transitionCompute() {\n' +
                     function(compute, 'if (_vkStage != kMVKShaderStageCompute)') + '}\n'))
    segments.append(('graphics-helper-transition-production-block',
                     'void MockMetalCompute::transitionRender(MVKShaderStage stage) {\n' +
                     function(render, 'if (_vkStage != stage)') + '}\n'))
    generated = '\n'.join(body for _, body in segments)
    fixture = ROOT / 'rebind-fixture.cpp'
    fixture_bytes = fixture.read_bytes()
    out.mkdir(parents=True)
    (out / 'production.inc').write_text(generated)
    (out / 'rebind-fixture.cpp').write_bytes(fixture_bytes)
    receipt = dict(status='started', variant=args.variant,
                   createdUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   moduleManifestSHA256=sha(manifest_path.read_bytes()),
                   fixtureSHA256=sha(fixture_bytes), productionIncludeSHA256=sha(generated.encode()),
                   inputPins=pins,
                   extractedSegments=[dict(name=name, sha256=sha(body.encode()), bytes=len(body.encode()))
                                      for name, body in segments], runs=[],
                   qualification='CPU production-body contract checks with stage/layout/Metal surfaces mocked; no actual GPU or full header ABI proof.',
                   activeSourceModified=False, appLaunched=False, GPUExecuted=False)
    save = lambda: (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    for foundation in (0, 1):
        exe = out / ('rebind-foundation-' + str(foundation))
        command = [args.compiler, '-std=c++17', '-O1', '-g', '-fsanitize=address,undefined',
                   '-fno-omit-frame-pointer', '-DMVK_BUILD_METAL4_FOUNDATION=' + str(foundation),
                   str(out / 'rebind-fixture.cpp'), '-I', str(out), '-o', str(exe)]
        build = subprocess.run(command, capture_output=True, text=True)
        (out / ('build-' + str(foundation) + '.stdout')).write_text(build.stdout)
        (out / ('build-' + str(foundation) + '.stderr')).write_text(build.stderr)
        row = dict(foundation=foundation, compileCommand=command, compileExit=build.returncode)
        receipt['runs'].append(row)
        save()
        if build.returncode:
            receipt['status'] = 'compile-failed'; save()
            raise SystemExit(build.returncode)
        run = subprocess.run([str(exe)], capture_output=True, text=True)
        (out / ('run-' + str(foundation) + '.stdout')).write_text(run.stdout)
        (out / ('run-' + str(foundation) + '.stderr')).write_text(run.stderr)
        row['runExit'] = run.returncode
        row['stdoutSHA256'] = sha(run.stdout.encode())
        row['stderrSHA256'] = sha(run.stderr.encode())
        if run.returncode:
            receipt['status'] = 'run-failed'; save()
            raise SystemExit(run.returncode)
        row['result'] = json.loads(run.stdout)
        save()
    receipt['status'] = 'passed-cpu-production-body-contracts-only'
    receipt['completedUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save()
    print(json.dumps(dict(status=receipt['status'], variant=args.variant,
                          output=str(out), runs=[r['result'] for r in receipt['runs']]), indent=2))


if __name__ == '__main__':
    main()
