#!/usr/bin/env python3
"""Prepare reviewed recording-local partial reuse; never edit active sources."""
import json
from prepare import OUT, ROOT, sha, replace_once, write_module, save_blob

TARGET = 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4PreparedResource.h'
BASE_SHA = 'd6222a17d4da569b0abd419f1c7e8b41c2f2101c7acf700e770aa02af7afa653'


def partial(text):
    if '#include <new>\n' not in text:
        text = replace_once(text, '#include <memory>\n', '#include <memory>\n#include <new>\n')
    text = replace_once(text,
        '// carries residency across recordings. Only a repeated descriptor combination\n'
        '// is admitted, so descriptor churn does not allocate/copy resource vectors.\n',
        '// carries residency across recordings. Full snapshots are admitted only for\n'
        '// repeated combinations. A changed combination may derive bounded CPU slices\n'
        '// for one recording; the next repeated observation uses normal full capture.\n')
    start = text.index('class MVKMetal4PreparedGroupSnapshot {')
    finish = text.index('\n// One full preparation per unchanged stage/set group', start)
    group = text[start:finish]
    group = replace_once(group,
        '        if (!entry || !entry->matchesBindings(stamp, revision)) { return Result::Miss; }\n',
        '''        if (!entry) { return Result::Miss; }
        std::shared_ptr<const Entry> partial;
        if (!entry->matchesBindings(stamp, revision)) {
            // A partial hit needs a residual consumer. A repeated combination
            // should use ordinary full capture instead of deriving every time.
            if (!retained || capture) { return Result::Miss; }
            std::array<bool, kMaxBindings> keep{};
            size_t keptBindings = 0, keptResources = 0;
            for (size_t i = 0; i < entry->covered.size(); ++i) {
                const auto& binding = entry->covered[i];
                keep[i] = binding.revision && binding.revision == revision(binding.set, binding.binding);
                if (keep[i]) { ++keptBindings; keptResources += binding.resourceCount; }
            }
            if (!keptBindings) { return Result::Miss; }
            try {
                auto selected = std::make_shared<Entry>();
                selected->stamp = stamp;
                selected->drawableIndependent = true;
                selected->resources.reserve(keptResources);
                selected->covered.reserve(keptBindings);
                selected->residual.reserve(entry->residual.size() + entry->covered.size() - keptBindings);
                selected->residual.assign(entry->residual.begin(), entry->residual.end());
                size_t cursor = 0;
                for (size_t i = 0; i < entry->covered.size(); ++i) {
                    const auto& binding = entry->covered[i];
                    if (keep[i]) {
                        selected->covered.push_back(binding);
                        selected->resources.insert(selected->resources.end(),
                            entry->resources.begin() + cursor,
                            entry->resources.begin() + cursor + binding.resourceCount);
                    } else { selected->residual.push_back(binding.ordinal); }
                    // Even changed bindings occupy a slice in the original entry.
                    cursor += binding.resourceCount;
                }
                std::sort(selected->residual.begin(), selected->residual.end());
                for (const auto& resource : selected->resources) {
                    if (resource.kind == MVKMetal4PreparedBindingSnapshots::Kind::Texture &&
                        !resource.drawableIndependent) { selected->drawableIndependent = false; }
                }
                partial = std::move(selected);
            } catch (const std::bad_alloc&) {
                // Optional metadata reuse must leave the original cache intact.
                return Result::Miss;
            }
        }
        // Keep the original entry alive for identity-checked invalidation. The
        // derived proof is recording-local and never replaces the global entry.
        const auto& replayEntry = partial ? partial : entry;
''')
    group = replace_once(group, '        for (const auto& resource : entry->resources) {\n',
                         '        for (const auto& resource : replayEntry->resources) {\n')
    group = replace_once(group, '        if (retained) { *retained = entry; }\n',
                         '        if (retained) { *retained = replayEntry; }\n')
    return text[:start] + group + text[finish:]


def main():
    before = (ROOT/TARGET).read_bytes()
    assert sha(before) == BASE_SHA
    nine_path = OUT/'modules/09-snapshot-unlocked-retain/module.json'
    nine = json.loads(nine_path.read_text())
    save_blob(nine_path.read_bytes())
    old_module = OUT/'modules/08b-partial-group-replay/module.json'
    if old_module.exists():
        save_blob(old_module.read_bytes())
    row = nine['variants']['R-and-Small']['files'][0]
    after09 = (OUT/row['after']['path']).read_bytes()
    assert row['target'] == TARGET and sha(after09) == row['after']['sha256']
    assert (OUT/row['before']['path']).read_bytes() == before
    after08 = partial(before.decode()).encode()
    combined = partial(after09.decode()).encode()
    # Apply the independently reviewed 09 class change in the opposite order.
    def binding_class(value):
        a = value.index('class MVKMetal4PreparedBindingSnapshots {')
        b = value.index('\nstruct MVKMetal4PreparedResourceIdentity', a)
        return value[a:b]
    inverse = replace_once(after08.decode(), binding_class(before.decode()), binding_class(after09.decode())).encode()
    assert inverse == combined
    result = write_module('08b-partial-group-replay', {
        'R-and-Small': [(TARGET, before, after08)],
        'after09': [(TARGET, after09, combined)]
    }, {
        'inventoryGroup':8,
        'title':'Recording-local reuse of unchanged covered binding slices',
        'implementation':'Unapplied exact source capsule; source design reviewed before code',
        'designReview':'design-deepening-08b.json',
        'preserves':['full-hit path', 'native retain/live checks', 'set incarnation', 'residual preparation',
                     'before/after stable-stamp guard', 'immutable global entry until ordinary full capture'],
        'limits':'Bounded CPU metadata allocation on partial hits; repeated new combination returns to ordinary full capture. Rejected capture may continue deriving. Fresh resource callbacks and weak proofs remain mandatory. No native ownership is shared. Profit depends on mixed binding churn; no GPU or FPS claim.',
        'requiredAfterCue':['Exact parent verification and affected native rebuild',
                            'Actual descriptor lifetime/alias/drawable/query and partial-path fixture',
                            'Matched performance comparison after frozen R/Small work']
    })
    variants = {}
    for name, value in nine['variants'].items():
        if name == 'after08b':
            continue
        variants[name] = [(f['target'], (OUT/f['before']['path']).read_bytes(), (OUT/f['after']['path']).read_bytes())
                          for f in value['files']]
    variants['after08b'] = [(TARGET, after08, combined)]
    metadata = {k:v for k,v in nine.items() if k not in ('id','variants','activation')}
    write_module(nine['id'], variants, metadata)
    print(json.dumps({'module':result['id'], 'variants':list(result['variants']),
                      'compositionSHA256':sha(combined),'activeSourceWrites':0}))


if __name__ == '__main__':
    main()
