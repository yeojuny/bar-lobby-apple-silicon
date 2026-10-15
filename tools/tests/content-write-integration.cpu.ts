// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

// Run with: node --import=tsx --test tools/tests/content-write-integration.cpu.ts
// Set BAR_CONTENT_WRITER_APP to the pinned candidate to test its packaged code.
// Only the three writer methods are loaded from current product source. Their
// imports, constructors, other methods, and application entry points never run.
import assert from "node:assert/strict";
import type { ChildProcess } from "node:child_process";
import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";
import { closeSync, openSync, readFileSync, readSync } from "node:fs";
import fs from "node:fs/promises";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { after, test, type TestContext } from "node:test";
import { setImmediate } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import vm from "node:vm";
import zlib from "node:zlib";
import ts from "typescript";

type Coordinator = typeof import("../../src/main/content/content-write-coordinator.ts");
const expectedPackagedMainSha256 = "86025ecbbab712a02c7c02bb98ee9bc79170f96e81c9cb875eafb94afc55bade";
const hashBytes = (value: string | Uint8Array) => createHash("sha256").update(value).digest("hex");

function loadPackagedInputs(candidateApp: string) {
    const app = path.resolve(candidateApp);
    const archive = path.join(app, "Contents", "Resources", "app.asar");
    const fd = openSync(archive, "r");
    try {
        const readAt = (position: number, length: number) => {
            assert.ok(Number.isSafeInteger(position) && position >= 0);
            assert.ok(Number.isSafeInteger(length) && length >= 0 && length <= 32 * 1024 * 1024);
            const buffer = Buffer.alloc(length);
            let offset = 0;
            while (offset < length) {
                const count = readSync(fd, buffer, offset, length - offset, position + offset);
                assert.ok(count > 0, "Unexpected end of ASAR");
                offset += count;
            }
            return buffer;
        };
        const prefix = readAt(0, 16);
        const header = JSON.parse(readAt(16, prefix.readUInt32LE(12)).toString("utf8"));
        const payloadStart = 8 + prefix.readUInt32LE(4);
        const entry = (name: string) => {
            let metadata = header;
            for (const component of name.split("/")) metadata = metadata.files?.[component];
            assert.ok(metadata && !metadata.unpacked && !metadata.link, `Expected packed ASAR file: ${name}`);
            const bytes = readAt(payloadStart + Number(metadata.offset), metadata.size);
            const digest = hashBytes(bytes);
            if (metadata.integrity) {
                assert.equal(metadata.integrity.algorithm, "SHA256");
                assert.equal(digest, metadata.integrity.hash, `ASAR entry integrity mismatch: ${name}`);
            }
            return { text: bytes.toString("utf8"), sha256: digest };
        };
        const mainEntry = ".vite/build/main.cjs";
        const helperEntry = ".vite/build/content-write-coordinator.cjs";
        const main = entry(mainEntry);
        assert.equal(main.sha256, expectedPackagedMainSha256, "Candidate main bundle differs from the authorized pin");
        const helper = entry(helperEntry);
        return { app, archive, mainEntry, helperEntry, main, helper, parsed: ts.createSourceFile(mainEntry, main.text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS) };
    } finally {
        closeSync(fd);
    }
}

const packagedInputs = process.env.BAR_CONTENT_WRITER_APP ? loadPackagedInputs(process.env.BAR_CONTENT_WRITER_APP) : undefined;
let packagedHelperLoads = 0;

function loadPackagedCoordinator(inputs: NonNullable<typeof packagedInputs>): Coordinator {
    const nodeRequire = createRequire(import.meta.url);
    const allowed = new Set(["node:crypto", "crypto", "node:fs/promises", "fs/promises", "node:path", "path"]);
    const requireBuiltin = (id: string) => {
        assert.ok(allowed.has(id), `Unexpected packaged-helper dependency: ${id}`);
        return nodeRequire(id);
    };
    const module = { exports: {} as Record<string, unknown> };
    const filename = `${inputs.archive}#${inputs.helperEntry}`;
    const wrapper = new vm.Script(`(function(exports, require, module, __filename, __dirname) {\n${inputs.helper.text}\n})`, { filename }).runInNewContext({ Buffer });
    packagedHelperLoads++;
    wrapper(module.exports, requireBuiltin, module, filename, path.dirname(filename));
    for (const name of ["withContentWrite", "waitForContentWriterClose", "publishContentMetadata"]) {
        assert.equal(typeof module.exports[name], "function", `Missing packaged helper export: ${name}`);
    }
    return module.exports as Coordinator;
}

