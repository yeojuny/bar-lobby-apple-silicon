#!/usr/bin/env python3
"""Prepare approved compact-only CPU State capsule; never apply active files."""
import json
from pathlib import Path
from prepare import OUT, ROOT, sha, replace_once, write_module, save_blob

BASE = 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/Commands/'


def compact_header(text):
    start = text.index('class MVKCmdPushDescriptorSetWithTemplate :')
    end = text.index('\n};', start) + 3
    prefix, body = text[:start], text[start:end]
    body = replace_once(body, '#if MVK_BUILD_METAL4_FOUNDATION\n',
        '#if MVK_BUILD_METAL4_FOUNDATION\n'
        '    // Only an already captured singleton-UBO payload is CPU-only State.\n'
        '    MVKMetal4RecordPolicy getMetal4RecordPolicy() const override {\n'
        '        return _compactUniformWriteCount ? MVKMetal4RecordPolicy::State : MVKMetal4RecordPolicy::Deferred;\n'
        '    }\n')
    body = replace_once(body,
        '\t// Capture only singleton UBOs; this does not admit early native recording.',
        '\t// Capture only singleton UBOs; completed capture may be early CPU State.')
    return prefix + body + text[end:]


def compact_source(text):
    text = replace_once(text,
        '\t// Replay owns all interpretation metadata and still resolves native buffers\n'
        '\t// at the original encode point. No query or record-policy state changes.\n',
        '\t// The node owns all interpretation metadata. Native buffer addresses\n'
        '\t// are resolved when encoded; UBO data bytes are not snapshotted.\n'
        '\t// Compact record-policy admission is defined separately.\n')
    return replace_once(text,
        'void MVKCmdPushDescriptorSetWithTemplate::encode(MVKCommandEncoder* cmdEncoder) {\n'
        '\tif (_compactUniformWriteCount) {\n',
        'void MVKCmdPushDescriptorSetWithTemplate::encode(MVKCommandEncoder* cmdEncoder) {\n'
        '\tif (_compactUniformWriteCount) {\n'
        '#if MVK_BUILD_METAL4_FOUNDATION\n'
        '\t\t// A pooled command may be reused before the prepared encoder finishes.\n'
        '\t\tif (cmdEncoder->isUsingMetal4()) { cmdEncoder->retainMetal4VulkanState(_pipelineLayout); }\n'
        '#endif\n')


def main():
    header = (ROOT / (BASE + 'MVKCmdPipeline.h')).read_bytes()
    source = (ROOT / (BASE + 'MVKCmdPipeline.mm')).read_bytes()
    design = json.loads((OUT / 'design-deepening-04.json').read_text())
    pins = {p['path']: p['sha256'] for p in design['readPins']}
    assert sha(header) == pins[BASE + 'MVKCmdPipeline.h']
    assert sha(source) == pins[BASE + 'MVKCmdPipeline.mm']
    after_header, after_source = compact_header(header.decode()).encode(), compact_source(source.decode()).encode()
    manifest_path = OUT / 'modules/02-layout-policy/module.json'
    original_manifest = manifest_path.read_bytes()
    policy = json.loads(original_manifest)
    previous04 = OUT / 'modules/04-compact-cpu-state/module.json'
    if previous04.exists():
        original_spec = json.loads(previous04.read_text())['module02OriginalManifest']
        original_bytes = (OUT / original_spec['path']).read_bytes()
        assert sha(original_bytes) == original_spec['sha256']
    else:
        original_spec = save_blob(original_manifest)
    policy_files = policy['variants']['R-and-Small']['files']
    policy_source = next(f for f in policy_files if f['target'] == BASE + 'MVKCmdPipeline.mm')
    after02 = (OUT / policy_source['after']['path']).read_bytes()
    assert sha(after02) == policy_source['after']['sha256']
    combined = compact_source(after02.decode()).encode()
    # Independently substitute exactly module 02's original diff block into
    # the 04 postimage, so reverse ordering is checked without fuzzy patching.
    # The policy transform occupies only the static-bind policy function.
    before_text, policy_text = source.decode(), after02.decode()
    start = before_text.index('MVKMetal4RecordPolicy MVKCmdBindDescriptorSetsStatic<N>::getMetal4RecordPolicy() const {')
    end = before_text.index('\n#endif', start)
    policy_end = policy_text.index('\n#endif', start)
    reverse_order = replace_once(after_source.decode(), before_text[start:end], policy_text[start:policy_end]).encode()
    assert reverse_order == combined
    module = write_module('04-compact-cpu-state', {
        'R-and-Small': [(BASE + 'MVKCmdPipeline.h', header, after_header),
                        (BASE + 'MVKCmdPipeline.mm', source, after_source)],
        'after02': [(BASE + 'MVKCmdPipeline.h', header, after_header),
                    (BASE + 'MVKCmdPipeline.mm', after02, combined)]
    }, {'inventoryGroup': 4, 'title': 'Captured singleton UBO push as early CPU State',
        'designReportSHA256': design['reportSHA256'],
        'module02OriginalManifest': original_spec,
        'preserves': ['Generic and mixed push stay Deferred', 'Foundation OFF and Metal3 behavior',
                      'Mapped bytes read at execution', 'Query activation/fallback and native ownership gates'],
        'requiredAfterCue': ['Header-dependent build', 'Actual early path Vulkan case with regular SSBO set0 and compact UBO set1',
                             'Native latest mapped content, cancel, timestamp fallback and M3 checks',
                             'BAR reach and controlled performance before benefit/adoption claim'],
        'limits': 'CPU/syntax preparation only; existing compact Vulkan case first uses Deferred ordinary push and does not exercise this new early path.'})
    # Append only the approved 02-after04 stage; preserve every existing 02
    # variant and metadata field byte-for-byte semantically.
    rows = []
    for f in policy_files:
        before = (OUT / f['before']['path']).read_bytes(); after = (OUT / f['after']['path']).read_bytes()
        if f['target'] == BASE + 'MVKCmdPipeline.mm':
            before, after = after_source, combined
        rows.append((f['target'], before, after))
    metadata = {k: v for k, v in policy.items() if k not in ('id', 'activation', 'variants')}
    # write_module normally replaces a manifest. Keep original immutable variant
    # in memory, then merge the generated staged variant back into the manifest.
    generated = write_module('02-layout-policy', {'after04': rows}, metadata)
    policy['variants']['after04'] = generated['variants']['after04']
    manifest_path.write_text(json.dumps(policy, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'module': module['id'], 'combinedMM_SHA256': sha(combined),
                      'module02BeforeManifestSHA256': sha(original_manifest),
                      'module02AfterManifestSHA256': sha(manifest_path.read_bytes()),
                      'reverseOrderByteExact': True, 'activeSourceWrites': 0}, indent=2))


if __name__ == '__main__':
    main()
