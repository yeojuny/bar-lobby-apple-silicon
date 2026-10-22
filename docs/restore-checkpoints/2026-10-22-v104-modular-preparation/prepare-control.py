#!/usr/bin/env python3
"""Prepare reviewed source capsules 02/03/09; no active source writes."""
from pathlib import Path
import json
from prepare import OUT, ROOT, sha, replace_once, write_module

BASE = 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/'
PINS = {
    'Commands/MVKCmdPipeline.mm': '8e663764a00e70ae9b6ede6996da275a9c0aad8a4de632fab8e9ed20e80e1d33',
    'GPUObjects/MVKDescriptorSet.h': 'fb7583ab4debcf0e8f6afcaa1abc62b87d80e1b457280a77136d3cf5afaae1f5',
    'GPUObjects/MVKDescriptorSet.mm': 'b87caab357dd43ba2c2cd937dcd7cdd0836c6418f90ddc5d2b90e13022257dc4',
    'Commands/MVKCommandBuffer.h': 'ea6eb8b685fe9a180c2f53faa08b0ca19545a1b764f426c3aac5eadd7b35609a',
    'Commands/MVKCommandBuffer.mm': 'c66515484dfda8a7d5b05ed45622b03f64e9695eedcbb607d4e71387eb354c74',
    'GPUObjects/MVKMetal4PreparedResource.h': 'd6222a17d4da569b0abd419f1c7e8b41c2f2101c7acf700e770aa02af7afa653',
}


def source(path):
    data = (ROOT / BASE / path).read_bytes()
    assert sha(data) == PINS[path], path
    return data.decode()


def module(name, number, changed, **metadata):
    rows = [(BASE+p, source(p).encode(), value.encode()) for p, value in changed.items()]
    return write_module(name, {'R-and-Small': rows}, dict(
        inventoryGroup=number, implementation='Unapplied exact source capsule',
        designReview='design-deepening-02-03-09.json; independent reviewer source-path approval',
        requiredAfterCue=['Recheck exact parent and finished frozen R/Small comparison',
                          'Related incremental builds, functional GPU checks and separate performance comparison'],
        **metadata))


def layout_policy():
    p = 'Commands/MVKCmdPipeline.mm'
    old = source(p)
    start = old.index('\t\tfor (const auto& binding : set->layout->bindings()) {', old.index('MVKCmdBindDescriptorSetsStatic<N>::getMetal4RecordPolicy()'))
    end = old.index('\n\t}\n\treturn MVKMetal4RecordPolicy::State;', start)
    new = old[:start] + '\t\tif (!set->layout->metal4EarlyRecordEligible()) { return MVKMetal4RecordPolicy::Deferred; }' + old[end:]
    h = 'GPUObjects/MVKDescriptorSet.h'
    header = source(h)
    header = replace_once(header, '\tMVKArrayRef<const MVKDescriptorBinding> bindings() const { return _bindings; }\n',
        '\tMVKArrayRef<const MVKDescriptorBinding> bindings() const { return _bindings; }\n'
        '#if MVK_BUILD_METAL4_FOUNDATION\n'
        '\tbool metal4EarlyRecordEligible() const { return _metal4EarlyRecordEligible; }\n'
        '#endif\n')
    header = replace_once(header, '\tMVKInlineArray<MVKDescriptorBinding> _bindings;\n',
        '\tMVKInlineArray<MVKDescriptorBinding> _bindings;\n'
        '#if MVK_BUILD_METAL4_FOUNDATION\n'
        '\t// Immutable after Create; empty layouts satisfy the original predicate.\n'
        '\tbool _metal4EarlyRecordEligible = true;\n'
        '#endif\n')
    q = 'GPUObjects/MVKDescriptorSet.mm'
    impl = source(q)
    anchor = '\t\tif (flagList)\n\t\t\tret->_bindings[i].flags |= flagList[i] & MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS;\n'
    impl = replace_once(impl, anchor, anchor + '''#if MVK_BUILD_METAL4_FOUNDATION
		const auto& binding = ret->_bindings[i];
		if (binding.flags & MVK_DESCRIPTOR_BINDING_ALL_VULKAN_FLAG_BITS) {
			ret->_metal4EarlyRecordEligible = false;
		}
		switch (binding.descriptorType) {
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:
			case VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC:
			case VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: break;
			default: ret->_metal4EarlyRecordEligible = false;
		}
#endif
''')
    return module('02-layout-policy', 2, {p:new,h:header,q:impl},
        title='Immutable layout early-record predicate',
        limits='Original predicate only. Does not admit compact push; BAR early-prefix reach and benefit remain unmeasured.')


