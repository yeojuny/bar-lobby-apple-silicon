#!/usr/bin/env python3
"""Coordinator-run source-derived CPU checks for unapplied 06/07 capsules.

Output is a fresh evidence subdirectory only. No active source, product build,
Metal device, queue, GPU or application is used. Native acceptance remains gated.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('rebind_extract', OUT / 'validate-rebind.py')
extract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extract)
BASELINE = '2e680f300575bdd99816c32252ef62c8ca8ad0398f5cd2543399b915ef8e012f'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_stage(stage):
    choices = {
        'baseline': ('06-success-notify', 'R-and-Small', 'before'),
        '06': ('06-success-notify', 'R-and-Small', 'after'),
        '07': ('07-signal-order-proof', 'R-and-Small', 'after'),
        '06+07': ('07-signal-order-proof', 'after06', 'after'),
    }
    module, variant, role = choices[stage]
    manifest_path = OUT / 'modules' / module / 'module.json'
    raw = manifest_path.read_bytes()
    manifest = json.loads(raw)
    files = manifest['variants'][variant]['files']
    assert len(files) == 1 and files[0]['target'].endswith('/MVKMetal4Submission.mm')
    entry = files[0][role]
    path = (OUT / entry['path']).resolve()
    assert path.is_relative_to(OUT / 'payload') and path.name == entry['sha256']
    data = path.read_bytes()
    assert sha(data) == entry['sha256'] and len(data) == entry['bytes']
    assert manifest['sourceBaselineSHA256'] == BASELINE
    return data.decode(), {'module': module, 'variant': variant, 'role': role,
                           'manifestSHA256': sha(raw), 'source': entry}


def source_segments(source):
    segments = []
    for marker in ('struct MVKMetal4SubmissionGroup {', 'struct NotificationSlotReservation {',
                   'struct SubmissionChildLocks {'):
        segments.append((marker, extract.function(source, marker).rstrip() + ';\n'))
    for marker in ('bool publishGroupError(', 'void notifyGroupWaiters(', 'void runGroupErrorHandlers(',
                   'void retireIfReady(', 'void recordSignalNotification(',
                   'void failSignalNotificationOwners(', 'void recordFeedback(', 'bool validSignalValue('):
        segments.append((marker, extract.function(source, marker)))
    if 'class GroupSignalOrderProof {' in source:
        segments.append(('class GroupSignalOrderProof', extract.function(source, 'class GroupSignalOrderProof {').rstrip() + ';\n'))
    validator = extract.function(source, 'bool validGroupSignals(')
    # Explicitly recorded test-only loop observation. Every other byte of the
    # extracted validator is unchanged. Never add this counter to a capsule.
    needle = '                for (size_t k = 0; k < count; ++k) {'
    assert validator.count(needle) == 1
    observed = validator.replace(needle, needle + '\n                    ++relativeComparisons;', 1)
    segments.append(('bool validGroupSignals/test-only-pair-observation', observed))
    if 'class GroupSignalOrderProof {' in source:
        # Start after the class, since its friend declaration precedes the body.
        factory_start = source.index('bool validateAndProveGroupSignals(', source.index('// Only a successful complete check creates a proof.'))
        segments.append(('bool validateAndProveGroupSignals', extract.function(source[factory_start:], 'bool validateAndProveGroupSignals(')))
    for marker in ('bool publishPreparedSubmission(', 'bool addEvent(',
                   'bool MVKMetal4Submission::wait(', 'bool MVKMetal4Queue::waitIdle('):
        segments.append((marker, extract.function(source, marker)))
    return segments, sha(validator.encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', choices=['baseline', '06', '07', '06+07'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', default='/usr/bin/clang++')
    args = parser.parse_args()
    output = args.output.absolute().resolve()
    if output == OUT or not output.is_relative_to(OUT):
        raise ValueError('Output must be a new evidence subdirectory')
    for protected in ('modules', 'payload'):
        if output.is_relative_to(OUT / protected):
            raise ValueError('Immutable capsule output prohibited')
    if output.exists():
        raise FileExistsError('Output already exists')
    source, binding = read_stage(args.stage)
    segments, validator_sha = source_segments(source)
    production = '\n\n'.join('// EXACT SOURCE SEGMENT: ' + marker + '\n' + body for marker, body in segments)
    fixture_path = OUT / 'sync-fixture.mm'
    fixture = fixture_path.read_bytes()
    output.mkdir(parents=True)
    (output / 'production.inc').write_text(production)
    (output / 'sync-fixture.mm').write_bytes(fixture)
    command = [args.compiler, '-std=c++17', '-O1', '-g', '-fblocks', '-fno-omit-frame-pointer',
               '-fsanitize=address,undefined', '-DMVK_ENABLE_CUSTOM_DIAGNOSTICS=0',
               '-DSYNC_HAS_PROOF=' + str(int(args.stage in ('07', '06+07'))),
               '-DSYNC_NOTIFY_REDUCED=' + str(int(args.stage in ('06', '06+07'))),
               '-I', str(output), str(output / 'sync-fixture.mm'),
               '-framework', 'Foundation', '-framework', 'Metal', '-pthread', '-o', str(output / 'sync-cpu')]
    compile_result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
    (output / 'compile.log').write_text(compile_result.stdout)
    receipt = {
        'createdUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'stage': args.stage, 'binding': binding,
        'validatorSHA256': sha(Path(__file__).read_bytes()), 'fixtureSHA256': sha(fixture),
        'productionExtractSHA256': sha(production.encode()), 'originalSignalValidatorSHA256': validator_sha,
        'segments': [{'marker': marker, 'sha256': sha(body.encode())} for marker, body in segments],
        'testOnlyInstrumentation': ['pair-loop counter in extracted validator',
                                    'mock event getter current-value reads', 'mock CV notify count/wait-entry observation'],
        'mockBoundaries': ['Storage/cache/allocator retirement effects', 'Metal event and commit feedback objects',
                           'queue/group setup; NSError helper creation; deadline helper'],
        'actualProductionBodies': ['group/child lock structure', 'feedback, signal and error state transitions',
                                   'retirement gates and callbacks', 'publication guards',
                                   'event registration phase rejection', 'public child and idle wait predicates'],
        'command': command, 'compileExitCode': compile_result.returncode,
        'activeSourceWrites': 0, 'GPUOrAppRuns': 0,
        'limits': 'CPU mock boundaries do not prove native device ordering, driver errors, runtime progress or FPS benefit.'
    }
    if compile_result.returncode == 0:
        try:
            run = subprocess.run([str(output / 'sync-cpu')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
            (output / 'run.log').write_text(run.stdout)
            receipt.update(runExitCode=run.returncode, runOutputSHA256=sha(run.stdout.encode()),
                           passed=run.returncode == 0 and 'PASS sync CPU' in run.stdout)
        except subprocess.TimeoutExpired as failure:
            (output / 'run.log').write_bytes(failure.stdout or b'')
            receipt.update(passed=False, timedOut=True, timeoutSeconds=45)
    else:
        receipt['passed'] = False
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'stage': args.stage, 'passed': receipt['passed'], 'receipt': str(output / 'receipt.json')}))
    raise SystemExit(0 if receipt['passed'] else 1)


if __name__ == '__main__':
    main()
