"""Read-only OS input/load observations around the existing comparison runner."""
from pathlib import Path
import json, os, re, subprocess, time

_lastCPU = 0
_cpuRows = []
_totalCPU = 0

def sample():
    global _lastCPU, _cpuRows, _totalCPU
    raw = subprocess.check_output(['/usr/sbin/ioreg', '-r', '-c', 'IOHIDSystem', '-d', '1'], text=True, timeout=3)
    values = re.findall(r'"HIDIdleTime"\s*=\s*(\d+)', raw)
    if len(values) != 1:
        raise RuntimeError('HID idle observation unavailable')
    now = time.time()
    if now-_lastCPU >= 15:
        raw = subprocess.check_output(['/bin/ps', '-A', '-o', 'pid=,pcpu=,comm='], text=True, timeout=3)
        rows = []
        totalCPU = 0
        for line in raw.splitlines():
            parts = line.strip().split(None, 2)
            if len(parts) != 3:
                continue
            pid, cpu = int(parts[0]), float(parts[1])
            if pid != os.getpid():totalCPU += cpu
            if cpu >= 2 and pid != os.getpid():
                rows.append(dict(pid=pid, cpuPercent=cpu, name=Path(parts[2]).name))
        rows.sort(key=lambda x: x['cpuPercent'], reverse=True)
        _cpuRows, _lastCPU, _totalCPU = rows[:10], now, totalCPU
    return dict(atUnix=now, HIDIdleSeconds=int(values[0])/1e9, topCPU=_cpuRows, allProcessCPUPercent=_totalCPU, CPUSampledAtUnix=_lastCPU)

def record(path, row):
    with Path(path).open('a') as f:
        f.write(json.dumps(row)+'\n')

def wait_ready(folder, ordinal, cancelled):
    """No game launched until input is idle and a quiet CPU interval is observed."""
    folder = Path(folder)
    quiet_since = None
    last_report = 0
    while True:
        if cancelled():raise RuntimeError('Screen or power guard stopped during idle wait')
        row = sample()
        ready = row['HIDIdleSeconds'] >= 60 and row['allProcessCPUPercent'] < 50 and not any(x['cpuPercent'] >= 25 for x in row['topCPU'])
        quiet_since = (quiet_since or row['atUnix']) if ready else None
        row.update(phase='before-arm', ordinal=ordinal, ready=ready, quietSince=quiet_since)
        record(folder/'idle-load-observations.jsonl', row)
        if quiet_since is not None and row['atUnix']-quiet_since >= 30:
            if cancelled():raise RuntimeError('Screen or power guard stopped before arm start')
            return row
        if row['atUnix']-last_report >= 30:
            print(json.dumps(dict(event='waiting-for-input-and-load-idle', **row)), flush=True)
            last_report = row['atUnix']
        time.sleep(5)

def assert_input_idle_window(folder, receipt):
    r = json.loads(Path(receipt).read_text())
    start = r['timing']['benchmarkStartUnixMS']/1000
    finish = r['timing']['benchmarkFinishUnixMS']/1000
    rows = [json.loads(s) for s in (Path(folder)/'idle-load-observations.jsonl').read_text().splitlines()]
    rows.sort(key=lambda s:s['atUnix'])
    earlier = [s for s in rows if s['atUnix'] <= start]
    later = [s for s in rows if s['atUnix'] >= finish]
    if not earlier or not later:
        raise RuntimeError('Benchmark input endpoint coverage missing')
    before, after = earlier[-1], later[0]
    covered = [s for s in rows if before['atUnix'] <= s['atUnix'] <= after['atUnix']]
    if start-before['atUnix'] > 6 or after['atUnix']-finish > 6:
        raise RuntimeError('Benchmark input endpoint coverage too sparse')
    if any(b['atUnix']-a['atUnix'] > 6 for a,b in zip(covered,covered[1:])):
        raise RuntimeError('Benchmark input observation gap too large')
    last_inputs = [s['atUnix']-s['HIDIdleSeconds'] for s in covered]
    if any(start+0.5 < v < finish-0.5 for v in last_inputs):
        raise RuntimeError('Input observed inside benchmark; retain separately, no automatic replay')
    # The first post-end sample must still show idle predating the start. A
    # post-end input can mask a near-end input: classify this as uncertain,
    # never label it definitely inside the window or silently accept it.
    if any(v > start-0.5 for v in last_inputs):
        raise RuntimeError('Input boundary coverage ambiguous; retain separately, no automatic replay')
    return dict(benchmarkStartUnix=start, benchmarkFinishUnix=finish, observations=len(covered), noInputObserved=True,
                endpointBeforeUnix=before['atUnix'],endpointAfterUnix=after['atUnix'],boundaryToleranceSeconds=0.5,
                backgroundLoadFullyControlled=False)
