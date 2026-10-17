// SPDX-FileCopyrightText: 2025 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

/* eslint-disable @typescript-eslint/no-explicit-any */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { EventEmitter } from "node:events";

describe("Main Process Lifecycle", () => {
    let mockApp: any;
    let mockProcess: any;
    let mockProtocol: any;
    let mockSession: any;
    let mockNet: any;
    let shutdownWriters: any;

    // Mock all services
    const mockServices = {
        engineService: { registerIpcHandlers: vi.fn() },
        settingsService: {
            init: vi.fn().mockResolvedValue(undefined),
            registerIpcHandlers: vi.fn(),
            getSettings: vi.fn().mockReturnValue({ assetsPath: "", lobbyServerOverride: "", customServerList: [] }),
            updateSettings: vi.fn().mockResolvedValue(undefined),
        },
        customLobbiesService: {
            init: vi.fn().mockResolvedValue(undefined),
            registerIpcHandlers: vi.fn(),
        },
        configService: {
            init: vi.fn().mockResolvedValue(undefined),
            registerIpcHandlers: vi.fn(),
            getConfig: vi.fn().mockReturnValue({ configUrl: "", defaultServers: ["wss://server4.beyondallreason.info"] }),
        },
        accountService: { init: vi.fn().mockResolvedValue(undefined) },
        replaysService: { init: vi.fn().mockResolvedValue(undefined), registerIpcHandlers: vi.fn() },
        gameService: { registerIpcHandlers: vi.fn() },
        mapsService: { registerIpcHandlers: vi.fn() },
        autoUpdaterService: { init: vi.fn().mockResolvedValue(undefined), registerIpcHandlers: vi.fn() },
        contentService: { registerIpcHandlers: vi.fn() },
        contentAPI: { init: vi.fn().mockResolvedValue(undefined), reinit: vi.fn().mockResolvedValue(undefined) },
        logService: { registerIpcHandlers: vi.fn() },
        infoService: { registerIpcHandlers: vi.fn() },
        authService: { init: vi.fn().mockResolvedValue(undefined), registerIpcHandlers: vi.fn() },
        tachyonService: { registerIpcHandlers: vi.fn() },
        shellService: { registerIpcHandlers: vi.fn() },
        miscService: { registerIpcHandlers: vi.fn() },
        navigationService: { registerIpcHandlers: vi.fn() },
        pathsService: { registerIpcHandlers: vi.fn() },
    };

    beforeEach(async () => {
        vi.clearAllMocks();
        vi.resetModules();
        shutdownWriters = vi.fn().mockResolvedValue(undefined);
        vi.doMock("@main/content/content-write-coordinator", () => ({ shutdownContentWriters: shutdownWriters }));

        vi.stubGlobal("SPLASH_WINDOW_VITE_DEV_SERVER_URL", "http://localhost:5173/splash.html");
        vi.stubGlobal("MAIN_WINDOW_VITE_DEV_SERVER_URL", "http://localhost:5173/index.html");

        mockApp = {
            requestSingleInstanceLock: vi.fn().mockReturnValue(true),
            exit: vi.fn(),
            quit: vi.fn(),
            whenReady: vi.fn().mockResolvedValue(undefined),
            on: vi.fn(),
            setName: vi.fn(),
            enableSandbox: vi.fn(),
            commandLine: {
                appendSwitch: vi.fn(),
            },
        };

        mockProtocol = {
            registerSchemesAsPrivileged: vi.fn(),
            handle: vi.fn(),
        };

        mockSession = {
            defaultSession: {
                webRequest: {
                    onHeadersReceived: vi.fn(),
                },
            },
        };

        mockNet = {
            fetch: vi.fn(),
        };

        mockProcess = {
            argv: ["BAR"],
            env: { NODE_ENV: "development" },
            platform: "linux",
            on: vi.fn(),
            listeners: vi.fn().mockResolvedValue([]),
        };

        vi.doMock("electron", () => ({
            app: mockApp,
            protocol: mockProtocol,
            session: mockSession,
            net: mockNet,

            BrowserWindow: vi.fn().mockImplementation(() => ({
                loadURL: vi.fn(),
                show: vi.fn(),
                on: vi.fn(),
                destroy: vi.fn(),
                webContents: {
                    on: vi.fn(),
                    send: vi.fn(),
                },
            })),
            nativeImage: {
                createEmpty: vi.fn().mockReturnValue({}),
                createFromPath: vi.fn().mockReturnValue({}),
                createFromBuffer: vi.fn().mockReturnValue({}),
                createFromDataURL: vi.fn().mockReturnValue({}),
            },
        }));

        vi.doMock("node:net", () => ({
            default: {
                setDefaultAutoSelectFamily: vi.fn(),
            },
        }));

        vi.doMock("@main/splash-window", () => ({
            createSplashWindow: vi.fn().mockReturnValue({
                webContents: {},
                once: vi.fn(),
                destroy: vi.fn(),
                close: vi.fn(),
            }),
        }));

        vi.doMock("@main/browser-behaviours", () => ({
            installApplicationMenu: vi.fn(),
        }));

        vi.doMock("@main/main-window", () => ({
            createWindow: vi.fn().mockReturnValue({
                webContents: {},
                on: vi.fn(),
            }),
        }));

        vi.doMock("@main/typed-ipc", () => ({
            typedWebContents: vi.fn().mockReturnValue({}),
            ipcMain: {
                handle: vi.fn(),
            },
        }));

        vi.doMock("@main/utils/logger", () => ({
            logger: vi.fn().mockReturnValue({
                info: vi.fn(),
                error: vi.fn(),
            }),
        }));

        vi.doMock("@main/config/app", () => ({
            APP_NAME: "Test App",
            SCENARIO_IMAGE_PATH: "/test/path",
            setAssetsPath: vi.fn(),
        }));

        // Mock all services
        vi.doMock("@main/services/replays.service", () => ({ default: mockServices.replaysService }));
        vi.doMock("@main/services/game.service", () => ({ default: mockServices.gameService }));
        vi.doMock("@main/services/maps.service", () => ({ default: mockServices.mapsService }));
        vi.doMock("@main/services/engine.service", () => ({ default: mockServices.engineService }));
        vi.doMock("@main/services/auto-updater.service", () => ({ default: mockServices.autoUpdaterService }));
        vi.doMock("@main/services/config.service", () => ({ configService: mockServices.configService }));
        vi.doMock("@main/services/content.service", () => ({ default: mockServices.contentService }));
        vi.doMock("@main/content/content-api", () => ({ contentAPI: mockServices.contentAPI }));
        vi.doMock("@main/services/settings.service", () => ({ settingsService: mockServices.settingsService }));
        vi.doMock("@main/services/custom-lobbies.service", () => ({ customLobbiesService: mockServices.customLobbiesService }));
        vi.doMock("@main/services/info.service", () => ({ infoService: mockServices.infoService }));
        vi.doMock("@main/services/log.service", () => ({ logService: mockServices.logService }));
        vi.doMock("@main/services/auth.service", () => ({ authService: mockServices.authService }));
        vi.doMock("@main/services/tachyon.service", () => ({ tachyonService: mockServices.tachyonService }));
        vi.doMock("@main/services/shell.service", () => ({ shellService: mockServices.shellService }));
        vi.doMock("@main/services/news.service", () => ({ miscService: mockServices.miscService }));
        vi.doMock("@main/services/navigation.service", () => ({ navigationService: mockServices.navigationService }));
        vi.doMock("@main/services/paths.service", () => ({ pathsService: mockServices.pathsService }));
        vi.doMock("@main/game/chobby-loopback-helper", () => ({
            isChobbyLoopbackHelperProcess: vi.fn().mockReturnValue(false),
            runChobbyLoopbackHelper: vi.fn(),
        }));

        vi.stubGlobal("process", mockProcess);
    });

    afterEach(() => {
        vi.clearAllMocks();
        vi.resetModules();
    });

    it("should exit if single instance lock is not acquired in production", async () => {
        mockApp.requestSingleInstanceLock.mockReturnValue(false);
        mockProcess.env.NODE_ENV = "production";

        await import("@main/main");

        expect(mockApp.requestSingleInstanceLock).toHaveBeenCalled();
        expect(mockApp.exit).toHaveBeenCalledWith(0);
    });

    it("lets the detached Chobby helper start without taking the parent app lock", async () => {
        mockProcess.argv.push("--bar-chobby-loopback-helper");
        const helper = vi.fn().mockResolvedValue(undefined);
        vi.doMock("@main/game/chobby-loopback-helper", () => ({ isChobbyLoopbackHelperProcess: () => true, runChobbyLoopbackHelper: helper }));
        await import("@main/main");
        expect(helper).toHaveBeenCalledOnce();
        expect(mockApp.requestSingleInstanceLock).not.toHaveBeenCalled();
        expect(mockServices.configService.init).not.toHaveBeenCalled();
        expect(mockApp.whenReady).not.toHaveBeenCalled();
    });

    it("should start the app successfully and initialize basic configurations", async () => {
        await import("@main/main");

        expect(mockApp.requestSingleInstanceLock).toHaveBeenCalled();
        expect(mockApp.setName).toHaveBeenCalledWith("Test App");
        expect(mockApp.on).toHaveBeenCalledWith("window-all-closed", expect.any(Function));
        expect(mockApp.enableSandbox).toHaveBeenCalled();
        expect(mockApp.commandLine.appendSwitch).toHaveBeenCalledWith("disable-features", "HardwareMediaKeyHandling,MediaSessionService");
        expect(mockApp.commandLine.appendSwitch).toHaveBeenCalledWith("disable-pinch", "1");
        expect(mockApp.whenReady).toHaveBeenCalled();
    });

    it("should handle graceful exit on SIGTERM for non-Windows platforms", async () => {
        mockProcess.platform = "linux";
        let sigTermHandler: any;
        mockProcess.on.mockImplementation((event: string, handler: any) => {
            if (event === "SIGTERM") {
                sigTermHandler = handler;
            }
        });

        await import("@main/main");

        expect(mockProcess.on).toHaveBeenCalledWith("SIGTERM", expect.any(Function));

        // Simulate SIGTERM
        sigTermHandler();
        expect(mockApp.quit).toHaveBeenCalled();
    });

    it("should handle graceful exit on message for Windows platform", async () => {
        mockProcess.platform = "win32";
        let messageHandler: any;
        mockProcess.on.mockImplementation((event: string, handler: any) => {
            if (event === "message") {
                messageHandler = handler;
            }
        });

        await import("@main/main");

        expect(mockProcess.on).toHaveBeenCalledWith("message", expect.any(Function));

        // Simulate graceful-exit message
        messageHandler("graceful-exit");
        expect(mockApp.quit).toHaveBeenCalled();
    });

    it("should not handle graceful exit in production environment", async () => {
        mockProcess.env.NODE_ENV = "production";

        await import("@main/main");

        expect(mockProcess.on).not.toHaveBeenCalled();
    });

    it("should initialize services when app is ready", async () => {
        await import("@main/main");

        expect(mockServices.configService.init).toHaveBeenCalled();
        expect(mockServices.settingsService.init).toHaveBeenCalled();
        expect(mockServices.customLobbiesService.init).toHaveBeenCalled();
        expect(mockServices.contentAPI.init).toHaveBeenCalled();
        expect(mockServices.authService.init).toHaveBeenCalled();
        expect(mockServices.replaysService.init).toHaveBeenCalled();
        expect(mockServices.autoUpdaterService.init).toHaveBeenCalled();
    });

    // A saved assets path on a drive that is not there makes content init throw, and the screen that lets
    // the user repoint it cannot appear unless the window is created anyway.
    it("should still create the window when content initialisation fails", async () => {
        mockServices.contentAPI.init.mockRejectedValueOnce(new Error("ENOENT: assets path is gone"));

        await import("@main/main");

        expect(mockServices.contentAPI.init).toHaveBeenCalled();
        expect(mockServices.contentService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.pathsService.registerIpcHandlers).toHaveBeenCalled();
    });

    it("should register IPC handlers when app is ready", async () => {
        await import("@main/main");

        expect(mockServices.configService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.logService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.infoService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.settingsService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.customLobbiesService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.authService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.tachyonService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.replaysService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.contentService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.engineService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.gameService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.mapsService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.shellService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.miscService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.autoUpdaterService.registerIpcHandlers).toHaveBeenCalled();
        expect(mockServices.navigationService.registerIpcHandlers).toHaveBeenCalled();
    });

    it("blocks repeated quit requests until owned downloader closure, then permits final quit", async () => {
        let finish!: () => void;
        shutdownWriters.mockImplementation(() => new Promise<void>((resolve) => { finish = resolve; }));
        await import("@main/main");
        const beforeQuit = mockApp.on.mock.calls.find(([event]: [string]) => event === "before-quit")[1];
        const first = { preventDefault: vi.fn() }, repeated = { preventDefault: vi.fn() };
        beforeQuit(first);
        beforeQuit(repeated);
        expect(first.preventDefault).toHaveBeenCalledOnce();
        expect(repeated.preventDefault).toHaveBeenCalledOnce();
        expect(shutdownWriters).toHaveBeenCalledOnce();
        expect(mockApp.quit).not.toHaveBeenCalled();
        finish();
        await Promise.resolve();
        await Promise.resolve();
        expect(mockApp.quit).toHaveBeenCalledOnce();
        const final = { preventDefault: vi.fn() };
        beforeQuit(final);
        expect(final.preventDefault).not.toHaveBeenCalled();
        expect(shutdownWriters).toHaveBeenCalledOnce();
    });

    it("does not exit or retry if stopping an owned downloader fails", async () => {
        shutdownWriters.mockRejectedValue(new Error("owned child termination failed"));
        await import("@main/main");
        const beforeQuit = mockApp.on.mock.calls.find(([event]: [string]) => event === "before-quit")[1];
        beforeQuit({ preventDefault: vi.fn() });
        await Promise.resolve();
        await Promise.resolve();
        beforeQuit({ preventDefault: vi.fn() });
        expect(mockApp.quit).not.toHaveBeenCalled();
        expect(mockApp.exit).not.toHaveBeenCalled();
        expect(shutdownWriters).toHaveBeenCalledOnce();
    });
});