def replay_chain():
    h = 'Commands/MVKCommandBuffer.h'
    header = replace_once(source(h), '    std::vector<MVKCommand*> _metal4PreparedReplay;\n',
        '    // Exclusively owned prefix; no node is pool-owned until detached release.\n'
        '    MVKCommand* _metal4PreparedReplayHead = nullptr;\n'
        '    MVKCommand* _metal4PreparedReplayTail = nullptr;\n')
    p = 'Commands/MVKCommandBuffer.mm'
    impl = replace_once(source(p), '            _metal4PreparedReplay.push_back(command);\n',
        '            if (_metal4PreparedReplayTail) { _metal4PreparedReplayTail->_next = command; }\n'
        '            else { _metal4PreparedReplayHead = command; }\n'
        '            _metal4PreparedReplayTail = command;\n')
    impl = replace_once(impl,
        '    for (auto* command : _metal4PreparedReplay) { releaseCommands(command, asyncReturn); }\n'
        '    _metal4PreparedReplay.clear();\n',
        '    auto* head = _metal4PreparedReplayHead;\n'
        '    _metal4PreparedReplayHead = _metal4PreparedReplayTail = nullptr;\n'
        '    // releaseCommands saves each successor before an async pool reuses _next.\n'
        '    releaseCommands(head, asyncReturn);\n')
    old = '''    for (size_t i = 1; i < _metal4PreparedReplay.size(); ++i) {
        _metal4PreparedReplay[i - 1]->_next = _metal4PreparedReplay[i];
    }
    if (!_metal4PreparedReplay.empty()) {
        _metal4PreparedReplay.back()->_next = _head;
        if (!_tail) { _tail = _metal4PreparedReplay.back(); }
        _head = _metal4PreparedReplay.front();
        _metal4PreparedReplay.clear();
    }
'''
    impl = replace_once(impl, old, '''    if (_metal4PreparedReplayHead) {
        _metal4PreparedReplayTail->_next = _head;
        if (!_tail) { _tail = _metal4PreparedReplayTail; }
        _head = _metal4PreparedReplayHead;
    }
    _metal4PreparedReplayHead = _metal4PreparedReplayTail = nullptr;
''')
    return module('03-owned-replay-chain', 3, {h:header,p:impl},
        title='Exclusive prepared-prefix replay chain',
        limits='Preserves multiview encode-before-transfer and single ownership. Does not alter async-return or early-record eligibility. Long-prefix frequency/benefit unmeasured.')


def snapshot_replay():
    p = 'GPUObjects/MVKMetal4PreparedResource.h'
    text = source(p)
    text = replace_once(text, '#include <memory>\n', '#include <memory>\n#include <new>\n')
    start = text.index('class MVKMetal4PreparedBindingSnapshots {')
    end = text.index('\nstruct MVKMetal4PreparedResourceIdentity', start)
    body = text[start:end]
    body = replace_once(body, '''        std::vector<Resource> resources;
    };
    std::mutex _mutex;
    std::unordered_map<uint32_t, Entry> _bindings;''', '''        std::vector<Resource> resources;
        Entry(uint64_t rev, std::vector<Resource>&& value)
            : revision(rev), resources(std::move(value)) {}
    };
    std::mutex _mutex;
    std::unordered_map<uint32_t, std::shared_ptr<const Entry>> _bindings;''')
    body = body.replace('it->second.revision', 'it->second->revision').replace('it->second.resources', 'it->second->resources')
    a = body.index('    template<class Retain>\n')
    b = body.index('    void remember(', a)
    body = body[:a]+'''    template<class Retain>
    Result replay(uint32_t binding, uint64_t revision, const Retain& retain) {
        std::shared_ptr<const Entry> entry;
        {
            std::lock_guard<std::mutex> lock(_mutex);
            auto it = _bindings.find(binding);
            if (!revision || it == _bindings.end() || it->second->revision != revision) { return Result::Miss; }
            entry = it->second;
        }
        // The entry owns only CPU metadata/weak proofs. The callback must still
        // acquire live native resources for this recording under its own guards.
        for (const auto& resource : entry->resources) {
            auto result = retain(resource);
            if (result != Result::Hit) {
                if (result == Result::Miss) {
                    std::lock_guard<std::mutex> lock(_mutex);
                    auto it = _bindings.find(binding);
                    if (it != _bindings.end() && it->second == entry) { _bindings.erase(it); }
                }
                return result;
            }
        }
        return Result::Hit;
    }
''' + body[b:]
    body = replace_once(body, '''        if (it != _bindings.end()) { it->second = {revision, std::move(resources)}; }
        else if (_bindings.size() < kMaxBindings) { _bindings.emplace(binding, Entry{revision, std::move(resources)}); }
''', '''        if (it == _bindings.end() && _bindings.size() >= kMaxBindings) { return; }
        try {
            auto entry = std::make_shared<const Entry>(revision, std::move(resources));
            if (it != _bindings.end()) { it->second = std::move(entry); }
            else { _bindings.emplace(binding, std::move(entry)); }
        } catch (const std::bad_alloc&) {
            // Optional cache admission must not disturb the old entry or the
            // current recording's already acquired native resource ownership.
        }
''')
    text = text[:start]+body+text[end:]
    return module('09-snapshot-unlocked-retain', 9, {p:text},
        title='Immutable per-binding entry across unlocked replay',
        limits='Adds shared ownership/allocation cost. Map remains limited to64; concurrently replayed replaced entries may outlive the map. No native ownership is extended. Contention/benefit not established.')


if __name__ == '__main__':
    values = [layout_policy(), replay_chain(), snapshot_replay()]
    print(json.dumps({'modules':[m['id'] for m in values], 'activeSourceWrites':0}))
