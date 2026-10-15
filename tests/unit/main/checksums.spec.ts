// SPDX-License-Identifier: MIT
import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ spawn: vi.fn(), runner: vi.fn(), env: vi.fn(), warn: vi.fn() }));
vi.mock("child_process", () => ({ spawn: mocks.spawn }));
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
    let child: EventEmitter;
    beforeEach(() => {
        vi.resetModules();
        vi.clearAllMocks();
        vi.stubGlobal("process", Object.create(process, { platform: { value: "darwin" } }));
        child = new EventEmitter();
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
        child.emit("exit", 0);
        await done;
    });

    it("does not substitute another engine or poison the queue when the requested version is missing", async () => {
        const { calcChecksum } = await import("@main/utils/checksums");
        mocks.runner.mockImplementationOnce(() => { throw new Error("requested version unavailable"); });
        await calcChecksum("missing", "first game");
        expect(mocks.spawn).not.toHaveBeenCalled();
        const done = calcChecksum("2026.06.08", "second game");
        await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
        child.emit("exit", 0);
        await done;
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
