#!/usr/bin/env python3
"""Prepare approved 06/07 capsules without applying active-source changes.

Run by the single coordinator. All writes are confined to this evidence tree.
"""
import importlib.util
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('modular_common', OUT / 'prepare.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
TARGET = 'build/run66-moltenvk-src-20260903/MoltenVK/MoltenVK/GPUObjects/MVKMetal4Submission.mm'
BASELINE = '2e680f300575bdd99816c32252ef62c8ca8ad0398f5cd2543399b915ef8e012f'


def success_notify(text):
    return common.replace_once(text,
        '    notifyGroupWaiters(group);\n    if (feedback.error) { failSignalNotificationOwners(queue, feedback.error); }',
        '    // Success feedback alone changes neither public wait predicate.\n'
        '    // Errors must still wake waiters even when no error handler exists.\n'
        '    if (feedback.error) { notifyGroupWaiters(group); }\n'
        '    if (feedback.error) { failSignalNotificationOwners(queue, feedback.error); }')


PROOF = '''// A submit-local proof of relative signal order for one fresh, strongly held
// group. Ended children are exclusively claimed; legal event mutators reject
// them, and neither child order nor signal arrays change before publication.
// Current shared-event values are deliberately NOT part of this proof.
class GroupSignalOrderProof {
    const MVKMetal4SubmissionGroup* _group = nullptr;
    friend bool validateAndProveGroupSignals(const MVKMetal4SubmissionGroup&, NSError**, GroupSignalOrderProof&);
public:
    GroupSignalOrderProof() = default;
    GroupSignalOrderProof(const GroupSignalOrderProof&) = delete;
    GroupSignalOrderProof& operator=(const GroupSignalOrderProof&) = delete;
    GroupSignalOrderProof(GroupSignalOrderProof&&) = delete;
    GroupSignalOrderProof& operator=(GroupSignalOrderProof&&) = delete;
    bool covers(const MVKMetal4SubmissionGroup& group) const { return _group == &group; }
};

'''

FACTORY = '''
// Only a successful complete check creates a proof. Reusing a local output
// after failure must not preserve a prior group's proof.
bool validateAndProveGroupSignals(const MVKMetal4SubmissionGroup& group, NSError** error,
                                 GroupSignalOrderProof& proof) {
    proof._group = nullptr;
    if (!validGroupSignals(group, error)) { return false; }
    proof._group = &group;
    return true;
}
'''


def signal_proof(text):
    marker = 'bool validGroupSignals(const MVKMetal4SubmissionGroup& group, NSError** error) {'
    text = common.replace_once(text, marker, PROOF +
        'bool validGroupSignals(const MVKMetal4SubmissionGroup& group, NSError** error,\n'
        '                       const GroupSignalOrderProof* proof = nullptr) {\n'
        '    const bool checkRelativeOrder = !proof || !proof->covers(group);')
    text = common.replace_once(text,
        '            for (size_t before = 0; before <= i; ++before) {',
        '            if (!checkRelativeOrder) { continue; }\n'
        '            for (size_t before = 0; before <= i; ++before) {')
    marker = '// The submit lock is held. All children are exclusively claimed before this'
    text = common.replace_once(text, marker, FACTORY + '\n' + marker)
    text = common.replace_once(text,
        '                               bool notificationRegistered, NotificationSlotReservation& reservation,\n'
        '                               NSError** error) {',
        '                               bool notificationRegistered, NotificationSlotReservation& reservation,\n'
        '                               NSError** error, const GroupSignalOrderProof* orderProof = nullptr) {')
    # There are exactly two identical old calls: first inside publication, then
    # submit's initial complete check. Bind each by its following unique text.
    text = common.replace_once(text,
        '    if (!validGroupSignals(*group, error)) { return false; }\n'
        '    std::lock_guard<std::mutex> queueLock(queue->stateMutex);',
        '    if (!validGroupSignals(*group, error, orderProof)) { return false; }\n'
        '    std::lock_guard<std::mutex> queueLock(queue->stateMutex);')
    text = common.replace_once(text,
        '    if (!validGroupSignals(*group, error)) { return false; }\n'
        '    bool needsSignalRetirement = false;',
        '    GroupSignalOrderProof orderProof;\n'
        '    if (!validateAndProveGroupSignals(*group, error, orderProof)) { return false; }\n'
        '    bool needsSignalRetirement = false;')
    return common.replace_once(text,
        '    if (!publishPreparedSubmission(group, childLocks, std::move(tail), notificationRegistered, notification, error)) {',
        '    if (!publishPreparedSubmission(group, childLocks, std::move(tail), notificationRegistered, notification, error, &orderProof)) {')


def main():
    before = (common.ROOT / TARGET).read_bytes()
    assert common.sha(before) == BASELINE, 'Frozen R/Small Submission baseline changed'
    base = before.decode()
    six, seven = success_notify(base), signal_proof(base)
    combined = signal_proof(six)
    assert combined == success_notify(seven), '06/07 composition must commute byte-for-byte'
    six, seven, combined = six.encode(), seven.encode(), combined.encode()
    shared = {
        'scope': 'Identical frozen R and Small Submission.mm; no public header or allocator change',
        'sourceBaselineSHA256': BASELINE,
        'designReportSHA256': '05099202a4696095160ed6310e283e3f1c124e9007d919e28cf54a533d2d9e86',
        'preserves': ['diagnostics compile/runtime policy', 'Q/R allocator ownership',
                      'group/child/queue lock order', 'GPU and signal retirement gates',
                      'first-error/poison paths', 'event operation ownership'],
        'requiredAfterCue': ['source-derived CPU cases and foundation ON/OFF syntax',
                             'related actual queue/error/signal GPU cases',
                             'one active build and isolated signed app before performance'],
        'limits': 'Prepared evidence only; no active changes, native acceptance, time, memory or FPS benefit claimed.'
    }
    m6 = common.write_module('06-success-notify', {
        'R-and-Small': [(TARGET, before, six)],
        'after07': [(TARGET, seven, combined)]
    }, dict(shared, inventoryGroup=6, title='Skip success-only pre-retirement wakeups',
            predicate='feedback.error, never runErrors; final and error notifications unchanged'))
    m7 = common.write_module('07-signal-order-proof', {
        'R-and-Small': [(TARGET, before, seven)],
        'after06': [(TARGET, six, combined)]
    }, dict(shared, inventoryGroup=7, title='Submit-local immutable signal-order proof',
            proof='Noncopyable exact fresh group identity, failed factory clears, optional absence falls back',
            alwaysRecheck='Current value on every signal before publication',
            immutabilityLimit='Legal Ended API mutation is rejected; arbitrary private synthetic vector mutation violates the contract.'))
    print(json.dumps({'modules': [m6['id'], m7['id']],
                      'baselineSHA256': BASELINE, 'combinedSHA256': common.sha(combined),
                      'activeSourceWrites': 0}, indent=2))


if __name__ == '__main__':
    main()
