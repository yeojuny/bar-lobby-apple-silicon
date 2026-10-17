// SPDX-FileCopyrightText: 2025 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import type { ChildProcess } from "child_process";
import { spawn } from "child_process";
import { randomUUID } from "crypto";
import { app, BrowserWindow, screen } from "electron";
import * as fs from "fs";
import { Signal } from "$/jaz-ts-utils/signal";
import * as path from "path";
import * as zlib from "zlib";

import { contentAPI } from "@main/content/content-api";
import { applyDefaultSpringsettings } from "@main/game/springsettings";
import { startScriptConverter } from "@main/utils/start-script-converter";
import { logger } from "@main/utils/logger";
import { WRITE_DATA_PATH, REPLAYS_PATH, LOGS_PATH, BUNDLED_ASSETS_PATH, getAssetsPath, getCaCertPath, getRapidIndexPath, getPackagePath, getPoolPath } from "@main/config/app";
import { BattleWithMetadata } from "@main/game/battle/battle-types";
import { Replay } from "@main/replays/replay";
import {
    getNativeEngineDataDirDiagnostics,
    getNativeEngineProcessEnv,
    getNativeEngineProcessEnvDiagnostics,
    MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV,
    MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV,
    MACOS_MINIMAL_FPS_WORKAROUND_REASON,
    MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE,
    MACOS_NATIVE_ENGINE_DATA_DIR_DIAGNOSTIC_PROBE,
    MACOS_NATIVE_ENGINE_ENV_DIAGNOSTIC_PROBE,
    resolveNativeEngineRunner,
    resolvePrDownloaderPath,
    prepareMacOSLuaUIOverlayForLaunch,
} from "@main/config/native-engine-runner";
import type { NativeEngineRunner } from "@main/config/native-engine-runner";
import { CHOBBY_MULTIPLAYER_GAME_RAPID_ALIAS, ChobbyMultiplayerProfile, resolveChobbyMultiplayerProfile } from "@main/game/chobby-multiplayer-profile";
import { ChobbyLauncherLoopback, CONNECTION_FILE_NAME } from "@main/game/chobby-launcher-loopback";
import { CHOBBY_LOOPBACK_HELPER_ARG, CHOBBY_LOOPBACK_HELPER_OPTIONS_ENV } from "@main/game/chobby-loopback-helper";
import { createEngineLobbyLogMirror } from "@main/game/engine-log-mirror";
import { createEngineStderrLog } from "@main/game/engine-stderr-log";
import { requireContentWritesOpen, shutdownContentWriters, waitForContentWriterClose, withContentWrite } from "@main/content/content-write-coordinator";
import { acquireChecksumHold } from "@main/utils/checksums";
import { prepareChobbyDisplaySettings } from "@main/game/chobby-display-settings";
import { settingsService } from "@main/services/settings.service";

const log = logger("main/game/game.ts");
const engineLogger = logger("[RECOIL ENGINE]", { separator: "\n", level: "info" });

export interface ScriptLaunchSettings {
    engineVersion: string;
    gameVersion: string;
    script: string;
}

export interface MultiplayerLaunchSettings {
    engineVersion: string;
    gameVersion: string;
    springString: string;
}

export interface ChobbyLaunchSettings {
    engineVersion?: string;
    menu?: string;
}

interface ResolvedChobbyLaunchSettings {
    engineVersion: string;
    menu?: string;
}

interface NativeEngineLaunchSettings {
    engineVersion: string;
    args: string[];
    resolveOnSpawn?: boolean;
    quitLobbyAfterSpawn?: boolean;
    envOverrides?: NodeJS.ProcessEnv;
    includeBundledAssetsInSpringDataDir?: boolean;
    includeBundledEngineSupportInSpringDataDir?: boolean;
    includeBundledMacOSLuaUIOverlayInSpringDataDir?: boolean;
    macOSLuaUIOverlayLane?: "bar-chobby" | "bar-lobby";
    onExit?: () => void;
    onDetachedSpawn?: (child: ChildProcess) => Promise<void>;
}

interface ChobbyLauncherConnectionFile {
    _sl_address?: string;
    _sl_port?: number;
    _sl_write_path?: string;
    _sl_helper_pid?: number;
    _sl_engine_pid?: number;
}

interface DetachedChobbyLauncherHelper {
    process: ChildProcess;
    connection: ChobbyLauncherConnectionFile;
}

const DEFAULT_CHOBBY_MENU = "rapid://byar-chobby:test";
const DEFAULT_CHOBBY_RAPID_TAG = "byar-chobby:test";
const CHOBBY_CONFIG_FILE_NAME = "chobby_config.json";
const CHOBBY_ENGINE_VERSION_ADDON_PATH = "luamenu/addons/engineversion.lua";
const CHOBBY_RAPID_REPO_HOST = "repos-cdn.beyondallreason.dev";
const CHOBBY_RAPID_REPO_NAME = "byar-chobby";
const CHOBBY_RAPID_TAG_RESOLUTION_ORDER = "repos-cdn.beyondallreason.dev";
const DEFAULT_CHOBBY_CONFIG = {
    server: {
        address: "server4.beyondallreason.info",
        port: 8200,
        protocol: "spring",
        serverName: "BAR",
    },
    game: "byar",
};

export class GameAPI {
    public onGameLaunched = new Signal<void>();
    public onGameClosed: Signal<number | null> = new Signal();
    public readonly startScriptName = "script.txt";

