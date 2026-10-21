#!/usr/bin/env python3
"""Offline summary of macOS sample call trees; never interprets counts as CPU time."""
from pathlib import Path
import collections
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parent
PATTERNS = {
    'mvk_any': r'\(in libMoltenVK',
    'queue_submit': r'^vkQueueSubmit ',
    'command_replay': r'^MVKCommandEncoder::encodeCommands\(',
    'prepare_draw': r'^MVKCommandEncoderState::prepareMetal4Draw\(',
    'bind_resources': r'^\(anonymous namespace\)::bindMetal4Resources\(',
    'register_resource': r'^MVKMetal4Submission::addResource\(',
    'add_resident': r'^MVKMetal4SubmissionState::addResident\(',
    'residency_lease': r'^MVKMetal4DeviceResidency::lease\(',
    'protocol_check': r'conformsToProtocol|class_conformsToProtocol|_class_conformsToProtocol|protocol_conformsToProtocol',
    'group_cache': r'^MVKMetal4PreparedGroup',
    'texture_binding_cache': r'^MVKMetal4PreparedTextureBindingCache',
    'render_pass_begin': r'^MVKCommandEncoder::beginMetal(?:4)?RenderPass\(',
    'native_render_encoder_create': r'^-\[AGX.* renderCommandEncoderWithDescriptor:',
    'allocator_lifecycle': r'acquireAllocator|resetAllocator|finishAllocator|MVKMetal4AllocatorUse|CommandAllocator.* (reset|init)|newCommandAllocator',
    'recording_pool_begin': r'^MVKMetal4RecordingPool::begin\(',
    'barrier': r'^MVK.*[Bb]arrier|^-\[.*[Bb]arrier',
    'query_results': r'^vkGetQueryPoolResults |^MVK.*getResults\(',
    'query_wait': r'^MVKQueryPool::waitForQueries',
    'fence_wait': r'^vkWaitForFences |^MVK.*waitForFences|^mvkWaitForFences',
    'condition_wait': r'^__psynch_cvwait ',
    'mutex_wait': r'^__psynch_mutexwait ',
    'geometry_query': r'^MacSDL3EGL::QueryDisplayGeometry\(',
    'windowserver_ipc': r'^get_current_display_system_state\(',
}
rx = {k: re.compile(v) for k,v in PATTERNS.items()}

def analyze(path):
    text = path.read_text()
    nodes, stack, roots = [], [], []
    active = False
    for line_number,line in enumerate(text.splitlines(),1):
        if line == 'Call graph:': active=True; continue
        if line.startswith('Total number in stack'): break
        if not active: continue
        m = re.match(r'^([ +!:\|]*?)(\d+) (.*)$',line)
        if not m: continue
        prefix,count,frame=m.groups()
        depth=len(prefix)
        while stack and nodes[stack[-1]]['depth'] >= depth: stack.pop()
        parent=stack[-1] if stack else None
        index=len(nodes)
        node={'count':int(count),'frame':frame,'depth':depth,'line':line_number,'children':[], 'parent':parent}
        nodes.append(node)
        if parent is None: roots.append(index)
        else: nodes[parent]['children'].append(index)
        stack.append(index)
    invalid=[]
    for n in nodes:
        n['self']=n['count']-sum(nodes[c]['count'] for c in n['children'])
        if n['self']<0: invalid.append({'line':n['line'],'count':n['count'],'children':n['children']})
    assert not invalid,invalid[:10]

    def union(index,predicate):
        node=nodes[index]
        if predicate(node): return node['count']
        return sum(union(c,predicate) for c in node['children'])

    threads=[]
    aggregate=collections.Counter()
    for index in roots:
        counts={k:union(index,lambda n,p=p:bool(p.search(n['frame']))) for k,p in rx.items()}
        aggregate.update(counts)
        threads.append({'thread':nodes[index]['frame'],'sampleCount':nodes[index]['count'], 'line':nodes[index]['line'], 'inclusiveUnion':counts})
    registration=[]
    for n in nodes:
        if not rx['register_resource'].search(n['frame']): continue
        index=nodes.index(n)
        # addResource is not recursive here; retain evidence for manual inspection.
        registration.append({'line':n['line'],'count':n['count'],
            'protocolCheck':union(index,lambda x:bool(rx['protocol_check'].search(x['frame']))),
            'residencyLease':union(index,lambda x:bool(rx['residency_lease'].search(x['frame']))),
            'mutexWait':union(index,lambda x:bool(rx['mutex_wait'].search(x['frame']))),
            'frame':n['frame']})
    top=collections.Counter()
    for n in nodes:
        if n['self'] and '(in libMoltenVK' in n['frame']:
            top[n['frame'].split('  (in ')[0]]+=n['self']
    return {'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'header':text.split('Call graph:')[0], 'nodes':len(nodes),'threadGroups':len(roots),
        'childCountValidation':True,'allThreadSampleCount':sum(nodes[i]['count'] for i in roots),
        'threads':threads,'aggregateInclusiveUnion':dict(aggregate),
        'addResourceSubtrees':registration,
        'registrationProtocolCheckSum':sum(x['protocolCheck'] for x in registration),
        'registrationResidencyLeaseSum':sum(x['residencyLease'] for x in registration),
        'registrationMutexWaitSum':sum(x['mutexWait'] for x in registration),
        'topMVKSelf':top.most_common(30)}

result={'method':'Call-tree inclusive counts unioned once per matching subtree; offsets collapsed by pattern; nested matches not double counted within a category.',
    'limitations':['One 10-second requested observation per backend; includes blocked/runnable/running threads, no CPU-state classification.',
        'Counts are sample-stack observations, not calls, milliseconds, CPU utilization, GPU time, or attributable FPS.',
        'Categories overlap and must not be added together. Non-observation does not establish zero cost.',
        'Unresolved/deduplicated/inlined symbols reduce category visibility. No cache hit/miss or pass-reason counts.'],
    'patterns':PATTERNS,
    'observations':[analyze(p) for p in sorted(ROOT.glob('*-candidate-metal*/sessions/*/cpu-sample.txt'))]}
assert len(result['observations'])==2
(ROOT/'sample-analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
for observation in result['observations']:
    print(observation['path'])
    print(json.dumps({'aggregate':observation['aggregateInclusiveUnion'],
      'registrationProtocolCheck':observation['registrationProtocolCheckSum'],
      'registrationLease':observation['registrationResidencyLeaseSum'],
      'registrationMutexWait':observation['registrationMutexWaitSum'],
      'threads':[x for x in observation['threads'] if x['inclusiveUnion']['mvk_any'] or 'main-thread' in x['thread']]},ensure_ascii=False,indent=2))