// Exactly one helper module instance per run. Packaged mode never imports the
// source coordinator and never executes the candidate's main module.
const coordinator: Coordinator = packagedInputs ? loadPackagedCoordinator(packagedInputs) : await import("../../src/main/content/content-write-coordinator.ts");
const { publishContentMetadata, waitForContentWriterClose, withContentWrite } = coordinator;
const fixtureHelpers: Array<Pick<Coordinator, "withContentWrite" | "waitForContentWriterClose" | "publishContentMetadata">> = [];

const sourceRoot = fileURLToPath(new URL("../../src/main/", import.meta.url));
const sourceEvidence: Array<{ file: string; method: string; fileSha256: string; methodSha256: string }> = [];
const sha256 = (value: string) => createHash("sha256").update(value).digest("hex");

function loadMethod(relativeFile: string, className: string, methodName: string) {
    const packagedClassNames: Record<string, string> = { PrDownloaderAPI: "dA", GameContentAPI: "bU", GameAPI: "$U" };
    const targetClass = packagedInputs ? packagedClassNames[className] : className;
    assert.ok(targetClass, `No fixed class target for ${className}`);
    const filename = packagedInputs ? `${packagedInputs.archive}#${packagedInputs.mainEntry}` : path.join(sourceRoot, relativeFile);
    const source = packagedInputs ? packagedInputs.main.text : readFileSync(filename, "utf8");
    const parsed = packagedInputs?.parsed ?? ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
    const declarations = new Set<ts.ClassDeclaration | ts.ClassExpression>();
    const visit = (node: ts.Node) => {
        if ((ts.isClassDeclaration(node) || ts.isClassExpression(node)) && node.name?.text === targetClass) declarations.add(node);
        if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.name.text === targetClass && node.initializer && ts.isClassExpression(node.initializer)) declarations.add(node.initializer);
        ts.forEachChild(node, visit);
    };
    visit(parsed);
    assert.equal(declarations.size, 1, `Expected exactly one fixed class target ${targetClass}`);
    const declaration = [...declarations][0];
    const method = declaration.members.find((member): member is ts.MethodDeclaration => ts.isMethodDeclaration(member) && ts.isIdentifier(member.name) && member.name.text === methodName);
    assert.ok(method?.body, `Missing implementation ${className}.${methodName}`);
    const printer = ts.createPrinter();
    const methodText = printer.printNode(ts.EmitHint.Unspecified, method, parsed);
    // Preserve the complete original method body, including its Promise chains.
    const isolatedClass = ts.factory.createClassDeclaration(undefined, "WriterUnderTest", undefined, undefined, [method]);
    const isolatedSource = printer.printNode(ts.EmitHint.Unspecified, isolatedClass, parsed);
    const compiled = packagedInputs ? { outputText: isolatedSource, diagnostics: [] as ts.Diagnostic[] } : ts.transpileModule(isolatedSource, {
        fileName: filename,
        compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None },
        reportDiagnostics: true,
    });
    const errors = compiled.diagnostics?.filter((diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error) ?? [];
    assert.deepEqual(errors.map((error) => ts.flattenDiagnosticMessageText(error.messageText, "\n")), []);
    sourceEvidence.push({ file: filename, method: `${targetClass}.${methodName}`, fileSha256: sha256(source), methodSha256: sha256(methodText) });
    const script = new vm.Script(`${compiled.outputText}\nWriterUnderTest;`, { filename: `${filename}#${methodName}` });
    return (bindings: Record<string, unknown>) => {
        const Constructor = script.runInNewContext({ ...bindings }) as new () => Record<string, (...args: any[]) => Promise<any>>;
        return new Constructor();
    };
}

const createOrdinaryWriter = loadMethod("content/pr-downloader.ts", "PrDownloaderAPI", "downloadContent");
const createChobbyWriter = loadMethod("game/game.ts", "GameAPI", "ensureChobbyMenuArchive");
const createMetadataWriter = loadMethod("content/game/game-content.ts", "GameContentAPI", "refreshRapidLookupTablesFromRemote");

function deferred() {
    let resolve!: () => void;
    const promise = new Promise<void>((done) => { resolve = done; });
    return { promise, resolve };
}

class FakeChild extends EventEmitter {
    stdout = new EventEmitter();
    stderr = new EventEmitter();
    closed = false;