    protected gameProcess: ChildProcess | null = null;
    private nativeLaunchPending = false;
    private chobbyLaunchPending: Promise<void> | null = null;
    private chobbyLauncherLoopback: ChobbyLauncherLoopback | null = null;
    private detachedChobbyHelper: ChildProcess | null = null;

    public async launchBattle(battle: BattleWithMetadata): Promise<void> {
        const script = await startScriptConverter.generateScriptStr(battle);
        const scriptPath = path.join(WRITE_DATA_PATH, this.startScriptName);
        await fs.promises.writeFile(scriptPath, script);
        await this.launch({
            engineVersion: battle.battleOptions.engineVersion,
            gameVersion: battle.battleOptions.gameVersion,
            mapSpringName: battle.battleOptions.map?.springName,
            launchArg: scriptPath,
        });
    }

    public async launchReplay(replay: Replay) {
        return this.launch({
            engineVersion: replay.engineVersion,
            gameVersion: replay.gameVersion,
            mapSpringName: replay.mapSpringName,
            launchArg: replay.filePath ? replay.filePath : path.join(REPLAYS_PATH, replay.fileName),
        });
    }

    public async launchScript({ engineVersion, gameVersion, script }: ScriptLaunchSettings) {
        log.debug(`Launching game with script: ${script}`);
        const scriptGameVersion = script.match(/gametype\s*=\s*(.*);/)?.[1];
        const mapSpringName = script.match(/mapname\s*=\s*(.*);/)?.[1];
        if (!mapSpringName) {
            throw new Error("Could not parse map name from script");
        }
        const scriptPath = path.join(WRITE_DATA_PATH, this.startScriptName);
        await fs.promises.writeFile(scriptPath, script);
        await this.launch({
            engineVersion,
            gameVersion: scriptGameVersion || gameVersion, // using script's game version if available
            mapSpringName,
            launchArg: scriptPath,
        });
    }

    public async launchMultiplayer({ engineVersion, gameVersion, springString }: MultiplayerLaunchSettings) {
        return this.launch({
            engineVersion,
            gameVersion,
            launchArg: springString,
        });
    }

    public launchChobby(settings: ChobbyLaunchSettings = {}): Promise<void> {
        // Reserve the whole preparation before the first await. Native ownership
        // starts later, after config migration and content preparation already ran.
        if (this.chobbyLaunchPending) return this.chobbyLaunchPending;
        const launch = this.launchChobbyPrepared(settings);
        this.chobbyLaunchPending = launch;
        const settled = () => {
            if (this.chobbyLaunchPending === launch) this.chobbyLaunchPending = null;
        };
        void launch.then(settled, settled);
        return launch;
    }

    private async launchChobbyPrepared({ engineVersion, menu = DEFAULT_CHOBBY_MENU }: ChobbyLaunchSettings) {
        if (this.gameProcess || this.nativeLaunchPending || this.detachedChobbyHelper) throw new Error("An engine process is still owned by this launcher");
        const profile = await resolveChobbyMultiplayerProfile(engineVersion);
        log.info(
            `Launching Chobby multiplayer compatibility mode with engine: ${profile.engineVersion}, game: ${profile.gameVersion ?? profile.gameRapidAlias}, profileSource: ${profile.source}, menu: ${menu}`
        );
        await this.assertNativeRuntimeEngineVersionMatches(profile.engineVersion, "Chobby multiplayer");
        await this.ensureChobbyConfigFile();
        await this.ensureChobbySpringSettings();
        if (process.platform === "darwin") {
            await prepareChobbyDisplaySettings(WRITE_DATA_PATH, settingsService.getSettings().fullscreen);
        }
        await this.ensureChobbyMenuArchive({ engineVersion: profile.engineVersion, menu });
        await this.ensureChobbyMultiplayerGameContent(profile);
        await this.ensureChobbyEngineVersionAlias({ engineVersion: profile.engineVersion, menu });
        let detachedHelper: DetachedChobbyLauncherHelper | undefined;
        if (process.platform === "darwin") {
            detachedHelper = await this.prepareDetachedChobbyLauncherLoopback(profile.engineVersion);
        } else {
            await this.prepareChobbyLauncherLoopback(profile.engineVersion);
        }
        try {
            return await this.launchNativeEngine({
                engineVersion: profile.engineVersion,
                args: ["--write-dir", WRITE_DATA_PATH, "--isolation", "--menu", menu],
                resolveOnSpawn: true,
                quitLobbyAfterSpawn: process.platform === "darwin",
                includeBundledAssetsInSpringDataDir: false,
                includeBundledEngineSupportInSpringDataDir: true,
                // Renderer adaptations are immutable native sources; user widgets stay sandboxed.
                includeBundledMacOSLuaUIOverlayInSpringDataDir: false,
                macOSLuaUIOverlayLane: "bar-chobby",
                onDetachedSpawn: detachedHelper ? (child) => this.publishDetachedChobbyEngineOwner(detachedHelper!, child) : undefined,
                onExit: () => {
                    if (detachedHelper) this.stopDetachedChobbyHelper(detachedHelper.process);
                    else this.stopChobbyLauncherLoopback().catch((err: unknown) => log.warn(`Failed to stop Chobby launcher loopback: ${err instanceof Error ? err.message : String(err)}`));
                },
            });
        } catch (err) {
            if (detachedHelper) this.stopDetachedChobbyHelper(detachedHelper.process);
            throw err;
        }
    }