describe("Detached Chobby helper ownership", () => {
    const dataPath = "/test/chobby/data";
    const connectionPath = `${dataPath}/sl-connection.json`;
    const parentPID = 12001;
    const nativePID = 12002;
    let files: Map<string, string>;
    let alive: Set<number>;
    let servers: any[];
    let spawn: any;
    let app: any;
    let fsPromises: any;
    let connect: any;
    let Loopback: any;
    let GameAPI: any;
    let helperLoopback: any;
    let helperProcess: any;
    let nativeProcess: any;
    let ownerProbe: any;
    let shutdownWriters: any;
    let acquireChecksumHold: any;
    let releaseChecksumHold: any;
    let requireContentWritesOpen: any;
    let onRead: ((file: string, value: string) => void) | undefined;

    function child(pid: number | undefined) {
        const result: any = new EventEmitter();
        Object.assign(result, { pid, exitCode: null, signalCode: null, killed: false, unref: vi.fn() });
        result.kill = vi.fn(() => {
            result.killed = true;
            return true;
        });
        return result;
    }

    function socket() {
        const result: any = new EventEmitter();
        result.destroyed = false;
        result.deferClose = false;
        result.setTimeout = vi.fn();
        result.destroy = vi.fn(() => {
            if (result.destroyed) return;
            result.destroyed = true;
            if (!result.deferClose) result.emit("close");
            if (result.peer && !result.peer.destroyed) result.peer.destroy();
        });
        return result;
    }

    function menuClient() {
        const client = socket();
        servers.at(-1).accept(client);
        return client;
    }

    function bridge(options: Record<string, unknown> = {}) {
        let result: any;
        const onIdle = vi.fn(() => { void result.close(); });
        result = new Loopback({
            engineVersion: "2026.07.04", assetsPath: "/test/assets", writeDataPath: dataPath,
            platform: "darwin", startupOwnerPID: parentPID, idleShutdownDelayMs: 5000, onIdle, ...options,
        });
        return { result, onIdle };
    }

    beforeEach(async () => {
        vi.unstubAllGlobals();
        vi.restoreAllMocks();
        vi.resetModules();
        vi.useFakeTimers();
        files = new Map();
        alive = new Set([parentPID, nativePID, process.pid]);
        servers = [];
        onRead = undefined;
        helperLoopback = undefined;
        helperProcess = child(process.pid);
        nativeProcess = child(nativePID);
        app = {
            exit: vi.fn(), hide: vi.fn(), dock: { hide: vi.fn() }, getAppPath: vi.fn(() => "/test/BAR.app"),
            disableHardwareAcceleration: vi.fn(), setActivationPolicy: vi.fn(), whenReady: vi.fn().mockResolvedValue(undefined),
        };
        fsPromises = {
            mkdir: vi.fn().mockResolvedValue(undefined),
            readFile: vi.fn(async (file: string) => {
                const value = files.get(file);
                if (value === undefined) throw Object.assign(new Error("missing"), { code: "ENOENT" });
                onRead?.(file, value);
                return value;
            }),
            writeFile: vi.fn(async (file: string, value: string, options?: any) => {
                if (options?.flag === "wx" && files.has(file)) throw Object.assign(new Error("exists"), { code: "EEXIST" });
                files.set(file, value);
            }),
            rename: vi.fn(async (from: string, to: string) => {
                const value = files.get(from);
                if (value === undefined) throw new Error("temporary file missing");
                files.set(to, value);
                files.delete(from);
            }),
            unlink: vi.fn(async (file: string) => { files.delete(file); }),
            rm: vi.fn(async (file: string) => { files.delete(file); }),
        };
        connect = vi.fn(() => {
            const client = socket(), peer = socket();
            client.peer = peer;
            peer.peer = client;
            void Promise.resolve().then(() => { servers.at(-1).accept(peer); client.emit("connect"); });
            return client;
        });
        spawn = vi.fn((command: string, args: string[]) => {
            if (args.includes("--bar-chobby-loopback-helper")) {
                const ownedHelper = helperProcess, ownedLoopback = helperLoopback;
                void ownedLoopback.start();
                ownedHelper.kill.mockImplementation(() => { ownedHelper.killed = true; void ownedLoopback.close(); return true; });
                return helperProcess;
            }
            void Promise.resolve().then(() => nativeProcess.emit("spawn"));
            return nativeProcess;
        });
        vi.doMock("electron", () => ({ app, BrowserWindow: { fromId: vi.fn(() => null) }, screen: { getDisplayMatching: vi.fn() }, shell: { openExternal: vi.fn() } }));
        vi.doMock("@main/services/settings.service", () => ({ settingsService: { getSettings: () => ({ fullscreen: true }) } }));
        vi.doMock("@main/game/chobby-display-settings", () => ({ prepareChobbyDisplaySettings: vi.fn().mockResolvedValue(undefined) }));
        vi.doMock("fs", () => ({ promises: fsPromises }));
        vi.doMock("net", () => ({
            createConnection: connect,
            createServer: (accept: (client: any) => void) => {
                const server: any = new EventEmitter();
                server.accept = accept;
                server.port = 31000 + servers.length;
                server.listen = vi.fn(() => { void Promise.resolve().then(() => server.emit("listening")); });
                server.address = () => ({ address: "127.0.0.1", port: server.port });
                server.close = vi.fn((callback: () => void) => { void Promise.resolve().then(callback); });
                servers.push(server);
                return server;
            },
        }));
        vi.doMock("child_process", () => ({ spawn }));
        vi.doMock("@main/config/app", () => ({
            WRITE_DATA_PATH: dataPath, REPLAYS_PATH: "/test/replays", LOGS_PATH: "/test/logs", BUNDLED_ASSETS_PATH: "/test/bundled",
            getAssetsPath: () => "/test/assets", getCaCertPath: () => undefined,
            getRapidIndexPath: () => "/test/rapid", getPackagePath: () => "/test/packages", getPoolPath: () => "/test/pool",
        }));
        vi.doMock("@main/config/native-engine-runner", () => ({
            getNativeEngineProcessEnv: () => ({}), getNativeEngineProcessEnvDiagnostics: () => ({}), getNativeEngineDataDirDiagnostics: () => [],
            resolveNativeEngineRunner: () => ({ enginePath: "/test/engine", binaryFileName: "spring", spawnCommand: "./spring" }),
            prepareMacOSLuaUIOverlayForLaunch: vi.fn().mockResolvedValue({ prepared: false }), resolvePrDownloaderPath: () => "/test/pr-downloader",
            MACOS_NATIVE_ENGINE_ENV_DIAGNOSTIC_PROBE: "native-env", MACOS_NATIVE_ENGINE_DATA_DIR_DIAGNOSTIC_PROBE: "native-data",
            MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV: "disable", MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV: "enable",
            MACOS_MINIMAL_FPS_WORKAROUND_REASON: "test", MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE: "quiet,flushsync",
        }));
        vi.doMock("@main/utils/logger", () => ({ logger: () => ({ info: vi.fn(), debug: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));
        vi.doMock("@main/utils/extract-7z", () => ({ extract7z: vi.fn() }));
        vi.doMock("@main/content/engine/engine-content", () => ({ engineContentAPI: {} }));
        vi.doMock("@main/content/game/game-content", () => ({ gameContentAPI: {} }));
        vi.doMock("@main/game/springsettings", () => ({ applyDefaultSpringsettings: vi.fn() }));
        vi.doMock("@main/utils/start-script-converter", () => ({ startScriptConverter: {} }));
        vi.doMock("@main/game/chobby-multiplayer-profile", () => ({
            CHOBBY_MULTIPLAYER_GAME_RAPID_ALIAS: "byar:test",
            resolveChobbyMultiplayerProfile: vi.fn().mockResolvedValue({ engineVersion: "2026.07.04", gameRapidAlias: "byar:test", source: "bundled-manifest" }),
        }));
        vi.doMock("@main/game/engine-log-mirror", () => ({ createEngineLobbyLogMirror: () => ({ write: vi.fn(), summarize: vi.fn() }) }));
        vi.doMock("@main/game/engine-stderr-log", () => ({ createEngineStderrLog: () => ({ write: vi.fn(), close: vi.fn() }) }));
        shutdownWriters = vi.fn().mockResolvedValue(undefined);
        requireContentWritesOpen = vi.fn();
        vi.doMock("@main/content/content-write-coordinator", () => ({ shutdownContentWriters: shutdownWriters, requireContentWritesOpen }));
        releaseChecksumHold = vi.fn();
        acquireChecksumHold = vi.fn().mockResolvedValue(releaseChecksumHold);
        vi.doMock("@main/utils/checksums", () => ({ acquireChecksumHold }));
        vi.doUnmock("@main/game/chobby-loopback-helper");
        ownerProbe = vi.spyOn(process, "kill").mockImplementation((pid, signal) => {
            if (signal !== 0) throw new Error("CPU fixture must not send OS signals");
            if (!alive.has(pid)) throw Object.assign(new Error("owner exited"), { code: "ESRCH" });
            return true;
        });
        ({ ChobbyLauncherLoopback: Loopback } = await import("@main/game/chobby-launcher-loopback"));
        ({ GameAPI } = await import("@main/game/game"));
    });

    afterEach(() => {
        vi.useRealTimers();
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
        vi.unstubAllEnvs();
        vi.resetModules();
    });

    it("passes the actual launcher display bounds instead of a saved display index or resolution", async () => {
        const { BrowserWindow, screen } = await import("electron");
        vi.stubEnv("MAIN_WINDOW_ID", "42");
        const bounds = { x: -1800, y: 0, width: 1800, height: 1125 };
        const getBounds = vi.fn(() => ({ x: -1700, y: 50, width: 1200, height: 800 }));
        vi.mocked(BrowserWindow.fromId).mockReturnValue({ isDestroyed: () => false, getBounds } as any);
        vi.mocked(screen.getDisplayMatching).mockReturnValue({ bounds } as any);
        const api: any = new GameAPI();
        expect(api.getMacOSLaunchDisplayEnv()).toEqual({ BAR_MACOS_TARGET_DISPLAY: "-1800,0,1800,1125" });
        expect(screen.getDisplayMatching).toHaveBeenCalledWith(getBounds());
        vi.mocked(BrowserWindow.fromId).mockReturnValue(null);
        expect(api.getMacOSLaunchDisplayEnv()).toEqual({});
    });

    it("preserves Chobby's explicit game fullscreen and windowed choices through the helper", () => {
        const { result }: { result: any } = bridge();
        const fullscreen = "WindowBorderless = 0\nFullscreen = 1\n";
        const windowed = "WindowBorderless = 0\nFullscreen = 0\n";
        expect(result.normalizeMacOSDisplaySpringSettings(fullscreen)).toBe(fullscreen);
        expect(result.normalizeMacOSDisplaySpringSettings(windowed)).toBe(windowed);
        expect(result.normalizeMacOSDisplaySpringSettings("WindowBorderless = 1\n")).toBe("WindowBorderless = 1\nFullscreen = 0\n");
        expect(result.normalizeMacOSDisplaySpringSettings("VSync = 0\n")).toBe("VSync = 0\nFullscreen = 1\n");
    });

    it("compares the complete sync identity, including a development branch suffix", async () => {
        const api: any = new GameAPI();
        vi.spyOn(api, "readNativeEngineVersion").mockResolvedValue("2026.09.01-24-g01efdf4 master\n");
        await expect(api.assertNativeRuntimeEngineVersionMatches("2026.09.01-24-g01efdf4 master")).resolves.toBeUndefined();
        await expect(api.assertNativeRuntimeEngineVersionMatches("2026.09.01-24-g01efdf4")).rejects.toThrow(/reports 2026.09.01-24-g01efdf4 master/);
        await expect(api.assertNativeRuntimeEngineVersionMatches("2026.07.04", "Chobby multiplayer")).rejects.toThrow(/Do not alias/);
    });

    function preparedAPI() {
        const api: any = new GameAPI();
        for (const name of ["assertNativeRuntimeEngineVersionMatches", "ensureChobbyConfigFile", "ensureChobbySpringSettings",
            "ensureChobbyMenuArchive", "ensureChobbyMultiplayerGameContent", "ensureChobbyEngineVersionAlias"]) {
            vi.spyOn(api, name).mockResolvedValue(undefined);
        }
        return api;
    }

    it("joins overlapping Chobby requests before any settings migration or helper spawn", async () => {
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const api = preparedAPI();
        let releasePreparation!: () => void;
        api.ensureChobbyConfigFile.mockImplementation(() => new Promise<void>((resolve) => { releasePreparation = resolve; }));
        const first = api.launchChobby();
        const second = api.launchChobby();
        await vi.advanceTimersByTimeAsync(0);
        expect(api.ensureChobbyConfigFile).toHaveBeenCalledOnce();
        expect(spawn).not.toHaveBeenCalled();
        releasePreparation();
        await vi.advanceTimersByTimeAsync(100);
        await Promise.all([first, second]);
        const { prepareChobbyDisplaySettings } = await import("@main/game/chobby-display-settings");
        expect(prepareChobbyDisplaySettings).toHaveBeenCalledOnce();
        expect(spawn.mock.calls.filter(([, args]: [string, string[]]) => args.includes("--bar-chobby-loopback-helper"))).toHaveLength(1);
        expect(spawn.mock.calls.filter(([, args]: [string, string[]]) => args.includes("--menu"))).toHaveLength(1);
        expect(JSON.parse(files.get(connectionPath)!)._sl_engine_pid).toBe(nativePID);
        await helperLoopback.close();
    });

    it("shares a failed Chobby preparation and allows a later retry", async () => {
        const api = preparedAPI();
        api.ensureChobbyConfigFile.mockRejectedValueOnce(new Error("settings unavailable"));
        const failures = await Promise.allSettled([api.launchChobby(), api.launchChobby()]);
        expect(failures.map((result) => result.status)).toEqual(["rejected", "rejected"]);
        expect(failures.every((result) => result.status === "rejected" && result.reason.message === "settings unavailable")).toBe(true);
        expect(api.ensureChobbyConfigFile).toHaveBeenCalledOnce();
        expect(spawn).not.toHaveBeenCalled();
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const retry = api.launchChobby();
        await vi.advanceTimersByTimeAsync(100);
        await retry;
        expect(api.ensureChobbyConfigFile).toHaveBeenCalledTimes(2);
        expect(spawn.mock.calls.filter(([, args]: [string, string[]]) => args.includes("--menu"))).toHaveLength(1);
        await helperLoopback.close();
    });

    it("does not repeat Chobby preparation after a successful detached handoff while the parent drains", async () => {
        shutdownWriters.mockImplementation(() => new Promise<void>(() => {}));
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const api = preparedAPI();
        const launch = api.launchChobby();
        await vi.advanceTimersByTimeAsync(100);
        await launch;
        await expect(api.launchChobby()).rejects.toThrow("engine process is still owned");
        expect(api.ensureChobbyConfigFile).toHaveBeenCalledOnce();
        expect(spawn.mock.calls.filter(([, args]: [string, string[]]) => args.includes("--bar-chobby-loopback-helper"))).toHaveLength(1);
        expect(spawn.mock.calls.filter(([, args]: [string, string[]]) => args.includes("--menu"))).toHaveLength(1);
        expect(app.exit).not.toHaveBeenCalled();
        await helperLoopback.close();
    });

    it("waits for checksum ownership before launching and rejects a concurrent pending launch", async () => {
        let grant!: (release: () => void) => void;
        acquireChecksumHold.mockImplementationOnce(() => new Promise((resolve) => { grant = resolve; }));
        const api = preparedAPI();
        const held = vi.spyOn(api, "launchNativeEngineHeld").mockImplementation(async (_settings: unknown, onSpawned: any) => onSpawned(nativeProcess));
        const launch = api.launchNativeEngine({ engineVersion: "test", args: [] });
        expect(held).not.toHaveBeenCalled();
        await expect(api.launchNativeEngine({ engineVersion: "test", args: [] })).rejects.toThrow("engine process is still owned");
        grant(releaseChecksumHold);
        await launch;
        expect(held).toHaveBeenCalledOnce();
        expect(releaseChecksumHold).not.toHaveBeenCalled();
        nativeProcess.emit("exit", 0, null);
        expect(releaseChecksumHold).not.toHaveBeenCalled();
        nativeProcess.emit("close", 0, null);
        expect(releaseChecksumHold).toHaveBeenCalledOnce();
    });

    it("releases checksum ownership when native preparation fails before spawn", async () => {
        const api = preparedAPI();
        api.assertNativeRuntimeEngineVersionMatches.mockRejectedValue(new Error("version mismatch"));
        await expect(api.launchNativeEngine({ engineVersion: "test", args: [] })).rejects.toThrow("version mismatch");
        expect(spawn).not.toHaveBeenCalled();
        expect(releaseChecksumHold).toHaveBeenCalledOnce();
        expect(api.nativeLaunchPending).toBe(false);
    });

    it("does not spawn a waiting native launch once ordinary shutdown has begun", async () => {
        const api = preparedAPI();
        requireContentWritesOpen.mockImplementation(() => { throw new Error("Content writes stopped because the launcher is quitting"); });
        await expect(api.launchNativeEngine({ engineVersion: "test", args: [] })).rejects.toThrow("launcher is quitting");
        expect(spawn).not.toHaveBeenCalled();
        expect(releaseChecksumHold).toHaveBeenCalledOnce();
    });

    it("does not let helper readiness disconnect start the menu's five-second idle clock", async () => {
        const { result, onIdle } = bridge({ startupOwnerPID: process.pid });
        helperLoopback = result;
        const api: any = new GameAPI();
        const preparation = api.prepareDetachedChobbyLauncherLoopback("2026.07.04");
        await vi.advanceTimersByTimeAsync(100);
        await preparation;
        await vi.advanceTimersByTimeAsync(6000);
        expect(onIdle).not.toHaveBeenCalled();
        expect(connect).not.toHaveBeenCalled();
        expect(files.has(connectionPath)).toBe(true);
        await result.close();
    });

    it("keeps a slow live native startup beyond the validation deadline without a product cutoff", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        const record = JSON.parse(files.get(connectionPath)!);
        files.set(connectionPath, JSON.stringify({ ...record, _sl_engine_pid: nativePID }));
        alive.delete(parentPID);
        await vi.advanceTimersByTimeAsync(180000);
        expect(onIdle).not.toHaveBeenCalled();
        expect(files.has(connectionPath)).toBe(true);
        expect(ownerProbe).toHaveBeenCalledWith(nativePID, 0);
        await result.close();
    });

    it("closes and unlinks when the startup parent dies before native handoff", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        alive.delete(parentPID);
        await vi.advanceTimersByTimeAsync(5000);
        expect(onIdle).toHaveBeenCalledOnce();
        expect(files.has(connectionPath)).toBe(false);
    });

    it("closes when the latched native owner dies before the first menu client", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        files.set(connectionPath, JSON.stringify({ ...JSON.parse(files.get(connectionPath)!), _sl_engine_pid: nativePID }));
        await vi.advanceTimersByTimeAsync(5000);
        alive.delete(nativePID);
        await vi.advanceTimersByTimeAsync(5000);
        expect(onIdle).toHaveBeenCalledOnce();
        expect(files.has(connectionPath)).toBe(false);
    });

    it("re-reads handoff metadata when the parent exits after the first record read", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        onRead = (file, oldRecord) => {
            if (file !== connectionPath) return;
            onRead = undefined;
            files.set(file, JSON.stringify({ ...JSON.parse(oldRecord), _sl_engine_pid: nativePID }));
            alive.delete(parentPID);
        };
        await vi.advanceTimersByTimeAsync(5000);
        expect(onIdle).not.toHaveBeenCalled();
        expect(ownerProbe).toHaveBeenCalledWith(nativePID, 0);
        await result.close();
    });

    it("stops startup liveness work on the first actual client and preserves exact five-second idle", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        const client = menuClient();
        alive.clear();
        await vi.advanceTimersByTimeAsync(180000);
        expect(ownerProbe).not.toHaveBeenCalled();
        expect(onIdle).not.toHaveBeenCalled();
        client.destroy();
        await vi.advanceTimersByTimeAsync(4999);
        expect(onIdle).not.toHaveBeenCalled();
        await vi.advanceTimersByTimeAsync(1);
        expect(onIdle).toHaveBeenCalledOnce();
    });

    it("preserves reconnect and tracked-child protection from idle shutdown", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        menuClient().destroy();
        await vi.advanceTimersByTimeAsync(4999);
        const reconnected = menuClient();
        await vi.advanceTimersByTimeAsync(10000);
        expect(onIdle).not.toHaveBeenCalled();
        const game = child(13001);
        result.trackChildProcess(game, "game");
        reconnected.destroy();
        await vi.advanceTimersByTimeAsync(10000);
        expect(onIdle).not.toHaveBeenCalled();
        game.emit("exit", 0, null);
        await vi.advanceTimersByTimeAsync(4999);
        expect(onIdle).not.toHaveBeenCalled();
        await vi.advanceTimersByTimeAsync(1);
        expect(onIdle).toHaveBeenCalledOnce();
    });

    it("ignores old socket and child events after close and restart", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        const oldClient = menuClient();
        oldClient.deferClose = true;
        const oldChild = child(13001);
        result.trackChildProcess(oldChild, "old game");
        await result.close();
        await result.start();
        oldClient.emit("close");
        oldChild.emit("exit", 0, null);
        await vi.advanceTimersByTimeAsync(5000);
        expect(onIdle).not.toHaveBeenCalled();
        expect(files.has(connectionPath)).toBe(true);
        await result.close();
    });

    it("waits for pending close deletion before publishing a restarted connection record", async () => {
        const { result } = bridge();
        await result.start();
        let finishClose: (() => void) | undefined;
        servers[0].close.mockImplementation((callback: () => void) => { finishClose = callback; });
        const closing = result.close();
        const restarting = result.start();
        await vi.advanceTimersByTimeAsync(0);
        expect(servers).toHaveLength(1);
        finishClose!();
        await closing;
        await restarting;
        expect(JSON.parse(files.get(connectionPath)!)._sl_port).toBe(servers[1].port);
        await result.close();
    });

    it("publishes the native owner atomically before exiting the detached parent", async () => {
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const launch = preparedAPI().launchChobby();
        await vi.advanceTimersByTimeAsync(100);
        await launch;
        expect(JSON.parse(files.get(connectionPath)!)._sl_engine_pid).toBe(nativePID);
        expect(fsPromises.rename).toHaveBeenCalledOnce();
        await vi.advanceTimersByTimeAsync(1);
        expect(app.exit).toHaveBeenCalledWith(0);
        expect(helperProcess.kill).not.toHaveBeenCalled();
        expect(releaseChecksumHold).not.toHaveBeenCalled();
        nativeProcess.emit("close", 0, null);
        expect(releaseChecksumHold).toHaveBeenCalledOnce();
        await helperLoopback.close();
    });

    it("drains parent downloaders after handoff without stopping the detached owners", async () => {
        let finish!: () => void;
        shutdownWriters.mockImplementation(() => new Promise<void>((resolve) => { finish = resolve; }));
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const launch = preparedAPI().launchChobby();
        await vi.advanceTimersByTimeAsync(100);
        await launch;
        expect(JSON.parse(files.get(connectionPath)!)._sl_engine_pid).toBe(nativePID);
        expect(shutdownWriters).toHaveBeenCalledOnce();
        expect(app.exit).not.toHaveBeenCalled();
        expect(nativeProcess.unref).toHaveBeenCalledOnce();
        expect(nativeProcess.kill).not.toHaveBeenCalled();
        expect(helperProcess.kill).not.toHaveBeenCalled();
        finish();
        await vi.advanceTimersByTimeAsync(1);
        expect(app.exit).toHaveBeenCalledWith(0);
        await helperLoopback.close();
    });

    it("does not roll back a detached menu if the parent download drain fails", async () => {
        shutdownWriters.mockRejectedValue(new Error("owned download did not stop"));
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const launch = preparedAPI().launchChobby();
        await vi.advanceTimersByTimeAsync(100);
        await launch;
        expect(JSON.parse(files.get(connectionPath)!)._sl_engine_pid).toBe(nativePID);
        expect(app.exit).not.toHaveBeenCalled();
        expect(nativeProcess.kill).not.toHaveBeenCalled();
        expect(helperProcess.kill).not.toHaveBeenCalled();
        await helperLoopback.close();
    });

    it("stops only the owned native and helper when ownership publication fails", async () => {
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        fsPromises.rename.mockRejectedValueOnce(new Error("owner publication failed"));
        const api = preparedAPI();
        const launch = api.launchChobby();
        const rejected = expect(launch).rejects.toThrow("owner publication failed");
        await vi.advanceTimersByTimeAsync(100);
        await rejected;
        expect(nativeProcess.kill).toHaveBeenCalledOnce();
        expect(nativeProcess.kill).toHaveBeenCalledWith("SIGTERM");
        expect(helperProcess.kill).toHaveBeenCalledOnce();
        expect(app.exit).not.toHaveBeenCalled();
        expect(nativeProcess.unref).not.toHaveBeenCalled();
        expect(api.gameProcess).toBe(nativeProcess);
        const callsBeforeRetry = spawn.mock.calls.length;
        await expect(api.launchChobby()).rejects.toThrow("engine process is still owned");
        await expect(api.launchNativeEngine({ engineVersion: "test", args: [] })).rejects.toThrow("engine process is still owned");
        expect(spawn).toHaveBeenCalledTimes(callsBeforeRetry);
        expect(api.gameProcess).toBe(nativeProcess);
        nativeProcess.exitCode = 1;
        nativeProcess.emit("exit", 1, null);
        helperProcess.exitCode = 0;
        helperProcess.emit("exit", 0, null);
        await vi.advanceTimersByTimeAsync(0);
        expect(api.gameProcess).toBeNull();
        helperProcess = child(process.pid);
        nativeProcess = child(nativePID + 1);
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const recovery = api.launchChobby();
        await vi.advanceTimersByTimeAsync(100);
        await recovery;
        expect(JSON.parse(files.get(connectionPath)!)._sl_engine_pid).toBe(nativePID + 1);
        await helperLoopback.close();
    });

    it("handles helper spawn error and rejects readiness without an unhandled child error", async () => {
        helperProcess = child(undefined);
        spawn.mockImplementation(() => { void Promise.resolve().then(() => helperProcess.emit("error", new Error("helper spawn failed"))); return helperProcess; });
        const api: any = new GameAPI();
        const preparation = api.prepareDetachedChobbyLauncherLoopback("2026.07.04");
        const rejected = expect(preparation).rejects.toThrow("helper spawn failed");
        await vi.advanceTimersByTimeAsync(100);
        await rejected;
        expect(helperProcess.kill).not.toHaveBeenCalled();
    });

    it("stops the owned helper when native spawn fails", async () => {
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const originalSpawn = spawn.getMockImplementation();
        spawn.mockImplementation((command: string, args: string[]) => {
            if (args.includes("--bar-chobby-loopback-helper")) return originalSpawn(command, args);
            nativeProcess.pid = undefined;
            void Promise.resolve().then(() => nativeProcess.emit("error", new Error("native spawn failed")));
            return nativeProcess;
        });
        const launch = preparedAPI().launchChobby();
        const rejected = expect(launch).rejects.toThrow("native spawn failed");
        await vi.advanceTimersByTimeAsync(100);
        await rejected;
        expect(helperProcess.kill).toHaveBeenCalledOnce();
        expect(app.exit).not.toHaveBeenCalled();
    });

    it("rejects handoff if the helper exits during atomic owner publication", async () => {
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const rename = fsPromises.rename.getMockImplementation();
        fsPromises.rename.mockImplementationOnce(async (from: string, to: string) => {
            await rename(from, to);
            helperProcess.exitCode = 1;
            helperProcess.emit("exit", 1, null);
        });
        const api = preparedAPI();
        const launch = api.launchChobby();
        const rejected = expect(launch).rejects.toThrow("helper exited before native handoff");
        await vi.advanceTimersByTimeAsync(100);
        await rejected;
        expect(nativeProcess.kill).toHaveBeenCalledWith("SIGTERM");
        expect(api.gameProcess).toBe(nativeProcess);
        expect(nativeProcess.unref).not.toHaveBeenCalled();
        expect(app.exit).not.toHaveBeenCalled();
        await helperLoopback.close();
    });

    it("does not let an old asynchronous owner read latch into a restarted generation", async () => {
        const { result, onIdle } = bridge();
        await result.start();
        const oldRecord = { ...JSON.parse(files.get(connectionPath)!), _sl_engine_pid: nativePID };
        let finishRead: ((value: string) => void) | undefined;
        fsPromises.readFile.mockImplementationOnce(() => new Promise<string>((resolve) => { finishRead = resolve; }));
        await vi.advanceTimersByTimeAsync(5000);
        await result.close();
        await result.start();
        alive.delete(nativePID);
        finishRead!(JSON.stringify(oldRecord));
        await vi.advanceTimersByTimeAsync(5000);
        expect(onIdle).not.toHaveBeenCalled();
        expect(files.has(connectionPath)).toBe(true);
        await result.close();
    });

    it.each([
        ["helper PID", "_sl_helper_pid", 99999],
        ["host", "_sl_address", "192.0.2.1"],
        ["port", "_sl_port", 0],
        ["write directory", "_sl_write_path", "/other/data"],
    ])("rejects a readiness record with a different %s and stops only its owned helper", async (_, key, value) => {
        helperLoopback = bridge({ startupOwnerPID: process.pid }).result;
        const write = fsPromises.writeFile.getMockImplementation();
        fsPromises.writeFile.mockImplementation(async (file: string, raw: string, options?: unknown) => {
            await write(file, file === connectionPath ? JSON.stringify({ ...JSON.parse(raw), [key]: value }) : raw, options);
        });
        const api: any = new GameAPI();
        const preparation = api.prepareDetachedChobbyLauncherLoopback("2026.07.04");
        const rejected = expect(preparation).rejects.toThrow("Timed out waiting for Chobby loopback helper");
        await vi.advanceTimersByTimeAsync(10000);
        await rejected;
        expect(helperProcess.kill).toHaveBeenCalledOnce();
        expect(helperProcess.kill).toHaveBeenCalledWith("SIGTERM");
        expect(nativeProcess.kill).not.toHaveBeenCalled();
    });

    it("waits for an initial connection write before removing its stopped generation", async () => {
        const { result, onIdle } = bridge();
        const write = fsPromises.writeFile.getMockImplementation();
        let finishWrite: (() => void) | undefined;
        fsPromises.writeFile.mockImplementationOnce((file: string, raw: string, options: unknown) => new Promise<void>((resolve) => {
            finishWrite = () => { void write(file, raw, options).then(resolve); };
        }));
        const starting = result.start();
        const rejected = expect(starting).rejects.toThrow("stopped during startup");
        await vi.advanceTimersByTimeAsync(0);
        expect(finishWrite).toBeTypeOf("function");
        let closed = false;
        const closing = result.close().then(() => { closed = true; });
        await vi.advanceTimersByTimeAsync(0);
        expect(closed).toBe(false);
        finishWrite!();
        await closing;
        await rejected;
        expect(files.has(connectionPath)).toBe(false);
        expect(onIdle).not.toHaveBeenCalled();
        expect(vi.getTimerCount()).toBe(0);
    });

    it("does not start a helper server after shutdown while waiting for app readiness", async () => {
        let ready: (() => void) | undefined;
        app.whenReady.mockReturnValue(new Promise<void>((resolve) => { ready = resolve; }));
        vi.stubEnv("BAR_CHOBBY_LOOPBACK_HELPER_OPTIONS", JSON.stringify({
            engineVersion: "2026.07.04", assetsPath: "/test/assets", writeDataPath: dataPath,
            platform: "darwin", startupOwnerPID: String(process.ppid),
        }));
        let terminate: (() => void) | undefined;
        vi.spyOn(process, "on").mockImplementation((event: string | symbol, listener: any) => {
            if (event === "SIGTERM") terminate = listener;
            return process;
        });
        const { runChobbyLoopbackHelper } = await import("@main/game/chobby-loopback-helper");
        const running = runChobbyLoopbackHelper();
        expect(terminate).toBeTypeOf("function");
        terminate!();
        await vi.advanceTimersByTimeAsync(0);
        ready!();
        await running;
        expect(app.exit).toHaveBeenCalledWith(0);
        expect(servers).toHaveLength(0);
        expect(files.has(connectionPath)).toBe(false);
        expect(vi.getTimerCount()).toBe(0);
    });

    it("does not exit main before the helper's pending startup write is cleaned up", async () => {
        vi.stubEnv("BAR_CHOBBY_LOOPBACK_HELPER_OPTIONS", JSON.stringify({
            engineVersion: "2026.07.04", assetsPath: "/test/assets", writeDataPath: dataPath,
            platform: "darwin", startupOwnerPID: String(process.ppid),
        }));
        let terminate: (() => void) | undefined;
        vi.spyOn(process, "on").mockImplementation((event: string | symbol, listener: any) => {
            if (event === "SIGTERM") terminate = listener;
            return process;
        });
        const write = fsPromises.writeFile.getMockImplementation();
        let finishWrite: (() => void) | undefined, finishDelete: (() => void) | undefined;
        fsPromises.writeFile.mockImplementationOnce((file: string, raw: string, options: unknown) => new Promise<void>((resolve) => {
            finishWrite = () => { void write(file, raw, options).then(resolve); };
        }));
        fsPromises.unlink.mockImplementationOnce((file: string) => new Promise<void>((resolve) => {
            finishDelete = () => { files.delete(file); resolve(); };
        }));
        const { runChobbyLoopbackHelper } = await import("@main/game/chobby-loopback-helper");
        const running = runChobbyLoopbackHelper().catch((err) => { app.exit(1); throw err; });
        const settled = running.then(() => undefined, () => undefined);
        await vi.advanceTimersByTimeAsync(0);
        expect(finishWrite).toBeTypeOf("function");
        terminate!();
        finishWrite!();
        await vi.advanceTimersByTimeAsync(0);
        expect(finishDelete).toBeTypeOf("function");
        expect(app.exit).not.toHaveBeenCalled();
        expect(files.has(connectionPath)).toBe(true);
        finishDelete!();
        await settled;
        await running;
        expect(files.has(connectionPath)).toBe(false);
        expect(app.exit).toHaveBeenCalledWith(0);
        expect(app.exit).not.toHaveBeenCalledWith(1);
    });

    it("still propagates a genuine helper startup failure to main", async () => {
        vi.stubEnv("BAR_CHOBBY_LOOPBACK_HELPER_OPTIONS", JSON.stringify({
            engineVersion: "2026.07.04", assetsPath: "/test/assets", writeDataPath: dataPath,
            platform: "darwin", startupOwnerPID: String(process.ppid),
        }));
        vi.spyOn(process, "on").mockReturnValue(process);
        fsPromises.writeFile.mockRejectedValueOnce(new Error("connection write failed"));
        const { runChobbyLoopbackHelper } = await import("@main/game/chobby-loopback-helper");
        const running = runChobbyLoopbackHelper().catch((err) => { app.exit(1); throw err; });
        await expect(running).rejects.toThrow("connection write failed");
        expect(app.exit).toHaveBeenCalledWith(1);
        expect(app.exit).not.toHaveBeenCalledWith(0);
    });
});
