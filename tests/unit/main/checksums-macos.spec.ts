// SPDX-License-Identifier: MIT
import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ spawn: vi.fn(), runner: vi.fn(), env: vi.fn(), warn: vi.fn() }));
vi.mock("child_process", () => ({ spawn: mocks.spawn }));
vi.mock("node:fs/promises", () => ({ default: { mkdir: async () => undefined, realpath: async (p: string) => p } }));
vi.mock("@main/utils/logger", () => ({ logger: () => ({ debug: vi.fn(), warn: mocks.warn }) }));
vi.mock("@main/config/app", () => ({
    getEnginePath: () => "/assets/engine",
    getAssetsPath: () => "/assets",
    WRITE_DATA_PATH: "/state/data",
    BUNDLED_ASSETS_PATH: "/BAR.app/bundled-assets",
}));
vi.mock("@main/config/native-engine-runner", () => ({
    resolveNativeEngineRunner: mocks.runner,
    getNativeEngineProcessEnv: mocks.env,
}));

describe("archive checksum subprocess", () => {
    let child: EventEmitter & { exitCode: number | null; signalCode: string | null; kill: ReturnType<typeof vi.fn> };
    beforeEach(() => {
        vi.resetModules();
        vi.clearAllMocks();
        vi.stubGlobal("process", Object.create(process, { platform: { value: "darwin" } }));
        child = Object.assign(new EventEmitter(), { exitCode: null, signalCode: null, kill: vi.fn(() => true) });
        mocks.spawn.mockReturnValue(child);
        mocks.runner.mockReturnValue({ enginePath: "/BAR.app/bundled-assets/engine/requested", spawnCommand: "./spring" });
        mocks.env.mockReturnValue({ SPRING_DATADIR: "/assets:/engine", DYLD_LIBRARY_PATH: "/BAR.app/runtime" });
    });
    afterEach(() => vi.unstubAllGlobals());

    it("uses the exact requested native engine and its bundle runtime without a content overlay", async () => {
        const { calcChecksum } = await import("@main/utils/checksums");
        const done = calcChecksum("2026.06.08", "official game");
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
        expect(mocks.runner).toHaveBeenCalledWith(expect.objectContaining({ engineVersion: "2026.06.08" }));
        expect(mocks.env).toHaveBeenCalledWith(expect.objectContaining({
            includeBundledAssetsInSpringDataDir: false,
            includeBundledMacOSLuaUIOverlayInSpringDataDir: false,
        }));
        expect(mocks.spawn).toHaveBeenCalledWith("./spring", ["--write-dir", "/state/data", "--isolation", "--calc-checksum", "official game"], {
            cwd: "/BAR.app/bundled-assets/engine/requested",
            stdio: "ignore",
            env: { SPRING_DATADIR: "/assets:/engine", DYLD_LIBRARY_PATH: "/BAR.app/runtime" },
        });
        child.emit("close", 0, null);
        await done;
    });

    it("does not substitute another engine or poison the queue when the requested version is missing", async () => {
        const { calcChecksum } = await import("@main/utils/checksums");
        mocks.runner.mockImplementationOnce(() => { throw new Error("requested version unavailable"); });
        await calcChecksum("missing", "first game");
        expect(mocks.spawn).not.toHaveBeenCalled();
        const done = calcChecksum("2026.06.08", "second game");
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
        child.emit("close", 0, null);
        await done;
    });

    it("waits for checksum close and holds later checksums until the native owner releases", async () => {
        const { calcChecksum, acquireChecksumHold } = await import("@main/utils/checksums");
        const first = calcChecksum("version", "first");
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
        const granted = vi.fn();
        const hold = acquireChecksumHold().then((release) => { granted(); return release; });
        const second = calcChecksum("version", "second");
        child.emit("exit", 0);
        await new Promise((resolve) => setTimeout(resolve, 0));
        expect(granted).not.toHaveBeenCalled();
        child.emit("close", 0, null);
        await first;
        const release = await hold;
        await new Promise((resolve) => setTimeout(resolve, 0));
        expect(mocks.spawn).toHaveBeenCalledOnce();
        release();
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledTimes(2));
        child.emit("close", 0, null);
        await second;
    });

    it("drains the owned checksum on ordinary shutdown and cancels its queued successor", async () => {
        const { calcChecksum } = await import("@main/utils/checksums");
        const { shutdownContentWriters } = await import("@main/content/content-write-coordinator");
        const first = calcChecksum("version", "first");
        const second = calcChecksum("version", "second");
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
        const drained = vi.fn();
        const shutdown = shutdownContentWriters().then(drained);
        expect(child.kill).toHaveBeenCalledWith("SIGTERM");
        child.emit("exit", 0);
        await new Promise((resolve) => setTimeout(resolve, 0));
        expect(drained).not.toHaveBeenCalled();
        child.emit("close", 0, null);
        await Promise.all([first, second, shutdown]);
        expect(drained).toHaveBeenCalledOnce();
        expect(mocks.spawn).toHaveBeenCalledOnce();
    });

    it("does not release checksum ownership on an error before close", async () => {
        const { calcChecksum, acquireChecksumHold } = await import("@main/utils/checksums");
        const first = calcChecksum("version", "first");
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
        const granted = vi.fn();
        const hold = acquireChecksumHold().then((release) => { granted(); return release; });
        child.emit("error", new Error("spawn error"));
        await new Promise((resolve) => setTimeout(resolve, 0));
        expect(granted).not.toHaveBeenCalled();
        child.emit("close", -1, null);
        await first;
        (await hold)();
        expect(mocks.warn).toHaveBeenCalledWith(expect.stringContaining("spawn error"));
    });

    it("keeps the existing headless executable on Windows", async () => {
        vi.stubGlobal("process", Object.create(process, { platform: { value: "win32" } }));
        const { calcChecksum } = await import("@main/utils/checksums");
        const done = calcChecksum("version", "game");
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
        expect(mocks.spawn.mock.calls[0][0]).toBe("spring-headless.exe");
        expect(mocks.runner).not.toHaveBeenCalled();
        child.emit("exit", 0);
        await done;
    });
});