    close(code: number | null = 0, signal: NodeJS.Signals | null = null) {
        if (this.closed) return;
        this.closed = true;
        this.emit("close", code, signal);
    }
}

function observed<T>(promise: Promise<T>): Promise<T> {
    // Preserve the original outcome while preventing an expected rejection from
    // becoming unhandled before the test reaches its settlement assertion.
    void promise.catch(() => undefined);
    return promise;
}

async function fixture(t: TestContext) {
    const assets = await fs.mkdtemp(path.join(os.tmpdir(), "bar-content-integration-cpu-"));
    const canonicalAssets = await fs.realpath(assets);
    const children: FakeChild[] = [];
    const calls: Array<{ command: string; args: string[] }> = [];
    const cleanupReleases: Array<() => void> = [];
    t.after(async () => {
        for (const release of cleanupReleases) release();
        // Register before wrapper construction, so setup failures clean up too.
        // Fake children have no OS processes or I/O handles.
        for (let i = 0; i < 3; i++) {
            for (const child of children) child.close(1);
            await setImmediate();
        }
        await fs.rm(assets, { recursive: true, force: true });
    });
    let normalizations = 0;
    const normalizationWaiters: Array<{ count: number; resolve: () => void }> = [];
    const spawnWaiters: Array<{ count: number; resolve: () => void }> = [];
    const originalRealpath = fs.realpath.bind(fs);
    // Observe real canonicalization without changing its result. Waiting for this
    // checkpoint plus a microtask drain proves a contender has reached the queue;
    // no sleep duration or filesystem-speed assumption is used.
    t.mock.method(fs, "realpath", async (filename: string) => {
        const result = await originalRealpath(filename);
        if (path.resolve(filename) === path.resolve(assets)) {
            normalizations++;
            for (const waiter of normalizationWaiters) if (normalizations >= waiter.count) waiter.resolve();
        }
        return result;
    });

    const faults: { failedListener?: Error; errorLogger?: Error; completionLogger?: Error } = {};
    let failedNotifications = 0;
    const logs: Array<{ level: string; message: unknown }> = [];
    const log = {
        debug: (message: unknown) => logs.push({ level: "debug", message }),
        info: (message: unknown) => {
            if (faults.completionLogger && String(message).startsWith("[CHOBBY PR-DOWNLOADER] [Progress]")) throw faults.completionLogger;
            logs.push({ level: "info", message });
        },
        error: (message: unknown) => {
            if (faults.errorLogger) throw faults.errorLogger;
            logs.push({ level: "error", message });
        },
        warn: (message: unknown) => logs.push({ level: "warn", message }),
    };
    const versionText = "byar:test,0123456789abcdef0123456789abcdef,,CPU test version\n";
    const metadataBytes = zlib.gzipSync(versionText);
    let fakeHttpRequests = 0;
    const bindings = {
        Buffer, Error, Date, log, os: { EOL: "\n" }, path,
        process: { platform: "darwin", env: {} },
        fs: { promises: fs },
        BUNDLED_ASSETS_PATH: undefined,
        DEFAULT_CHOBBY_MENU: "rapid://byar-chobby:test",
        DEFAULT_CHOBBY_RAPID_TAG: "byar-chobby:test",
        getAssetsPath: () => assets,
        getCaCertPath: () => undefined,
        getRapidIndexPath: () => path.join(assets, "rapid"),
        contentSources: { rapid: { host: "offline.invalid", game: "byar" } },
        engineContentAPI: { getDefaultEngine: () => ({ id: "ordinary-cpu-stub", installed: true }) },
        resolvePrDownloaderPath: ({ engineVersion }: { engineVersion: string }) => `/never-executed/${engineVersion}/pr-downloader`,
        withContentWrite, waitForContentWriterClose, publishContentMetadata,
        gunzip: promisify(zlib.gunzip),
        axios: async () => { fakeHttpRequests++; return { data: metadataBytes }; },
        spawn: (command: string, args: string[]) => {
            assert.equal(children.filter((child) => !child.closed).length, 0, "ordinary and Chobby writers overlapped");
            assert.equal(args[0], "--filesystem-writepath");
            assert.equal(args[1], canonicalAssets);
            const child = new FakeChild();
            calls.push({ command, args: Array.from(args) });
            children.push(child);
            for (const waiter of spawnWaiters) if (children.length >= waiter.count) waiter.resolve();
            return child as unknown as ChildProcess;
        },
    };
    const methodBindings = packagedInputs ? {
        ...bindings,
        __barWithContentWrite: withContentWrite,
        __barWaitForContentWriterClose: waitForContentWriterClose,
        __barPublishContentMetadata: publishContentMetadata,
        jr: bindings.getAssetsPath,
        Dv: bindings.getCaCertPath,
        ys: bindings.BUNDLED_ASSETS_PATH,
        qv: bindings.resolvePrDownloaderPath,
        _s: { spawn: bindings.spawn },
        Me: bindings.fs,
        xe: path,
        Nl: log,
        lt: bindings.engineContentAPI,
        vs: bindings.os,
        Rt: log,
        Fn: bindings.contentSources,
        Ar: bindings.axios,
        lu: bindings.gunzip,
        Su: bindings.getRapidIndexPath,
        er: log,
        Rl: bindings.DEFAULT_CHOBBY_MENU,
        u5: bindings.DEFAULT_CHOBBY_RAPID_TAG,
    } : bindings;
    fixtureHelpers.push({ withContentWrite, waitForContentWriterClose, publishContentMetadata });
    const ordinary = createOrdinaryWriter(methodBindings);
    Object.assign(ordinary, {
        currentDownloads: [],
        downloadStarted: () => undefined,
        downloadProgress: () => undefined,
        downloadRetrying: () => undefined,
        downloadFailed: () => {
            failedNotifications++;
            if (faults.failedListener) throw faults.failedListener;
        },
    });
    const chobby = createChobbyWriter(methodBindings);
    const metadata = createMetadataWriter(methodBindings);
    const indexed: string[] = [];
    Object.assign(metadata, { indexRapidVersions: (text: string) => indexed.push(text) });
    const metadataPath = path.join(assets, "rapid", "offline.invalid", "byar", "versions.gz");

    return {
        assets, canonicalAssets, children, calls, faults, logs, indexed, metadataPath, metadataBytes, cleanupReleases,
        ordinary: () => observed(ordinary.downloadContent("game", "byar:test")),
        chobby: () => observed(chobby.ensureChobbyMenuArchive({ engineVersion: "chobby-cpu-stub" })),
        metadata: () => observed(metadata.refreshRapidLookupTablesFromRemote()),
        failedNotifications: () => failedNotifications,
        fakeHttpRequests: () => fakeHttpRequests,
        async admitted(count: number) {
            if (normalizations < count) await new Promise<void>((resolve) => normalizationWaiters.push({ count, resolve }));
            await setImmediate();
        },
        async spawned(count: number) {
            if (children.length < count) await new Promise<void>((resolve) => spawnWaiters.push({ count, resolve }));
            await setImmediate();
        },
    };
}

