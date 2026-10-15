// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
// SPDX-License-Identifier: MIT

import { beforeEach, describe, expect, it, vi } from "vitest";
import electronUpdater from "electron-updater";
import { getAutoUpdaterInitializationSkipReason } from "@main/config/auto-updater";
import { AutoUpdaterAPI } from "@main/content/auto-updater";
import type { DownloadInfo } from "@main/content/downloads";

const { log } = vi.hoisted(() => ({ log: { info: vi.fn(), error: vi.fn() } }));
vi.mock("@main/utils/logger", () => ({ logger: () => log }));
vi.mock("@main/config/auto-updater", () => ({ getAutoUpdaterInitializationSkipReason: vi.fn() }));
vi.mock("electron", () => ({ app: { isPackaged: true } }));
vi.mock("electron-updater", async () => {
    const { EventEmitter } = await import("node:events");
    return { default: { autoUpdater: Object.assign(new EventEmitter(), {
        currentVersion: { toString: () => "0.15.3" },
        checkForUpdates: vi.fn(), downloadUpdate: vi.fn(), quitAndInstall: vi.fn(),
    }) } };
});

const updater = electronUpdater.autoUpdater;
const info = { version: "0.15.4", files: [], releaseDate: "2026-09-28T00:00:00Z", path: "BAR-0.15.4.zip", sha512: "fixture-not-downloaded" };
const downloadedInfo = { ...info, downloadedFile: "/tmp/BAR-updater-fixture.zip" };
const available = { updateInfo: info, versionInfo: info, isUpdateAvailable: true };
const watchedEvents = ["error", "update-available", "update-not-available", "download-progress", "update-downloaded"] as const;

class RecordingUpdater extends AutoUpdaterAPI {
    readonly progress: DownloadInfo[] = [];
    readonly complete: DownloadInfo[] = [];
    readonly failed: DownloadInfo[] = [];
    protected override async downloadProgress(value: DownloadInfo) { this.progress.push(value); }
    protected override async downloadComplete(value: DownloadInfo) { this.complete.push(value); }
    protected override async downloadFailed(value: DownloadInfo) { this.failed.push(value); }
}

function deferred<T>() {
    let resolve!: (value: T) => void;
    let reject!: (reason: Error) => void;
    const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
    return { promise, resolve, reject };
}

function expectCleanListeners() {
    for (const event of watchedEvents) expect(updater.listenerCount(event)).toBe(0);
}

async function ready() {
    const api = new RecordingUpdater();
    await api.init();
    await api.checkForUpdates();
    return api;
}

beforeEach(() => {
    updater.removeAllListeners();
    vi.clearAllMocks();
    vi.mocked(getAutoUpdaterInitializationSkipReason).mockReset().mockReturnValue(undefined);
    vi.mocked(updater.checkForUpdates).mockReset().mockResolvedValue(available);
    vi.mocked(updater.downloadUpdate).mockReset().mockImplementation(async () => {
        updater.emit("update-downloaded", downloadedInfo);
        return [];
    });
});