    private async prepareDetachedChobbyLauncherLoopback(engineVersion: string) {
        if (this.detachedChobbyHelper) throw new Error("A detached Chobby helper is still owned by this launcher");
        const connectionFilePath = path.join(WRITE_DATA_PATH, CONNECTION_FILE_NAME);
        await fs.promises.mkdir(WRITE_DATA_PATH, { recursive: true });
        await fs.promises.rm(connectionFilePath, { force: true });

        const helperOptions = {
            engineVersion,
            assetsPath: getAssetsPath(),
            ...(BUNDLED_ASSETS_PATH && { bundledAssetsPath: BUNDLED_ASSETS_PATH }),
            writeDataPath: WRITE_DATA_PATH,
            platform: process.platform,
            startupOwnerPID: String(process.pid),
        };
        const helperProcess = spawn(process.execPath, this.getChobbyLoopbackHelperArgs(), {
            detached: true,
            stdio: "ignore",
            env: {
                ...process.env,
                ...this.getMacOSLaunchDisplayEnv(),
                [CHOBBY_LOOPBACK_HELPER_OPTIONS_ENV]: JSON.stringify(helperOptions),
            },
        });
        this.detachedChobbyHelper = helperProcess;
        let startupError: Error | undefined;
        const forgetHelper = () => {
            if (this.detachedChobbyHelper === helperProcess) this.detachedChobbyHelper = null;
        };
        helperProcess.on("error", (err) => {
            startupError = err;
            if (!helperProcess.pid) forgetHelper();
            log.warn(`Detached Chobby helper process error: ${err.message}`);
        });
        helperProcess.once("exit", forgetHelper);
        helperProcess.once("close", forgetHelper);
        helperProcess.unref();
        log.info(`Spawned detached Chobby loopback helper pid=${helperProcess.pid ?? "<unknown>"}`);

        try {
            const connection = await this.waitForChobbyLauncherConnection(connectionFilePath, helperProcess, () => startupError);
            log.info(`Detached Chobby loopback helper ready at ${connection._sl_address}:${connection._sl_port}, pid=${connection._sl_helper_pid}`);
            return { process: helperProcess, connection };
        } catch (err) {
            this.stopDetachedChobbyHelper(helperProcess);
            throw err;
        }
    }

    private stopDetachedChobbyHelper(helper: ChildProcess) {
        if (!helper.pid || helper.exitCode !== null || helper.signalCode !== null || helper.killed) return;
        try {
            helper.kill("SIGTERM");
        } catch (err) {
            log.warn(`Failed to request owned Chobby helper shutdown: ${err instanceof Error ? err.message : String(err)}`);
        }
        // A sent signal is not an observed exit; keep ownership until exit/close.
    }

    private async publishDetachedChobbyEngineOwner(helper: DetachedChobbyLauncherHelper, child: ChildProcess) {
        if (!child.pid || child.pid === helper.process.pid || child.pid === process.pid || helper.process !== this.detachedChobbyHelper) {
            throw new Error("Invalid detached Chobby native process ownership");
        }
        const connectionFilePath = path.join(WRITE_DATA_PATH, CONNECTION_FILE_NAME);
        const record = JSON.parse(await fs.promises.readFile(connectionFilePath, "utf-8")) as ChobbyLauncherConnectionFile;
        if (!record || record._sl_address !== "127.0.0.1" || record._sl_helper_pid !== helper.process.pid
            || record._sl_port !== helper.connection._sl_port || record._sl_write_path !== WRITE_DATA_PATH) {
            throw new Error("Detached Chobby helper connection ownership changed before native handoff");
        }
        const temporaryPath = path.join(WRITE_DATA_PATH, `.sl-connection-${randomUUID()}.tmp`);
        let created = false;
        try {
            await fs.promises.writeFile(temporaryPath, `${JSON.stringify({ ...record, _sl_engine_pid: child.pid }, null, 2)}\n`, { flag: "wx", mode: 0o600 });
            created = true;
            await fs.promises.rename(temporaryPath, connectionFilePath);
        } finally {
            if (created) await fs.promises.rm(temporaryPath, { force: true });
        }
        if (helper.process !== this.detachedChobbyHelper || helper.process.exitCode !== null
            || helper.process.signalCode !== null || helper.process.killed) {
            throw new Error("Detached Chobby helper exited before native handoff");
        }
    }

    private getChobbyLoopbackHelperArgs() {
        const electronProcess = process as NodeJS.Process & { defaultApp?: boolean };
        if (electronProcess.defaultApp && process.argv[1]) {
            return [process.argv[1], CHOBBY_LOOPBACK_HELPER_ARG];
        }

        return [CHOBBY_LOOPBACK_HELPER_ARG];
    }

    private async waitForChobbyLauncherConnection(connectionFilePath: string, helper: ChildProcess, startupError: () => Error | undefined) {
        const timeoutMs = 10_000;
        const startTime = Date.now();
        let lastError = "connection file has not been written";

        while (Date.now() - startTime < timeoutMs) {
            const error = startupError();
            if (error) throw error;
            if (helper.exitCode !== null || helper.signalCode !== null) throw new Error("Chobby loopback helper exited before readiness");
            try {
                const connection = JSON.parse(await fs.promises.readFile(connectionFilePath, "utf-8")) as ChobbyLauncherConnectionFile;
                // The helper writes this record only after server.listen has
                // completed. A TCP readiness probe would look like a menu client.
                if (helper.pid && connection?._sl_helper_pid === helper.pid && connection._sl_address === "127.0.0.1"
                    && typeof connection._sl_port === "number" && Number.isInteger(connection._sl_port) && connection._sl_port > 0 && connection._sl_port <= 65535
                    && connection._sl_write_path === WRITE_DATA_PATH) {
                    return connection;
                }
                lastError = `connection file is incomplete: ${connectionFilePath}`;
            } catch (err) {
                lastError = err instanceof Error ? err.message : String(err);
            }
            await new Promise((resolve) => setTimeout(resolve, 100));
        }

        throw new Error(`Timed out waiting for Chobby loopback helper: ${lastError}`);
    }