test("actual ordinary and Chobby wrappers share exclusion until close, not exit", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const ordinary = f.ordinary();
    await f.spawned(1);
    const chobby = f.chobby();
    await f.admitted(2);
    assert.equal(f.children.length, 1);
    f.children[0].emit("exit", 0, null);
    await setImmediate();
    assert.equal(f.children.length, 1);
    f.children[0].close();
    await f.spawned(2);
    f.children[1].close();
    const result = await ordinary;
    await chobby;
    assert.equal(result.name, "byar:test");
    assert.equal(f.calls[0].args[3], "byar:test");
    assert.equal(f.calls[1].args[3], "byar-chobby:test");
});

test("actual Chobby error does not release before close and settles its outer Promise", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const chobby = f.chobby();
    await f.spawned(1);
    const ordinary = f.ordinary();
    await f.admitted(2);
    const error = new Error("simulated Chobby spawn failure");
    f.children[0].emit("error", error);
    await setImmediate();
    assert.equal(f.children.length, 1);
    f.children[0].close(-2);
    await assert.rejects(chobby, (actual) => actual === error);
    await f.spawned(2);
    f.children[1].close();
    await ordinary;
});

test("ordinary failure-listener exception is forwarded by catch and frees the queue", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const error = new Error("downloadFailed listener threw");
    f.faults.failedListener = error;
    const ordinary = f.ordinary();
    await f.spawned(1);
    const chobby = f.chobby();
    await f.admitted(2);
    f.children[0].close(1);
    await assert.rejects(ordinary, (actual) => actual === error);
    assert.equal(f.failedNotifications(), 1);
    await f.spawned(2);
    f.children[1].close();
    await chobby;
});

