// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import assert from "node:assert/strict";
import type { ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import fs from "node:fs/promises";
import { syncBuiltinESMExports } from "node:module";
import os from "node:os";
import path from "node:path";
import { setImmediate } from "node:timers/promises";
import test, { type TestContext } from "node:test";
import { publishContentMetadata, shutdownContentWriters, waitForContentWriterClose, withContentWrite } from "../../src/main/content/content-write-coordinator.ts";

function deferred() {
    let resolve!: () => void;
    const promise = new Promise<void>((done) => {
        resolve = done;
    });
    return { promise, resolve };
}

function fakeChild() {
    return new EventEmitter() as ChildProcess;
}

// Resolved mock I/O makes queue admission deterministic after a single event-loop
// turn. A separate test exercises real canonicalization/publication before the
// final test permanently latches shutdown.
function mockDirectories(t: TestContext, canonicalize: (directory: string) => string = (directory) => directory) {
    t.mock.method(fs, "mkdir", async () => undefined);
    t.mock.method(fs, "realpath", async (directory: string) => canonicalize(directory));
}

test("same canonical assets serialize writer lifetimes through close, not exit", { timeout: 5000 }, async (t) => {
    mockDirectories(t, () => "/canonical/shared-assets");
    const events: string[] = [];
    const firstStarted = deferred();
    const secondStarted = deferred();
    const firstChild = fakeChild();
    const secondChild = fakeChild();
    let active = 0;
    const writer = (name: string, child: ChildProcess, started: ReturnType<typeof deferred>) => async () => {
        assert.equal(++active, 1, "overlapping writers");
        events.push(`${name}:start`);
        started.resolve();
        await waitForContentWriterClose(child);
        events.push(`${name}:close`);
        active--;
    };
    const first = withContentWrite("/diagnostic/assets", writer("ordinary", firstChild, firstStarted));
    await firstStarted.promise;
    const second = withContentWrite("/diagnostic/assets-alias", writer("chobby", secondChild, secondStarted));
    await setImmediate();
    assert.deepEqual(events, ["ordinary:start"]);
    firstChild.emit("exit", 0, null);
    await setImmediate();
    assert.deepEqual(events, ["ordinary:start"], "exit must not release the slot");
    firstChild.emit("close", 0, null);
    await secondStarted.promise;
    secondChild.emit("close", 0, null);
    await Promise.all([first, second]);
    assert.deepEqual(events, ["ordinary:start", "ordinary:close", "chobby:start", "chobby:close"]);
    assert.equal(active, 0);
});

test("child error waits for close and releases the queued writer", { timeout: 5000 }, async (t) => {
    mockDirectories(t);
    const child = fakeChild();
    const started = deferred();
    let nextRan = false;
    const first = withContentWrite("/failure/assets", () => {
        started.resolve();
        return waitForContentWriterClose(child);
    });
    const failed = assert.rejects(first, /simulated spawn failure/);
    await started.promise;
    const next = withContentWrite("/failure/assets", () => {
        nextRan = true;
    });
    await setImmediate();
    child.emit("error", new Error("simulated spawn failure"));
    await setImmediate();
    assert.equal(nextRan, false);
    child.emit("close", -2, null);
    await Promise.all([failed, next]);
    assert.equal(nextRan, true);
});

test("synchronous throws and rejected writers do not poison the queue", { timeout: 5000 }, async (t) => {
    mockDirectories(t);
    await assert.rejects(withContentWrite("/throw/assets", () => {
        throw new Error("synchronous failure");
    }), /synchronous failure/);
    await assert.rejects(withContentWrite("/throw/assets", () => Promise.reject(new Error("async failure"))), /async failure/);
    assert.equal(await withContentWrite("/throw/assets", () => "recovered"), "recovered");
});

test("distinct assets directories can write concurrently", { timeout: 5000 }, async (t) => {
    mockDirectories(t);
    const holdFirst = deferred();
    const firstStarted = deferred();
    const secondStarted = deferred();
    let firstActive = false;
    const first = withContentWrite("/distinct/one", async () => {
        firstActive = true;
        firstStarted.resolve();
        await holdFirst.promise;
        firstActive = false;
    });
    await firstStarted.promise;
    const second = withContentWrite("/distinct/two", () => {
        assert.equal(firstActive, true);
        secondStarted.resolve();
    });
    await secondStarted.promise;
    holdFirst.resolve();
    await Promise.all([first, second]);
});

test("metadata publication waits for downloader closure and uses a unique temporary file", { timeout: 5000 }, async (t) => {
    mockDirectories(t);
    const writes: string[] = [];
    const publications: string[] = [];
    t.mock.method(fs, "writeFile", async (filename: string, contents: string, options: { flag: string }) => {
        assert.equal(contents, "new index");
        assert.equal(options.flag, "wx");
        writes.push(filename);
    });
    t.mock.method(fs, "rename", async (from: string, to: string) => {
        assert.equal(from, writes[0]);
        publications.push(to);
    });
    t.mock.method(fs, "rm", async () => undefined);
    const child = fakeChild();
    const started = deferred();
    const writer = withContentWrite("/metadata/assets", () => {
        started.resolve();
        return waitForContentWriterClose(child);
    });
    await started.promise;
    const destination = "/metadata/assets/rapid/repo/versions.gz";
    const publish = publishContentMetadata("/metadata/assets", destination, "new index");
    await setImmediate();
    assert.deepEqual(writes, []);
    assert.deepEqual(publications, []);
    child.emit("close", 0, null);
    await Promise.all([writer, publish]);
    assert.equal(writes.length, 1);
    assert.ok(writes[0].startsWith(`${destination}.`));
    assert.ok(writes[0].endsWith(".tmp"));
    assert.deepEqual(publications, [destination]);
});

test("metadata failure releases the assets writer slot", { timeout: 5000 }, async (t) => {
    mockDirectories(t);
    t.mock.method(fs, "writeFile", async () => {
        throw new Error("metadata write failure");
    });
    t.mock.method(fs, "rm", async () => undefined);
    await assert.rejects(publishContentMetadata("/metadata-failure/assets", "/metadata-failure/assets/versions.gz", "index"), /metadata write failure/);
    assert.equal(await withContentWrite("/metadata-failure/assets", () => "released"), "released");
});

test("real directory aliases canonicalize identically and metadata publishes on disk", { timeout: 5000 }, async () => {
    const temporaryRoot = await fs.mkdtemp(path.join(os.tmpdir(), "bar-content-writer-cpu-"));
    try {
        const assets = path.join(temporaryRoot, "assets");
        const alias = path.join(temporaryRoot, "alias");
        await fs.mkdir(assets);
        await fs.symlink(assets, alias, "dir");
        const canonical = await withContentWrite(assets, (directory) => directory);
        assert.equal(await withContentWrite(alias, (directory) => directory), canonical);
        const destination = path.join(alias, "rapid", "versions.gz");
        await publishContentMetadata(alias, destination, "first index");
        await publishContentMetadata(assets, destination, "replacement index");
        assert.equal(await fs.readFile(destination, "utf8"), "replacement index");
        assert.deepEqual(await fs.readdir(path.dirname(destination)), ["versions.gz"]);
    } finally {
        await fs.rm(temporaryRoot, { recursive: true, force: true });
    }
});

// This must remain last: shutdown is irreversible, including after a deadline
// failure. No production reset hook or second coordinator instance is used.
test("shutdown closes admission races and reports a bounded failure without releasing unclosed owners", { timeout: 5000 }, async (t) => {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    // Node 22 patches the timers object; refresh the coordinator's named ESM
    // timer bindings too, so this test never waits on the real shutdown clock.
    syncBuiltinESMExports();
    const mkdirEntered = deferred();
    const releaseMkdir = deferred();
    const realpathEntered = deferred();
    const releaseRealpath = deferred();
    const registerLate = deferred();
    const lateRegistered = deferred();
    const inflight: Promise<unknown>[] = [];
    const observe = <T>(promise: Promise<T>) => {
        inflight.push(promise);
        void promise.catch(() => undefined);
        return promise;
    };
    let directoryCalls = 0;
    let publications = 0;
    const enteredWrites: string[] = [];
    t.mock.method(fs, "mkdir", async (directory: string) => {
        directoryCalls++;
        if (directory === "/shutdown/mkdir-race") {
            mkdirEntered.resolve();
            await releaseMkdir.promise;
        }
    });
    t.mock.method(fs, "realpath", async (directory: string) => {
        if (directory === "/shutdown/realpath-race") {
            realpathEntered.resolve();
            await releaseRealpath.promise;
        }
        return directory;
    });
    t.mock.method(fs, "writeFile", async () => { publications++; });
    t.mock.method(fs, "rename", async () => { publications++; });

    const processError = new Error("signal error without close");
    const owners = ["false", "error", "exited", "late"].map((name) => {
        const signals: NodeJS.Signals[] = [];
        const started = deferred();
        const emitter = new EventEmitter();
        const child = Object.assign(emitter, {
            exitCode: null as number | null,
            signalCode: null as NodeJS.Signals | null,
            killed: false,
            kill(signal: NodeJS.Signals) {
                signals.push(signal);
                if (name === "false") return false;
                this.killed = true;
                if (name === "error") emitter.emit("error", processError);
                return true;
            },
        });
        let settled = false;
        const promise = observe(withContentWrite(`/shutdown/${name}`, async () => {
            started.resolve();
            if (name === "late") await registerLate.promise;
            const closed = waitForContentWriterClose(child as unknown as ChildProcess);
            if (name === "late") lateRegistered.resolve();
            return closed;
        }));
        void promise.then(() => { settled = true; }, () => { settled = true; });
        return { name, child, signals, started, promise, settled: () => settled };
    });
    t.after(async () => {
        releaseMkdir.resolve();
        releaseRealpath.resolve();
        registerLate.resolve();
        await setImmediate();
        for (const owner of owners) owner.child.emit("close", 0, null);
        await Promise.allSettled(inflight);
        t.mock.timers.reset();
        syncBuiltinESMExports();
    });
    await Promise.all(owners.map((owner) => owner.started.promise));
    const queued = observe(withContentWrite("/shutdown/false", () => { enteredWrites.push("queued"); }));
    const metadata = observe(publishContentMetadata("/shutdown/false", "/shutdown/false/versions.gz", "index"));
    const mkdirRace = observe(withContentWrite("/shutdown/mkdir-race", () => { enteredWrites.push("mkdir-race"); }));
    const realpathRace = observe(withContentWrite("/shutdown/realpath-race", () => { enteredWrites.push("realpath-race"); }));
    await Promise.all([mkdirEntered.promise, realpathEntered.promise]);
    await setImmediate();
    const exited = owners.find((owner) => owner.name === "exited")!;
    exited.child.exitCode = 0;
    exited.child.emit("exit", 0, null);
    t.mock.timers.tick(2_000);
    assert.ok(owners.every((owner) => owner.signals.length === 0), "active downloads are not subject to the shutdown grace timer");

    const shutdown = shutdownContentWriters();
    const failedShutdown = assert.rejects(shutdown, /Owned content writers did not close within the launcher shutdown deadline/);
    assert.equal(shutdownContentWriters(), shutdown, "simultaneous quit calls share one Promise");
    let shutdownSettled = false;
    void shutdown.then(() => { shutdownSettled = true; }, () => { shutdownSettled = true; });
    const live = owners.filter((owner) => owner.name === "false" || owner.name === "error");
    for (const owner of live) assert.deepEqual(owner.signals, ["SIGTERM"]);
    assert.equal(live.find((owner) => owner.name === "error")!.child.killed, true);
    assert.deepEqual(exited.signals, [], "an exited child still owes close but must not be signalled again");

    const callsAtShutdown = directoryCalls;
    await assert.rejects(withContentWrite("/shutdown/new", () => { enteredWrites.push("new"); }), /Content writes stopped because the launcher is quitting/);
    assert.equal(directoryCalls, callsAtShutdown, "the quit latch rejects before directory I/O");
    releaseMkdir.resolve();
    releaseRealpath.resolve();
    await Promise.all([
        assert.rejects(mkdirRace, /Content writes stopped because the launcher is quitting/),
        assert.rejects(realpathRace, /Content writes stopped because the launcher is quitting/),
    ]);
    registerLate.resolve();
    await lateRegistered.promise;
    const late = owners.find((owner) => owner.name === "late")!;
    assert.deepEqual(late.signals, ["SIGKILL"], "a late child of an already-owned writer is stopped immediately");
    t.mock.timers.tick(1_999);
    assert.equal(shutdownSettled, false);
    for (const owner of live) assert.deepEqual(owner.signals, ["SIGTERM"]);
    t.mock.timers.tick(1);
    for (const owner of live) assert.deepEqual(owner.signals, ["SIGTERM", "SIGKILL"], "false/error or killed=true cannot suppress the KILL attempt");
    t.mock.timers.tick(2_999);
    await setImmediate();
    assert.equal(shutdownSettled, false, "close/drain is still pending before the five-second deadline");
    assert.ok(owners.every((owner) => !owner.settled()), "neither false, error, exit nor a signal releases child ownership");
    assert.deepEqual(enteredWrites, []);
    assert.equal(publications, 0);
    t.mock.timers.tick(1);
    await failedShutdown;
    assert.equal(shutdownSettled, true);
    assert.ok(owners.every((owner) => !owner.settled()), "deadline failure preserves every unclosed writer");
    assert.equal(shutdownContentWriters(), shutdown, "deadline failure does not create a fresh shutdown attempt");
    await assert.rejects(withContentWrite("/shutdown/after-deadline", () => { enteredWrites.push("after-deadline"); }), /Content writes stopped because the launcher is quitting/);
    assert.deepEqual(enteredWrites, []);
    assert.equal(publications, 0);

    for (const owner of owners) {
        assert.equal(owner.settled(), false, `${owner.name} must still wait for its own close`);
        owner.child.emit("close", owner.name === "error" ? -2 : 0, null);
        if (owner.name === "error") await assert.rejects(owner.promise, (actual) => actual === processError);
        else await owner.promise;
        assert.equal(owner.settled(), true);
        if (owner.name === "false") {
            await Promise.all([
                assert.rejects(queued, /Content writes stopped because the launcher is quitting/),
                assert.rejects(metadata, /Content writes stopped because the launcher is quitting/),
            ]);
        }
    }
    assert.deepEqual(enteredWrites, [], "releasing old ownership never reopens admission");
    assert.equal(publications, 0);
    await assert.rejects(shutdownContentWriters(), /Owned content writers did not close within the launcher shutdown deadline/);
});