    private async prepareChobbyLauncherLoopback(engineVersion: string) {
        await this.stopChobbyLauncherLoopback();
        this.chobbyLauncherLoopback = new ChobbyLauncherLoopback({
            engineVersion,
            assetsPath: getAssetsPath(),
            bundledAssetsPath: BUNDLED_ASSETS_PATH,
            writeDataPath: WRITE_DATA_PATH,
            platform: process.platform,
        });
        const connection = await this.chobbyLauncherLoopback.start();
        log.info(`Prepared Chobby launcher loopback connection file: ${connection.connectionFilePath}`);
    }

    private async stopChobbyLauncherLoopback() {
        const loopback = this.chobbyLauncherLoopback;
        this.chobbyLauncherLoopback = null;
        await loopback?.close();
    }

    private async ensureChobbyConfigFile() {
        const configPath = path.join(WRITE_DATA_PATH, CHOBBY_CONFIG_FILE_NAME);
        await fs.promises.mkdir(WRITE_DATA_PATH, { recursive: true });

        try {
            const existingConfig = JSON.parse(await fs.promises.readFile(configPath, "utf-8"));
            if (existingConfig?.server?.address && existingConfig?.server?.port && existingConfig?.server?.protocol && existingConfig?.game) {
                log.info(`Using existing Chobby config: ${configPath}`);
                return;
            }
        } catch {
            // Missing or malformed config is replaced with the BAR production lobby defaults.
        }

        await fs.promises.writeFile(configPath, `${JSON.stringify(DEFAULT_CHOBBY_CONFIG, null, 2)}\n`, "utf-8");
        log.info(`Wrote Chobby config: ${configPath}`);
    }

