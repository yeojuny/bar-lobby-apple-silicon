#!/usr/bin/env python3
"""Exact, in-memory capsule validation. Never apply to the active source tree."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def relative(value):
    p = PurePosixPath(value)
    if p.is_absolute() or '..' in p.parts or str(p) != value:
        raise ValueError('Unsafe or noncanonical relative path')
    return value


def blob(spec):
    digest = spec['sha256']
    if not re.fullmatch('[0-9a-f]{64}', digest):
        raise ValueError('Invalid digest')
    if spec['path'] != 'payload/' + digest:
        raise ValueError('Payload must use the central content-addressed store')
    p = HERE / spec['path']
    if p.is_symlink():
        raise ValueError('Payload symlink refused')
    data = p.read_bytes()
    if sha(data) != digest or len(data) != spec['bytes']:
        raise ValueError('Payload bytes changed')
    return data


def exact_patch(original, patch):
    """Apply our unified-diff format with exact line numbers, context, no fuzz."""
    lines = patch.decode().splitlines(keepends=True)
    result = dict(original)
    seen = set()
    i = 0
    while i < len(lines):
        if not lines[i].startswith('--- a/') or i + 1 >= len(lines):
            raise ValueError('Expected paired file header')
        name = relative(lines[i][6:].rstrip('\n'))
        if lines[i + 1] != '+++ b/' + name + '\n' or name in seen:
            raise ValueError('Unexpected destination or duplicate file')
        if name not in original:
            raise ValueError('Patch contains an undeclared target')
        seen.add(name)
        source = original[name].decode().splitlines(keepends=True)
        output = []
        cursor = 0
        i += 2
        hunks = 0
        while i < len(lines) and not lines[i].startswith('--- a/'):
            m = re.fullmatch(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@\n', lines[i])
            if not m:
                raise ValueError('Expected exact hunk header')
            old_start, old_count, new_start, new_count = (
                int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1))
            pos = old_start if old_count == 0 else old_start - 1
            if pos < cursor or pos > len(source):
                raise ValueError('Invalid old line range')
            output.extend(source[cursor:pos])
            expected_new_pos = new_start if new_count == 0 else new_start - 1
            if len(output) != expected_new_pos:
                raise ValueError('New line position changed')
            cursor = pos
            removed = added = 0
            i += 1
            while i < len(lines) and not lines[i].startswith(('@@ ', '--- a/')):
                line = lines[i]
                if not line or line[0] not in ' +-':
                    raise ValueError('Invalid hunk body')
                if line[0] in ' -':
                    if cursor >= len(source) or source[cursor] != line[1:]:
                        raise ValueError('Context differs; offsets and fuzz are forbidden')
                    cursor += 1
                    removed += 1
                if line[0] in ' +':
                    output.append(line[1:])
                    added += 1
                i += 1
            if removed != old_count or added != new_count:
                raise ValueError('Hunk length differs')
            hunks += 1
        if not hunks:
            raise ValueError('Empty file patch')
        output.extend(source[cursor:])
        result[name] = ''.join(output).encode()
    if seen != set(original):
        raise ValueError('Not every declared file was patched')
    return result


def exact_variant(module, variant, current, reverse=False):
    value = module['variants'][variant]
    old, new = ('after', 'before') if reverse else ('before', 'after')
    expected = {relative(f['target']): blob(f[old]) for f in value['files']}
    if current != expected:
        raise ValueError('Exact full-file preimage does not match')
    path = HERE / 'modules' / relative(module['id']) / (
        variant + ('.reverse.patch' if reverse else '.patch'))
    data = path.read_bytes()
    key = 'reversePatchSHA256' if reverse else 'patchSHA256'
    if sha(data) != value[key]:
        raise ValueError('Patch hash changed')
    result = exact_patch(current, data)
    if result != {f['target']: blob(f[new]) for f in value['files']}:
        raise ValueError('Patch output differs from the declared exact postimage')
    return result


def must_reject(fn):
    try:
        fn()
    except (ValueError, KeyError):
        return True
    raise AssertionError('Invalid input was accepted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.parent != HERE or output.exists():
        raise SystemExit('Output must be a new direct evidence JSON file')
    modules = [json.loads(p.read_text()) for p in sorted((HERE/'modules').glob('*/module.json'))]
    rows = []
    states = {}
    for module in modules:
        for name, value in module['variants'].items():
            before = {f['target']: blob(f['before']) for f in value['files']}
            after = exact_variant(module, name, before)
            assert exact_variant(module, name, after, reverse=True) == before
            bad = dict(before)
            key = next(iter(bad))
            bad[key] += b'// wrong parent\n'
            negatives = {
                'changedParent': must_reject(lambda: exact_variant(module, name, bad)),
                'doubleApply': must_reject(lambda: exact_variant(module, name, after)),
                'reverseOnParent': must_reject(lambda: exact_variant(module, name, before, True)),
                'missingFile': must_reject(lambda: exact_variant(module, name, {})),
            }
            actual = {}
            for f in value['files']:
                p = ROOT / relative(f['target'])
                actual[f['target']] = {
                    'sha256': sha(p.read_bytes()), 'mode': p.stat().st_mode & 0o777,
                    'parentMatches': not p.is_symlink() and sha(p.read_bytes()) == f['before']['sha256']
                        and p.stat().st_mode & 0o777 == f['mode'],
                }
            rows.append({'module': module['id'], 'variant': name,
                         'forwardReverseExact': True, 'negativeCases': negatives,
                         'liveParentComparison': actual})
            states[module['id'], name] = (before, after)
    # Composition is checked for disjoint edits only. Overlap requires a new
    # reviewed staged full-file pin, not textual hunk merging.
    composition = []
    keys = list(states)
    for i, left in enumerate(keys):
        for right in keys[i+1:]:
            if left[0] == right[0]:
                continue
            lb, la = states[left]; rb, ra = states[right]
            common = sorted(set(lb) & set(rb))
            if common:
                composition.append({'left': left, 'right': right, 'status': 'staged-pins-required', 'overlap': common})
                continue
            first = dict(lb, **rb); first.update(la); first.update(ra)
            second = dict(lb, **rb); second.update(ra); second.update(la)
            assert first == second
            first.update(rb); first.update(lb)
            assert first == dict(lb, **rb)
            composition.append({'left': left, 'right': right,
                                'status': 'disjoint-postimages-commute-and-reverse-exact'})
    staged = []
    by_id = {m['id']:m for m in modules}
    queue = json.loads((HERE/'QUEUE.json').read_text())
    for name, selections in queue.get('sameFileComposition', {}).items():
        if not isinstance(selections, list):
            continue
        route = [tuple(s.split(':', 1)) for s in selections]
        current = {}; initial = {}; history = []
        for module_id, variant in route:
            m = by_id[module_id]
            for f in m['variants'][variant]['files']:
                if f['target'] not in current:
                    current[f['target']] = initial[f['target']] = blob(f['before'])
            subset = {f['target']:current[f['target']] for f in m['variants'][variant]['files']}
            current.update(exact_variant(m, variant, subset))
            history.append((m, variant))
        final = dict(current)
        for m, variant in reversed(history):
            subset = {f['target']:current[f['target']] for f in m['variants'][variant]['files']}
            current.update(exact_variant(m, variant, subset, reverse=True))
        assert current == initial
        staged.append({'route':name,'sequence':selections,'forwardReverseExact':True,
                       'postimages':{p:sha(v) for p,v in final.items()}})
    staged_by_name = {entry['route']:entry for entry in staged}
    for left,right in queue.get('equivalentCompositionPairs',[]):
        assert staged_by_name[left]['postimages'] == staged_by_name[right]['postimages']
    receipt = {'status': 'passed-source-capsule-validation', 'activeSourceWrites': 0,
               'productBuilds': 0, 'gameSessions': 0, 'variants': rows,
               'composition': composition, 'exactStagedRoutes':staged,
               'limits': 'Memory-only exact patch validation. Does not authorize activation or prove ABI, GPU correctness or performance.'}
    output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'status': receipt['status'], 'variants': len(rows), 'receipt': str(output)}))


if __name__ == '__main__':
    main()
