// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import assert from "node:assert/strict";
import type { ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { setImmediate } from "node:timers/promises";
import test, { type TestContext } from "node:test";
import { publishContentMetadata, waitForContentWriterClose, withContentWrite } from "../../src/main/content/content-write-coordinator.ts";

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
// turn. The final test separately exercises real canonicalization/publication.
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