test("ordinary child-error logger exception settles after close and cannot strand the queue", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const error = new Error("error logger threw");
    f.faults.errorLogger = error;
    const ordinary = f.ordinary();
    await f.spawned(1);
    const chobby = f.chobby();
    await f.admitted(2);
    f.children[0].emit("error", new Error("simulated child failure"));
    await setImmediate();
    assert.equal(f.children.length, 1);
    f.children[0].close(-2);
    await assert.rejects(ordinary, (actual) => actual === error);
    await f.spawned(2);
    f.children[1].close();
    await chobby;
});

test("Chobby completion-logger exception is forwarded by catch and frees the queue", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const chobby = f.chobby();
    await f.spawned(1);
    f.children[0].stdout.emit("data", Buffer.from("[Progress] CPU completion marker\n"));
    const error = new Error("completion logger threw");
    f.faults.completionLogger = error;
    const ordinary = f.ordinary();
    await f.admitted(2);
    f.children[0].close();
    await assert.rejects(chobby, (actual) => actual === error);
    await f.spawned(2);
    f.children[1].close();
    await ordinary;
});

test("Chobby nonzero close rejects the outer Promise and admits the next writer", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const chobby = f.chobby();
    await f.spawned(1);
    const ordinary = f.ordinary();
    await f.admitted(2);
    f.children[0].close(7);
    await assert.rejects(chobby, /Chobby archive download failed with code 7/);
    await f.spawned(2);
    f.children[1].close();
    await ordinary;
});

test("actual metadata refresh publishes between queued ordinary and Chobby writers", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const ordinary = f.ordinary();
    await f.spawned(1);
    const metadata = f.metadata();
    await f.admitted(2);
    const chobby = f.chobby();
    await f.admitted(3);
    assert.equal(f.fakeHttpRequests(), 1);
    assert.equal(f.children.length, 1);
    await assert.rejects(fs.access(f.metadataPath), { code: "ENOENT" });
    f.children[0].close();
    await f.spawned(2);
    assert.deepEqual(await fs.readFile(f.metadataPath), f.metadataBytes);
    assert.equal(f.indexed.length, 1);
    f.children[1].close();
    await Promise.all([ordinary, metadata, chobby]);
});

test("actual metadata publication holds exclusion while an ordinary download is queued", { timeout: 5000 }, async (t) => {
    const f = await fixture(t);
    const publicationStarted = deferred();
    const releasePublication = deferred();
    f.cleanupReleases.push(releasePublication.resolve);
    const writeFile = fs.writeFile.bind(fs);
    t.mock.method(fs, "writeFile", async (filename: string, contents: Uint8Array, options: { flag: string }) => {
        if (filename.startsWith(`${f.metadataPath}.`)) {
            publicationStarted.resolve();
            await releasePublication.promise;
        }
        return writeFile(filename, contents, options);
    });
    const metadata = f.metadata();
    await publicationStarted.promise;
    const ordinary = f.ordinary();
    await f.admitted(2);
    assert.equal(f.children.length, 0);
    releasePublication.resolve();
    await f.spawned(1);
    assert.deepEqual(await fs.readFile(f.metadataPath), f.metadataBytes);
    f.children[0].close();
    await Promise.all([metadata, ordinary]);
});

if (packagedInputs) {
    test("packaged helper module is loaded once and shared by all eight fixtures", () => {
        assert.equal(packagedHelperLoads, 1);
        assert.equal(fixtureHelpers.length, 8);
        for (const helpers of fixtureHelpers) {
            assert.equal(helpers.withContentWrite, coordinator.withContentWrite);
            assert.equal(helpers.waitForContentWriterClose, coordinator.waitForContentWriterClose);
            assert.equal(helpers.publishContentMetadata, coordinator.publishContentMetadata);
        }
    });
}

after(() => {
    // Small provenance output for the separate evidence receipt, never source text.
    console.log(`CONTENT_WRITER_INTEGRATION_SOURCES ${JSON.stringify(sourceEvidence)}`);
    if (packagedInputs) console.log(`CONTENT_WRITER_PACKAGED_ARTIFACT ${JSON.stringify({ candidateApp: packagedInputs.app, archive: packagedInputs.archive, mainEntry: packagedInputs.mainEntry, mainSha256: packagedInputs.main.sha256, helperEntry: packagedInputs.helperEntry, helperSha256: packagedInputs.helper.sha256, helperModuleLoads: packagedHelperLoads, fixtureCount: fixtureHelpers.length })}`);
});