    private async ensureChobbyEngineVersionAlias({ engineVersion, menu = DEFAULT_CHOBBY_MENU }: ResolvedChobbyLaunchSettings) {
        if (process.platform !== "darwin") {
            return;
        }

        const rapidTag = menu === DEFAULT_CHOBBY_MENU ? DEFAULT_CHOBBY_RAPID_TAG : menu.replace(/^rapid:\/\//, "");
        const packageMd5 = await this.getChobbyPackageMd5(rapidTag);
        const addonEntry = await this.getSdpEntry(path.join(getPackagePath(), `${packageMd5}.sdp`), CHOBBY_ENGINE_VERSION_ADDON_PATH);
        const addonPath = path.join(getPoolPath(), addonEntry.md5.slice(0, 2), `${addonEntry.md5.slice(2)}.gz`);
        const advertisedEngineVersion = engineVersion;
        const addonText = this.createChobbyEngineVersionAliasAddon(advertisedEngineVersion, addonEntry.filesizeBytes);

        await fs.promises.writeFile(addonPath, zlib.gzipSync(Buffer.from(addonText, "utf-8")));
        log.info(`Patched Chobby engine version alias ${CHOBBY_ENGINE_VERSION_ADDON_PATH} to advertise ${advertisedEngineVersion} for installed engine ${engineVersion}`);
    }

    private async assertNativeRuntimeEngineVersionMatches(engineVersion: string, launchContext = "macOS native engine launch") {
        let runtimeEngineVersion: string;
        try {
            runtimeEngineVersion = await this.getNativeEngineRuntimeVersion(engineVersion);
        } catch (err) {
            throw new Error(
                [
                    `${launchContext} requires native macOS engine ${engineVersion}.`,
                    "Bundle or install the matching macOS engine artifact before launching.",
                    `Details: ${err instanceof Error ? err.message : String(err)}`,
                ].join(" ")
            );
        }

        if (runtimeEngineVersion !== engineVersion) {
            throw new Error(
                [
                    `${launchContext} requires native macOS engine ${engineVersion}, but the installed runtime reports ${runtimeEngineVersion}.`,
                    "Do not alias a newer or older runtime for accepted compatibility; build or install the matching official engine tag.",
                ].join(" ")
            );
        }
    }

    private async getNativeEngineRuntimeVersion(engineVersion: string) {
        const runner = resolveNativeEngineRunner({
            engineVersion,
            assetsPath: getAssetsPath(),
            bundledAssetsPath: BUNDLED_ASSETS_PATH,
            platform: process.platform,
        });
        const versionOutput = await this.readNativeEngineVersion(runner);
        const syncVersion = versionOutput.trim();
        if (syncVersion && !/[\r\n]/.test(syncVersion)) return syncVersion;
        throw new Error(`Could not parse native engine sync version from '${versionOutput.trim()}'`);
    }

    private async readNativeEngineVersion(runner: NativeEngineRunner) {
        return new Promise<string>((resolve, reject) => {
            const versionProcess = spawn(runner.spawnCommand, ["--sync-version"], {
                cwd: runner.enginePath,
                stdio: "pipe",
            });
            const chunks: Buffer[] = [];
            versionProcess.stdout?.on("data", (data: Buffer) => chunks.push(data));
            versionProcess.stderr?.on("data", (data: Buffer) => chunks.push(data));
            versionProcess.on("error", reject);
            versionProcess.on("exit", (code, signal) => {
                const output = Buffer.concat(chunks).toString("utf-8");
                if (code === 0) {
                    resolve(output);
                    return;
                }

                reject(new Error(`Failed to read native engine version, code ${code}, signal ${signal}: ${output.trim()}`));
            });
        });
    }

    private async ensureChobbySpringSettings() {
        const settingsPath = path.join(WRITE_DATA_PATH, "springsettings.cfg");
        await fs.promises.mkdir(WRITE_DATA_PATH, { recursive: true });

        let existingSettings = "";
        try {
            existingSettings = await fs.promises.readFile(settingsPath, "utf-8");
        } catch {
            // The engine will create this file too; we only need it early for Chobby's rapid repo lookup.
        }

        const nextSettings = this.upsertSpringSetting(existingSettings, "RapidTagResolutionOrder", CHOBBY_RAPID_TAG_RESOLUTION_ORDER);
        if (nextSettings !== existingSettings) {
            await fs.promises.writeFile(settingsPath, nextSettings, "utf-8");
            log.info(`Updated Chobby spring settings: ${settingsPath}`);
        }
    }

    private upsertSpringSetting(settings: string, key: string, value: string) {
        const lines = settings.trimEnd() ? settings.trimEnd().split(/\r?\n/) : [];
        let found = false;
        const nextLines = lines.map((line) => {
            const match = line.match(/^(\s*)([^#=]+?)(\s*=\s*)(.*)$/);
            if (!match || match[2].trim() !== key) {
                return line;
            }
            found = true;
            return `${match[1]}${key}${match[3]}${value}`;
        });

        if (!found) {
            nextLines.push(`${key} = ${value}`);
        }

        return `${nextLines.join("\n")}\n`;
    }

    private async getChobbyPackageMd5(rapidTag: string) {
        const versionsPath = path.join(getRapidIndexPath(), CHOBBY_RAPID_REPO_HOST, CHOBBY_RAPID_REPO_NAME, "versions.gz");
        const versions = zlib.gunzipSync(await fs.promises.readFile(versionsPath)).toString("utf-8");
        for (const versionLine of versions.trim().split("\n")) {
            const [alias, packageMd5] = versionLine.split(",");
            if (alias === rapidTag && packageMd5) {
                return packageMd5;
            }
        }
        throw new Error(`Could not resolve Chobby rapid tag: ${rapidTag}`);
    }

    private async getSdpEntry(sdpFilePath: string, targetFileName: string) {
        const sdpFile = zlib.gunzipSync(await fs.promises.readFile(sdpFilePath));
        const normalizedTargetFileName = targetFileName.toLowerCase();
        let offset = 0;
        while (offset < sdpFile.length) {
            const fileNameLength = sdpFile.readUInt8(offset);
            offset += 1;
            const fileName = sdpFile.subarray(offset, offset + fileNameLength).toString("utf-8");
            offset += fileNameLength;
            const md5 = sdpFile.subarray(offset, offset + 16).toString("hex");
            offset += 16;
            offset += 4;
            const filesizeBytes = sdpFile.readUInt32BE(offset);
            offset += 4;

            if (fileName === targetFileName || fileName.toLowerCase() === normalizedTargetFileName) {
                return { fileName, md5, filesizeBytes };
            }
        }
        throw new Error(`Could not find ${targetFileName} in ${sdpFilePath}`);
    }

    private createChobbyEngineVersionAliasAddon(engineVersion: string, filesizeBytes: number) {
        const content = [
            "Spring.Utilities = Spring.Utilities or {}",
            "",
            "function Spring.Utilities.GetEngineVersion()",
            `\treturn "${this.escapeLuaString(engineVersion)}"`,
            "end",
            "",
            "-- macOS BAR lobby engine id compatibility alias.",
            "",
        ].join("\n");
        const contentBytes = Buffer.byteLength(content);
        if (contentBytes > filesizeBytes) {
            throw new Error(`Chobby engine version alias is too large: ${contentBytes} > ${filesizeBytes}`);
        }
        return `${content}${" ".repeat(filesizeBytes - contentBytes)}`;
    }

    private escapeLuaString(value: string) {
        return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    }

    private async ensureChobbyMenuArchive({ engineVersion, menu = DEFAULT_CHOBBY_MENU }: ResolvedChobbyLaunchSettings) {
        const rapidTag = menu === DEFAULT_CHOBBY_MENU ? DEFAULT_CHOBBY_RAPID_TAG : menu.replace(/^rapid:\/\//, "");
        const prBinaryPath = resolvePrDownloaderPath({
            engineVersion,
            assetsPath: getAssetsPath(),
            bundledAssetsPath: BUNDLED_ASSETS_PATH,
            platform: process.platform,
        });
        const caCertPath = getCaCertPath();

        await fs.promises.mkdir(getAssetsPath(), { recursive: true });
        log.info(`Ensuring Chobby archive is available: ${rapidTag}`);

        await withContentWrite(getAssetsPath(), (assetsPath) => new Promise<void>((resolve, reject) => {
            let lastProgressLogTime = 0;
            let lastProgressMessage = "";
            const prdProcess = spawn(`${prBinaryPath}`, ["--filesystem-writepath", assetsPath, "--download-game", rapidTag], {
                env: {
                    ...process.env,
                    PRD_RAPID_USE_STREAMER: "false",
                    PRD_RAPID_REPO_MASTER: "https://repos-cdn.beyondallreason.dev/repos.gz",
                    PRD_HTTP_SEARCH_URL: "https://files-cdn.beyondallreason.dev/find",
                    ...(caCertPath && !process.env.PRD_SSL_CERT_FILE && { PRD_SSL_CERT_FILE: caCertPath }),
                },
            });
            const closed = waitForContentWriterClose(prdProcess);
            prdProcess.stdout?.on("data", (data: Buffer) => {
                for (const line of data
                    .toString()
                    .split(/\r?\n|\r/)
                    .filter(Boolean)) {
                    if (line.startsWith("[Progress]")) {
                        lastProgressMessage = line;
                        const now = Date.now();
                        if (now - lastProgressLogTime >= 5000) {
                            lastProgressLogTime = now;
                            log.info(`[CHOBBY PR-DOWNLOADER] ${line}`);
                        }
                        continue;
                    }
                    log.info(`[CHOBBY PR-DOWNLOADER] ${line}`);
                }
            });
            prdProcess.stderr?.on("data", (data: Buffer) => log.error(`[CHOBBY PR-DOWNLOADER] ${data.toString().trim()}`));
            closed.then(({ code, signal }) => {
                if (code === 0) {
                    if (lastProgressMessage) {
                        log.info(`[CHOBBY PR-DOWNLOADER] ${lastProgressMessage}`);
                    }
                    resolve();
                    return;
                }

                reject(new Error(`Chobby archive download failed with code ${code}, signal ${signal}`));
            }, reject).catch(reject);
        }));
    }

    private async ensureChobbyMultiplayerGameContent(profile: ChobbyMultiplayerProfile) {
        const gameTarget = profile.gameRapidAlias || CHOBBY_MULTIPLAYER_GAME_RAPID_ALIAS;
        log.info(`Ensuring Chobby multiplayer game content is available: ${profile.gameVersion ?? gameTarget}`);
        await this.ensureChobbyMenuArchive({ engineVersion: profile.engineVersion, menu: gameTarget });
        log.info("Chobby multiplayer keeps official rapid game content unchanged; macOS graphics fixes must come from the engine/runtime or upstream-compatible content.");
    }

    public async launch({ engineVersion, gameVersion, mapSpringName, launchArg }: { engineVersion?: string; gameVersion?: string; mapSpringName?: string; launchArg?: string }): Promise<void> {
        if (!engineVersion || !gameVersion || !launchArg) {
            throw new Error("Engine Version, Game Version and launch Arguments need to be specified");
        }

        log.info(`Launching game with engine: ${engineVersion}, game: ${gameVersion}`);

        // Playing something is the clearest sign it is still wanted, and it is the one thing every
        // launch path has in common.
        void contentAPI.markUsed([{ type: "engine", id: engineVersion }, { type: "game", id: gameVersion }, ...(mapSpringName ? [{ type: "map" as const, id: mapSpringName }] : [])]);
        await this.fetchMissingContent(engineVersion, gameVersion); // TODO preload anything needed through the UI before launching. Remove this step
        return this.launchNativeEngine({
            engineVersion,
            args: ["--write-dir", WRITE_DATA_PATH, "--isolation", launchArg],
            includeBundledAssetsInSpringDataDir: process.platform === "darwin" ? false : undefined,
            includeBundledEngineSupportInSpringDataDir: process.platform === "darwin" ? true : undefined,
            includeBundledMacOSLuaUIOverlayInSpringDataDir: false,
            macOSLuaUIOverlayLane: "bar-lobby",
        });
    }

    private async launchNativeEngine(settings: NativeEngineLaunchSettings): Promise<void> {
        if (process.platform !== "darwin") return this.launchNativeEngineHeld(settings, () => undefined);
        if (this.gameProcess || this.nativeLaunchPending) throw new Error("An engine process is still owned by this launcher");
        this.nativeLaunchPending = true;
        let release: (() => void) | undefined;
        let childOwnsHold = false;
        try {
            release = await acquireChecksumHold();
            return await this.launchNativeEngineHeld(settings, (child) => {
                childOwnsHold = true;
                child.once("close", release!);
            });
        } finally {
            this.nativeLaunchPending = false;
            // A successful load/handoff resolves before native teardown. The
            // child retains the hold through close, including Kill stage 8.
            if (!childOwnsHold) release?.();
        }
    }

    private getMacOSLaunchDisplayEnv(): NodeJS.ProcessEnv {
        if (process.platform !== "darwin") return {};
        const id = Number(process.env.MAIN_WINDOW_ID);
        const window = Number.isSafeInteger(id) && id > 0 ? BrowserWindow.fromId(id) : null;
        if (!window || window.isDestroyed()) return {};
        // Electron DIP and SDL Cocoa desktop bounds share logical coordinates.
        // Pass the target display, never a fixed render resolution or workarea.
        const { x, y, width, height } = screen.getDisplayMatching(window.getBounds()).bounds;
        return { BAR_MACOS_TARGET_DISPLAY: [x, y, width, height].join(",") };
    }

    private async launchNativeEngineHeld({
        engineVersion,
        args,
        resolveOnSpawn = false,
        quitLobbyAfterSpawn = false,
        envOverrides,
        includeBundledAssetsInSpringDataDir,
        includeBundledEngineSupportInSpringDataDir,
        includeBundledMacOSLuaUIOverlayInSpringDataDir,
        macOSLuaUIOverlayLane,
        onExit,
        onDetachedSpawn,
    }: NativeEngineLaunchSettings, onSpawned: (child: ChildProcess) => void): Promise<void> {
        if (this.gameProcess) throw new Error("An engine process is still owned by this launcher");
        if (process.platform === "darwin") {
            await this.assertNativeRuntimeEngineVersionMatches(engineVersion);
        }
        // Keep exact legacy-file quarantine even though bundled code is no longer a RAW data directory.
        if (process.platform === "darwin" && (includeBundledMacOSLuaUIOverlayInSpringDataDir || macOSLuaUIOverlayLane)) {
            if (!macOSLuaUIOverlayLane) {
                throw new Error("Missing macOS LuaUI overlay lane for native engine launch");
            }
            const overlayResult = await prepareMacOSLuaUIOverlayForLaunch({
                bundledAssetsPath: BUNDLED_ASSETS_PATH,
                writeDataPath: WRITE_DATA_PATH,
                lane: macOSLuaUIOverlayLane,
                platform: process.platform,
            });
            if (overlayResult.prepared) {
                log.info(
                    `Prepared ${macOSLuaUIOverlayLane} macOS LuaUI overlay: ${overlayResult.sourcePath}; quarantined=${overlayResult.quarantinedFiles?.length ?? 0}; preserved=${overlayResult.preservedFiles?.length ?? 0}`
                );
            } else {
                log.debug(`Skipped ${macOSLuaUIOverlayLane} macOS LuaUI overlay preparation: ${overlayResult.reason ?? "unknown"}`);
            }
        }
        applyDefaultSpringsettings();

        const runner = resolveNativeEngineRunner({
            engineVersion,
            assetsPath: getAssetsPath(),
            bundledAssetsPath: BUNDLED_ASSETS_PATH,
            platform: process.platform,
        });
        const enginePath = runner.enginePath.replaceAll("\\", "/");
        const engineEnv = getNativeEngineProcessEnv({
            assetsPath: getAssetsPath(),
            bundledAssetsPath: BUNDLED_ASSETS_PATH,
            enginePath,
            includeBundledAssetsInSpringDataDir,
            includeBundledEngineSupportInSpringDataDir,
            includeBundledMacOSLuaUIOverlayInSpringDataDir,
            macOSLuaUIOverlayLane,
            writeDataPath: WRITE_DATA_PATH,
            platform: process.platform,
            baseEnv: { ...process.env, ...this.getMacOSLaunchDisplayEnv(), ...envOverrides },
        });
        log.debug(`Running binary: ${path.join(enginePath, runner.binaryFileName)}, args: ${args}`);
        // macOS-port diagnostic probe: remove or demote after Thread 07 runtime closure accepts the final app-local environment contract.
        if (process.platform === "darwin") {
            log.info(`${MACOS_NATIVE_ENGINE_ENV_DIAGNOSTIC_PROBE}: ${JSON.stringify(getNativeEngineProcessEnvDiagnostics(engineEnv))}`);
            log.info(`${MACOS_NATIVE_ENGINE_DATA_DIR_DIAGNOSTIC_PROBE}: ${JSON.stringify(getNativeEngineDataDirDiagnostics(engineEnv))}`);
            if (engineEnv.ZINK_DEBUG === MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE) {
                const workaroundOptInValue = engineEnv[MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV] ?? "<unset>";
                const workaroundOptOutValue = engineEnv[MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV] ?? "<unset>";
                log.info(
                    [
                        "MACOS_RUNTIME_WORKAROUND",
                        `reason=${MACOS_MINIMAL_FPS_WORKAROUND_REASON}`,
                        `ZINK_DEBUG=${MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE}`,
                        `${MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV}=${workaroundOptInValue}`,
                        `${MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV}=${workaroundOptOutValue}`,
                        "workaround_active=true",
                        "production_acceptance=false",
                        "track_owner=Thread07-runtime-backend",
                    ].join(" ")
                );
            }
        }

        return new Promise<void>((resolve, reject) => {
            let driverLog: ReturnType<typeof createEngineStderrLog> | undefined;
            try {
                const engineLogMirror = createEngineLobbyLogMirror(engineLogger, path.join(WRITE_DATA_PATH, "infolog.txt"));
                let exitHookCalled = false;
                const runExitHook = () => {
                    if (exitHookCalled) {
                        return;
                    }
                    exitHookCalled = true;
                    onExit?.();
                };
                if (this.gameProcess) throw new Error("An engine process is still owned by this launcher");
                if (process.platform === "darwin") requireContentWritesOpen();
                this.gameProcess = spawn(runner.spawnCommand, args, {
                    cwd: enginePath,
                    stdio: quitLobbyAfterSpawn ? "ignore" : "pipe",
                    detached: true,
                    env: engineEnv,
                });
                onSpawned(this.gameProcess);
                if (quitLobbyAfterSpawn) {
                    const ownedProcess = this.gameProcess;
                    let handedOff = false;
                    log.info("Engine stderr capture unavailable for detached Chobby stdio policy; do not interpret the absence of lobby driver errors as a clean GPU result.");
                    this.gameProcess.addListener("error", (err) => {
                        log.error(err);
                        runExitHook();
                        if (!ownedProcess.pid && this.gameProcess === ownedProcess) this.gameProcess = null;
                        reject(err);
                    });
                    ownedProcess.once("exit", () => {
                        runExitHook();
                        if (!handedOff && this.gameProcess === ownedProcess) this.gameProcess = null;
                    });
                    ownedProcess.addListener("spawn", () => {
                        void (async () => {
                            try {
                                await onDetachedSpawn?.(ownedProcess);
                                if (ownedProcess.exitCode !== null || ownedProcess.signalCode !== null) throw new Error("Chobby native process exited before ownership handoff");
                                log.info("Chobby spawned; exiting BAR lobby process by policy.");
                                if (process.platform === "darwin") {
                                    app.dock?.hide();
                                    app.hide();
                                }
                                ownedProcess.unref();
                                handedOff = true;
                                this.onGameLaunched.dispatch();
                                resolve();
                                this.gameProcess = null;
                            } catch (err) {
                                if (ownedProcess.pid && ownedProcess.exitCode === null && ownedProcess.signalCode === null && !ownedProcess.killed) {
                                    try { ownedProcess.kill("SIGTERM"); }
                                    catch (killError) { log.warn(`Failed to request owned Chobby native shutdown: ${killError instanceof Error ? killError.message : String(killError)}`); }
                                }
                                runExitHook();
                                reject(err);
                                return;
                            }
                            // Ownership has transferred. A parent download drain
                            // failure must not roll back the detached menu/helper.
                            shutdownContentWriters().then(() => {
                                setImmediate(() => app.exit(0));
                            }).catch((error: unknown) => {
                                log.error(`Could not stop parent content writers after Chobby handoff: ${String(error)}`);
                            });
                        })();
                    });
                    log.debug(`Game process PID: ${this.gameProcess.pid}`);
                    return;
                }
                if (!this.gameProcess.stdout || !this.gameProcess.stderr) throw new Error("failed to access game process stream");
                driverLog = createEngineStderrLog(path.join(LOGS_PATH, "engine-diagnostics"), {
                    engineVersion, enginePath, pid: this.gameProcess.pid, appPath: app.getAppPath(),
                    icd: engineEnv.VK_DRIVER_FILES ?? engineEnv.VK_ICD_FILENAMES,
                    zinkDebug: engineEnv.ZINK_DEBUG,
                    asyncWaitOptOut: engineEnv.BAR_ZINK_MVK_DISABLE_ASYNC_WAIT,
                    metalShaderValidation: engineEnv.MTL_SHADER_VALIDATION,
                }, (message) => log.warn(message));
                if (driverLog.path) log.info(`Bounded engine stderr capture: ${driverLog.path}`);
                let isGameRunning = false;
                this.gameProcess.stdout.on("data", (data) => {
                    engineLogMirror.write(data, "info");
                    // Check if the game has started
                    // This is a heuristic based on the log output, as the engine does not provide a specific event for game launch
                    //TODO replace this with some ipc event from the engine when it is available
                    if (!isGameRunning && data.toString().includes("[Game::Load]")) {
                        isGameRunning = true;
                        this.onGameLaunched.dispatch();
                        resolve();
                    }
                    //TODO this is a workaround for the fact that the engine does not exit right away when the game is closed (can take a few seconds on Linux)
                    // See https://github.com/beyond-all-reason/RecoilEngine/issues/2450
                    if (isGameRunning && data.toString().includes("[SpringApp::Kill][8]")) {
                        log.info("Game process requested to close");
                        this.gameProcess = null;
                        isGameRunning = false;
                        this.onGameClosed.dispatch(null);
                    }
                });
                this.gameProcess.stderr.on("data", (data) => {
                    driverLog?.write(data);
                    engineLogMirror.write(data, "error");
                });
                this.gameProcess.addListener("error", (err) => {
                    log.error(err);
                    runExitHook();
                });
                this.gameProcess.addListener("exit", (code) => {
                    runExitHook();
                    if (code !== 0) {
                        log.error(`Game process exited with code: ${code}`);
                        reject(new Error(`Game process exited with code: ${code}`));
                    } else {
                        log.info(`Game process exited with code: ${code}`);
                    }
                    this.gameProcess = null;
                    if (isGameRunning) this.onGameClosed.dispatch(code); // Dispatch if the game closed unexpectedly
                });
                this.gameProcess.addListener("spawn", () => {
                    log.debug(`Game process spawned successfully`);
                    if (resolveOnSpawn) {
                        isGameRunning = true;
                        this.onGameLaunched.dispatch();
                        resolve();
                    }
                });
                this.gameProcess.addListener("close", (exitCode) => {
                    driverLog?.close();
                    engineLogMirror.summarize();
                    log.debug(`Game process closed with exit code: ${exitCode}`);
                });
                log.debug(`Game process PID: ${this.gameProcess.pid}`);
            } catch (err) {
                driverLog?.close();
                log.error(`Failed to launch game: ${err}`);
                reject(err);
            }
        });
    }

    public isGameRunning() {
        return this.gameProcess !== null;
    }

    //TODO not handling maps, not sure if needed if we always come from the lobby's UI
    protected async fetchMissingContent(engineVersion?: string, gameVersion?: string) {
        if (!engineVersion || !gameVersion) {
            throw new Error("Engine Version and Game Version need to be specified");
        }

        await contentAPI.ensure([
            { type: "engine", id: engineVersion },
            { type: "game", id: gameVersion },
        ]);
    }
}

export const gameAPI = new GameAPI();