describe("updater request lifecycle without a feed or native updater", () => {
    it("uses the actual macOS policy to remain inert even with updater metadata", async () => {
        const actual = await vi.importActual<typeof import("@main/config/auto-updater")>("@main/config/auto-updater");
        const resourcesPath = "/Applications/BAR.app/Contents/Resources";
        vi.mocked(getAutoUpdaterInitializationSkipReason).mockImplementation((runtime) =>
            actual.getAutoUpdaterInitializationSkipReason({
                ...runtime,
                platform: "darwin",
                resourcesPath,
                pathExists: (file) => file === `${resourcesPath}/app-update.yml`,
            })
        );
        updater.autoInstallOnAppQuit = true;
        const api = new RecordingUpdater();
        await api.init();
        expect(updater.autoInstallOnAppQuit).toBe(false);
        expect(await api.checkForUpdates()).toBe(false);
        await api.downloadUpdate();
        api.installUpdates();
        api.quitAndInstall();
        expect(updater.checkForUpdates).not.toHaveBeenCalled();
        expect(updater.downloadUpdate).not.toHaveBeenCalled();
        expect(updater.quitAndInstall).not.toHaveBeenCalled();
        expectCleanListeners();
    });

    it("keeps uninitialized and portable-disabled operations inert", async () => {
        const api = new RecordingUpdater();
        expect(await api.checkForUpdates()).toBe(false);
        await api.downloadUpdate();
        api.installUpdates();
        api.quitAndInstall();
        vi.mocked(getAutoUpdaterInitializationSkipReason).mockReturnValue("macOS portable build detected");
        await api.init();
        expect(await api.checkForUpdates()).toBe(false);
        await api.downloadUpdate();
        api.installUpdates();
        api.quitAndInstall();
        expect(updater.checkForUpdates).not.toHaveBeenCalled();
        expect(updater.downloadUpdate).not.toHaveBeenCalled();
        expect(updater.quitAndInstall).not.toHaveBeenCalled();
        expectCleanListeners();
    });

    it("does not accumulate listeners over repeated checks or remove another owner's listeners", async () => {
        const api = new RecordingUpdater();
        await api.init();
        const other = vi.fn();
        updater.on("error", other);
        for (let i = 0; i < 20; i++) expect(await api.checkForUpdates()).toBe(true);
        expect(updater.listeners("error")).toEqual([other]);
        updater.removeListener("error", other);
        expectCleanListeners();
        expect(api.currentVersion).toBe("0.15.3");
    });

    it("settles unavailable and disabled checks and rejects an unavailable download", async () => {
        const api = await ready();
        vi.mocked(updater.checkForUpdates).mockResolvedValueOnce({ ...available, isUpdateAvailable: false }).mockResolvedValueOnce(null);
        expect(await api.checkForUpdates()).toBe(false);
        await expect(api.downloadUpdate()).rejects.toThrow(/unavailable update/);
        expect(await api.checkForUpdates()).toBe(false);
        expect(api.updateInformation).toBeNull();
        expectCleanListeners();
    });

    it.each(["throw", "reject", "event-and-reject"])("handles check %s once and permits retry", async (mode) => {
        const api = new RecordingUpdater();
        await api.init();
        const error = new Error("check failed");
        vi.mocked(updater.checkForUpdates).mockImplementationOnce(() => {
            if (mode === "throw") throw error;
            if (mode === "event-and-reject") updater.emit("error", error);
            return Promise.reject(error);
        });
        expect(await api.checkForUpdates()).toBe(false);
        expect(log.error).toHaveBeenCalledTimes(1);
        expectCleanListeners();
        expect(await api.checkForUpdates()).toBe(true);
    });

    it("coalesces checks until the underlying promise settles, including after an available event", async () => {
        const api = new RecordingUpdater();
        await api.init();
        const pending = deferred<typeof available>();
        vi.mocked(updater.checkForUpdates).mockReturnValueOnce(pending.promise);
        const first = api.checkForUpdates();
        expect(api.checkForUpdates()).toBe(first);
        await vi.waitFor(() => expect(updater.checkForUpdates).toHaveBeenCalledTimes(1), { interval: 1 });
        updater.emit("update-available", info);
        expect(api.checkForUpdates()).toBe(first);
        pending.resolve(available);
        expect(await first).toBe(true);
        expectCleanListeners();
    });

    it("coalesces downloads through native staging and emits each completion once", async () => {
        const api = await ready();
        for (let i = 0; i < 3; i++) {
            const pending = deferred<string[]>();
            vi.mocked(updater.downloadUpdate).mockReturnValueOnce(pending.promise);
            const first = api.downloadUpdate();
            expect(api.downloadUpdate()).toBe(first);
            await vi.waitFor(() => expect(updater.downloadUpdate).toHaveBeenCalledTimes(i + 1), { interval: 1 });
            updater.emit("download-progress", { transferred: 50, total: 100, percent: 50, delta: 50, bytesPerSecond: 50 });
            updater.emit("update-downloaded", downloadedInfo);
            expect(api.complete).toHaveLength(i);
            expect(api.downloadUpdate()).toBe(first);
            pending.resolve([]);
            await first;
            expect(api.complete).toHaveLength(i + 1);
            expect(api.progress).toHaveLength(i + 1);
            expectCleanListeners();
        }
    });

    it.each(["throw", "reject", "event-and-reject"])("handles download %s once and permits retry", async (mode) => {
        const api = await ready();
        const error = new Error("download failed or cancelled");
        vi.mocked(updater.downloadUpdate).mockImplementationOnce(() => {
            if (mode === "throw") throw error;
            if (mode === "event-and-reject") updater.emit("error", error);
            return Promise.reject(error);
        });
        await api.downloadUpdate();
        expect(api.failed).toHaveLength(1);
        expect(log.error).toHaveBeenCalledTimes(1);
        expectCleanListeners();
        await api.downloadUpdate();
        expect(api.complete).toHaveLength(1);
        expectCleanListeners();
    });

    it("reports a fulfilled download without a downloaded event as failure", async () => {
        const api = await ready();
        vi.mocked(updater.downloadUpdate).mockResolvedValueOnce([]);
        await api.downloadUpdate();
        expect(api.failed).toHaveLength(1);
        expect(api.complete).toHaveLength(0);
        expectCleanListeners();
    });

    it("contains a throwing progress subscriber without losing download completion", async () => {
        const api = new AutoUpdaterAPI();
        const progressError = new Error("progress subscriber failed");
        const complete = vi.fn();
        api.onDownloadProgress.add(() => { throw progressError; });
        api.onDownloadComplete.add(complete);
        await api.init();
        await api.checkForUpdates();
        vi.mocked(updater.downloadUpdate).mockImplementationOnce(async () => {
            updater.emit("download-progress", { transferred: 50, total: 100, percent: 50, delta: 50, bytesPerSecond: 50 });
            updater.emit("update-downloaded", downloadedInfo);
            return [];
        });
        await api.downloadUpdate();
        expect(log.error).toHaveBeenCalledWith(progressError, "Error notifying update download progress");
        expect(complete).toHaveBeenCalledTimes(1);
        expectCleanListeners();
    });

    it("holds cancellation ownership until the native promise rejects, then permits retry", async () => {
        const api = await ready();
        const pending = deferred<string[]>();
        vi.mocked(updater.downloadUpdate).mockReturnValueOnce(pending.promise);
        const downloading = api.downloadUpdate();
        const checking = api.checkForUpdates();
        await vi.waitFor(() => expect(updater.downloadUpdate).toHaveBeenCalledTimes(1), { interval: 1 });
        // electron-updater emits cancellation before rejecting its download promise.
        updater.emit("update-cancelled", info);
        expect(api.downloadUpdate()).toBe(downloading);
        expect(api.failed).toHaveLength(0);
        expect(updater.checkForUpdates).toHaveBeenCalledTimes(1);
        expect(updater.listenerCount("download-progress")).toBe(1);
        pending.reject(new Error("cancelled"));
        await Promise.all([downloading, checking]);
        expect(api.failed).toHaveLength(1);
        expect(api.complete).toHaveLength(0);
        expect(updater.checkForUpdates).toHaveBeenCalledTimes(2);
        expectCleanListeners();
        await api.downloadUpdate();
        expect(api.complete).toHaveLength(1);
        expectCleanListeners();
    });

    it("waits for a concurrent check before starting a download", async () => {
        const api = new RecordingUpdater();
        await api.init();
        const pending = deferred<typeof available>();
        vi.mocked(updater.checkForUpdates).mockReturnValueOnce(pending.promise);
        const checking = api.checkForUpdates();
        const downloading = api.downloadUpdate();
        await vi.waitFor(() => expect(updater.checkForUpdates).toHaveBeenCalledTimes(1), { interval: 1 });
        expect(updater.downloadUpdate).not.toHaveBeenCalled();
        pending.resolve(available);
        await Promise.all([checking, downloading]);
        expect(api.complete).toHaveLength(1);
        expectCleanListeners();
    });

    it("does not replace download identity with a concurrent check", async () => {
        const api = await ready();
        const pending = deferred<string[]>();
        vi.mocked(updater.downloadUpdate).mockReturnValueOnce(pending.promise);
        const downloading = api.downloadUpdate();
        const checking = api.checkForUpdates();
        await vi.waitFor(() => expect(updater.downloadUpdate).toHaveBeenCalledTimes(1), { interval: 1 });
        expect(updater.checkForUpdates).toHaveBeenCalledTimes(1);
        updater.emit("update-downloaded", downloadedInfo);
        expect(updater.checkForUpdates).toHaveBeenCalledTimes(1);
        pending.resolve([]);
        await Promise.all([downloading, checking]);
        expect(updater.checkForUpdates).toHaveBeenCalledTimes(2);
        expect(api.complete[0].name).toBe(info.version);
        expectCleanListeners();
    });
});
