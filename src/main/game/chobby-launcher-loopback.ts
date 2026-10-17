// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import type { ChildProcess } from "child_process";
import { spawn } from "child_process";
import { shell } from "electron";
import * as fs from "fs";
import * as http from "http";
import * as https from "https";
import type { AddressInfo, Server, Socket } from "net";
import * as net from "net";
import * as path from "path";

import { extract7z } from "@main/utils/extract-7z";
import { logger } from "@main/utils/logger";
import { getCaCertPath } from "@main/config/app";
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

const log = logger("main/game/chobby-launcher-loopback.ts");

const LOOPBACK_HOST = "127.0.0.1";
export const CONNECTION_FILE_NAME = "sl-connection.json";
const RESOURCE_DOWNLOAD_DIR_NAME = "chobby-resource-downloads";
const PRD_RAPID_REPO_MASTER = "https://repos-cdn.beyondallreason.dev/repos.gz";
const PRD_HTTP_SEARCH_URL = "https://files-cdn.beyondallreason.dev/find";
const MAX_HTTP_REDIRECTS = 8;

export interface ChobbyLauncherLoopbackOptions {
    engineVersion: string;
    assetsPath: string;
    bundledAssetsPath?: string;
    writeDataPath: string;
    platform: NodeJS.Platform;
    idleShutdownDelayMs?: number;
    onIdle?: () => void;
    startupOwnerPID?: number;
}

export interface ChobbyLauncherConnection {
    host: string;
    port: number;
    writePath: string;
    connectionFilePath: string;
}

interface ChobbyConnectorMessage {
    name?: string;
    command?: unknown;
}

interface ChobbyDownloadCommand {
    name?: string;
    type?: string;
    resource?: ChobbyResourceDownload;
}

interface ChobbyResourceDownload {
    url?: string;
    destination?: string;
    extract?: boolean;
    optional?: boolean;
}

interface ChobbyStartNewSpringCommand {
    StartScriptContent?: string;
    StartDemoName?: string;
    Engine?: string;
    SpringSettings?: string;
}

type DownloadProgressListener = (downloadedBytes: number, totalBytes: number) => void;

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null;
}

function asString(value: unknown): string | undefined {
    return typeof value === "string" && value.trim() ? value : undefined;
}

function asBoolean(value: unknown): boolean | undefined {
    return typeof value === "boolean" ? value : undefined;
}

function parseDownloadCommand(command: unknown): ChobbyDownloadCommand {
    if (!isRecord(command)) {
        return {};
    }

    const resource = isRecord(command.resource)
        ? {
              url: asString(command.resource.url),
              destination: asString(command.resource.destination),
              extract: asBoolean(command.resource.extract),
              optional: asBoolean(command.resource.optional),
          }
        : undefined;

    return {
        name: asString(command.name),
        type: asString(command.type),
        resource,
    };
}

function parseStartNewSpringCommand(command: unknown): ChobbyStartNewSpringCommand {
    if (!isRecord(command)) {
        return {};
    }

    return {
        StartScriptContent: asString(command.StartScriptContent),
        StartDemoName: asString(command.StartDemoName),
        Engine: asString(command.Engine),
        SpringSettings: asString(command.SpringSettings),
    };
}

function getPrDownloaderDownloadArg(type: string) {
    switch (type.toLowerCase()) {
        case "game":
        case "rapid":
            return "--download-game";
        case "map":
            return "--download-map";
        case "engine":
            return "--download-engine";
        default:
            return undefined;
    }
}

function parsePrDownloaderProgress(line: string) {
    const percentMatch = line.match(/\[Progress\]\s+([0-9]+(?:\.[0-9]+)?)%/);
    const countMatch = line.match(/([0-9]+(?:\.[0-9]+)?)\/([0-9]+(?:\.[0-9]+)?)\s*$/);
    const progress = percentMatch ? Number(percentMatch[1]) / 100 : countMatch ? Number(countMatch[1]) / Number(countMatch[2]) : 0;
    const total = countMatch ? Number(countMatch[2]) : 1;

    return {
        progress: Number.isFinite(progress) ? Math.max(0, Math.min(1, progress)) : 0,
        total: Number.isFinite(total) ? total : 1,
    };
}

function safeDownloadFileName(url: string, fallbackName: string) {
    try {
        const basename = path.basename(new URL(url).pathname);
        if (basename) {
            return basename.replace(/[^A-Za-z0-9._-]/g, "_");
        }
    } catch {
        // Fall back to the caller-provided name below.
    }

    return fallbackName.replace(/[^A-Za-z0-9._-]/g, "_") || "download";
}

export class ChobbyLauncherLoopback {
    private readonly options: ChobbyLauncherLoopbackOptions;
    private server: Server | null = null;
    private readonly clients = new Set<Socket>();
    private readonly childProcesses = new Set<ChildProcess>();
    private readonly prDownloaderDownloads = new Map<string, Promise<boolean>>();
    private idleShutdownTimer: ReturnType<typeof setTimeout> | null = null;
    private startupOwnerTimer: ReturnType<typeof setTimeout> | null = null;
    private startupNativePID: number | undefined;
    private hasConnectedClient = false;
    private generation = 0;
    private connection: ChobbyLauncherConnection | null = null;
    private closingPromise: Promise<void> | null = null;
    private pendingConnectionWrite: Promise<ChobbyLauncherConnection> | null = null;

    public constructor(options: ChobbyLauncherLoopbackOptions) {
        this.options = options;
    }

    public async start(): Promise<ChobbyLauncherConnection> {
        await this.close();
        const generation = ++this.generation;
        this.hasConnectedClient = false;
        this.startupNativePID = undefined;
        const server = net.createServer((socket) => this.handleConnection(socket, generation));
        this.server = server;
        await new Promise<void>((resolve, reject) => {
            const onError = (err: Error) => {
                server.off("listening", onListening);
                reject(err);
            };
            const onListening = () => {
                server.off("error", onError);
                resolve();
            };

            server.once("error", onError);
            server.once("listening", onListening);
            server.listen(0, LOOPBACK_HOST);
        });

        if (generation !== this.generation || this.server !== server) throw new Error("Chobby loopback stopped during startup");
        const address = server.address();
        if (!address || typeof address === "string") {
            throw new Error("Could not resolve Chobby launcher loopback port");
        }

        const pendingWrite = this.writeConnectionFile(address);
        this.pendingConnectionWrite = pendingWrite;
        let connection: ChobbyLauncherConnection;
        try {
            connection = await pendingWrite;
        } finally {
            if (this.pendingConnectionWrite === pendingWrite) this.pendingConnectionWrite = null;
        }
        if (generation !== this.generation || this.server !== server) throw new Error("Chobby loopback stopped during startup");
        this.connection = connection;
        this.scheduleStartupOwnerCheck(generation);
        log.info(`Chobby launcher loopback listening at ${connection.host}:${connection.port}`);
        return connection;
    }

    public close(): Promise<void> {
        if (this.closingPromise) return this.closingPromise;
        const generation = ++this.generation;
        const server = this.server;
        const connection = this.connection;
        const pendingWrite = this.pendingConnectionWrite;
        this.server = null;
        this.connection = null;
        this.clearIdleShutdownTimer();
        this.clearStartupOwnerTimer();
        const closing = (async () => {
            for (const socket of this.clients) socket.destroy();
            this.clients.clear();
            for (const childProcess of this.childProcesses) {
                if (!childProcess.killed) childProcess.kill();
            }
            this.childProcesses.clear();
            if (server) await new Promise<void>((resolve) => server.close(() => resolve()));
            const stoppedConnection = connection ?? await pendingWrite?.catch(() => null);
            if (!stoppedConnection || generation !== this.generation) return;
            try {
                const record: unknown = JSON.parse(await fs.promises.readFile(this.connectionFilePath, "utf-8"));
                if (generation === this.generation && this.isOwnedConnectionRecord(record, stoppedConnection)) {
                    await fs.promises.unlink(this.connectionFilePath);
                }
            } catch (err) {
                if ((err as NodeJS.ErrnoException).code !== "ENOENT") {
                    log.warn(`Failed to remove Chobby launcher connection file: ${err instanceof Error ? err.message : String(err)}`);
                }
            }
        })();
        const completion = closing.finally(() => {
            if (this.closingPromise === completion) this.closingPromise = null;
        });
        this.closingPromise = completion;
        return completion;
    }

    private isOwnedConnectionRecord(record: unknown, connection: ChobbyLauncherConnection): record is Record<string, unknown> {
        return isRecord(record) && record._sl_helper_pid === process.pid && record._sl_address === LOOPBACK_HOST
            && record._sl_port === connection.port && record._sl_write_path === this.options.writeDataPath;
    }

    private isPreClientStartup(generation: number) {
        return generation === this.generation && this.server !== null && !this.hasConnectedClient;
    }

    private clearStartupOwnerTimer() {
        if (this.startupOwnerTimer) clearTimeout(this.startupOwnerTimer);
        this.startupOwnerTimer = null;
    }

    private scheduleStartupOwnerCheck(generation: number) {
        if (!this.options.startupOwnerPID || !this.options.onIdle || !this.isPreClientStartup(generation) || this.startupOwnerTimer) return;
        // This is a liveness observation cadence, not a deadline for slow startup.
        this.startupOwnerTimer = setTimeout(() => {
            if (!this.isPreClientStartup(generation)) return;
            this.startupOwnerTimer = null;
            void this.checkStartupOwner(generation).catch((err: unknown) => {
                if (!this.isPreClientStartup(generation)) return;
                log.warn(`Failed to check Chobby startup owner: ${err instanceof Error ? err.message : String(err)}`);
                this.options.onIdle?.();
            });
        }, this.options.idleShutdownDelayMs ?? 5_000);
    }

    private async readStartupNativeOwner(generation: number) {
        if (this.startupNativePID !== undefined) return this.startupNativePID;
        try {
            const record: unknown = JSON.parse(await fs.promises.readFile(this.connectionFilePath, "utf-8"));
            if (!this.isPreClientStartup(generation)) return;
            if (this.connection && this.isOwnedConnectionRecord(record, this.connection)) {
                const pid = record._sl_engine_pid;
                if (typeof pid === "number" && Number.isSafeInteger(pid) && pid > 0 && pid !== process.pid && pid !== this.options.startupOwnerPID) {
                    this.startupNativePID = pid;
                }
            }
        } catch {
            // Before publication the launcher remains the owner. On its death,
            // the caller re-reads the record to close the publish/exit race.
        }
        return this.startupNativePID;
    }

    private isProcessAlive(pid: number) {
        try {
            process.kill(pid, 0);
            return true;
        } catch (err) {
            if ((err as NodeJS.ErrnoException).code === "ESRCH") return false;
            if ((err as NodeJS.ErrnoException).code === "EPERM") return true;
            throw err;
        }
    }

    private async checkStartupOwner(generation: number) {
        let nativePID = await this.readStartupNativeOwner(generation);
        if (!this.isPreClientStartup(generation)) return;
        if (nativePID === undefined && this.isProcessAlive(this.options.startupOwnerPID!)) {
            this.scheduleStartupOwnerCheck(generation);
            return;
        }
        if (nativePID === undefined) {
            nativePID = await this.readStartupNativeOwner(generation);
            if (!this.isPreClientStartup(generation)) return;
        }
        if (nativePID !== undefined && this.isProcessAlive(nativePID)) {
            this.scheduleStartupOwnerCheck(generation);
            return;
        }
        log.info("Chobby startup owner exited before a menu client connected; requesting helper shutdown");
        this.options.onIdle?.();
    }

    private clearIdleShutdownTimer() {
        if (!this.idleShutdownTimer) {
            return;
        }

        clearTimeout(this.idleShutdownTimer);
        this.idleShutdownTimer = null;
    }

    private scheduleIdleShutdownIfNeeded() {
        if (!this.server || !this.options.onIdle || this.clients.size > 0 || this.childProcesses.size > 0 || this.idleShutdownTimer) {
            return;
        }

        const delayMs = this.options.idleShutdownDelayMs ?? 5_000;
        const generation = this.generation;
        this.idleShutdownTimer = setTimeout(() => {
            if (generation !== this.generation || !this.server) return;
            this.idleShutdownTimer = null;
            if (this.clients.size === 0 && this.childProcesses.size === 0) {
                log.info("Chobby launcher loopback is idle; requesting helper shutdown");
                this.options.onIdle?.();
            }
        }, delayMs);
    }

    private trackChildProcess(childProcess: ChildProcess, label: string) {
        const generation = this.generation;
        this.clearIdleShutdownTimer();
        this.childProcesses.add(childProcess);

        let settled = false;
        const forgetChildProcess = (reason: string) => {
            if (settled) {
                return;
            }
            settled = true;
            if (generation !== this.generation || !this.server) return;
            this.childProcesses.delete(childProcess);
            log.info(`Chobby launcher loopback child process ended (${label}, ${reason})`);
            this.scheduleIdleShutdownIfNeeded();
        };

        childProcess.once("error", (err) => forgetChildProcess(`error=${err.message}`));
        childProcess.once("exit", (code, signal) => forgetChildProcess(`exit code=${code}, signal=${signal}`));
        childProcess.once("close", (code, signal) => forgetChildProcess(`close code=${code}, signal=${signal}`));
    }

    private async writeConnectionFile(address: AddressInfo): Promise<ChobbyLauncherConnection> {
        const connection = {
            _sl_address: LOOPBACK_HOST,
            _sl_port: address.port,
            _sl_write_path: this.options.writeDataPath,
            _sl_helper_pid: process.pid,
        };

        await fs.promises.mkdir(this.options.writeDataPath, { recursive: true });
        await fs.promises.writeFile(this.connectionFilePath, `${JSON.stringify(connection, null, 2)}\n`, "utf-8");

        return {
            host: connection._sl_address,
            port: connection._sl_port,
            writePath: connection._sl_write_path,
            connectionFilePath: this.connectionFilePath,
        };
    }

    private get connectionFilePath() {
        return path.join(this.options.writeDataPath, CONNECTION_FILE_NAME);
    }

    private handleConnection(socket: Socket, generation: number) {
        if (generation !== this.generation || !this.server) {
            socket.destroy();
            return;
        }
        this.hasConnectedClient = true;
        this.clearStartupOwnerTimer();
        this.clearIdleShutdownTimer();
        this.clients.add(socket);
        log.info("Chobby launcher loopback client connected");

        let buffered = "";
        socket.on("data", (data) => {
            buffered += data.toString("utf-8");
            const lines = buffered.split("\n");
            buffered = lines.pop() ?? "";

            for (const line of lines.map((value) => value.trim()).filter(Boolean)) {
                this.handleLine(socket, line).catch((err: unknown) => log.error(`Chobby launcher loopback command failed: ${err instanceof Error ? err.message : String(err)}`));
            }
        });
        socket.on("error", (err) => log.warn(`Chobby launcher loopback socket error: ${err.message}`));
        socket.on("close", () => {
            if (generation !== this.generation || !this.server || !this.clients.delete(socket)) return;
            log.info("Chobby launcher loopback client disconnected");
            this.scheduleIdleShutdownIfNeeded();
        });
    }

    private async handleLine(socket: Socket, line: string) {
        let message: ChobbyConnectorMessage;
        try {
            message = JSON.parse(line);
        } catch (err) {
            log.warn(`Ignoring malformed Chobby launcher loopback message: ${err instanceof Error ? err.message : String(err)}`);
            return;
        }

        switch (message.name) {
            case "Download":
                await this.handleDownload(socket, parseDownloadCommand(message.command));
                break;
            case "StartNewSpring":
                await this.handleStartNewSpring(parseStartNewSpringCommand(message.command));
                break;
            case "OpenFile":
                await this.handleOpenFile(message.command);
                break;
            case "LoadArchiveExtensions":
            case "DiscordSetActivity":
            case "ReadReplayInfo":
            case "ParseMiniMap":
            case "UploadLog":
                log.debug(`Chobby launcher loopback received ${message.name}`);
                break;
            default:
                log.debug(`Chobby launcher loopback ignoring command: ${message.name ?? "<missing>"}`);
        }
    }

    private async handleOpenFile(command: unknown) {
        if (!isRecord(command)) {
            return;
        }

        const targetPath = asString(command.path);
        if (!targetPath || !/^(https?:|file:)/i.test(targetPath)) {
            return;
        }

        await shell.openExternal(targetPath).catch((err: unknown) => log.warn(`Failed to open Chobby external path ${targetPath}: ${err instanceof Error ? err.message : String(err)}`));
    }

    private async handleDownload(socket: Socket, command: ChobbyDownloadCommand) {
        const name = command.name;
        const type = command.type?.toLowerCase();
        if (!name || !type) {
            this.sendDownloadFinished(socket, name ?? "<missing>", false);
            return;
        }

        if (type === "resource") {
            await this.handleResourceDownload(socket, name, command.resource);
            return;
        }

        const downloadArg = getPrDownloaderDownloadArg(type);
        if (!downloadArg) {
            log.warn(`Unsupported Chobby launcher download type: ${type}`);
            this.sendDownloadFinished(socket, name, false);
            return;
        }

        await this.runPrDownloader(socket, name, downloadArg);
    }

    private async runPrDownloader(socket: Socket, name: string, downloadArg: string) {
        const downloadKey = `${downloadArg}\0${name}`;
        const activeDownload = this.prDownloaderDownloads.get(downloadKey);
        if (activeDownload) {
            log.info(`Chobby launcher loopback joining in-flight download ${name} with ${downloadArg}`);
            const isSuccess = await activeDownload;
            if (isSuccess) {
                this.send(socket, "DownloadProgress", { name, progress: 1, total: 1 });
            }
            this.sendDownloadFinished(socket, name, isSuccess);
            return;
        }

        const downloadPromise = this.runPrDownloaderProcess(socket, name, downloadArg);
        this.prDownloaderDownloads.set(downloadKey, downloadPromise);
        try {
            await downloadPromise;
        } finally {
            if (this.prDownloaderDownloads.get(downloadKey) === downloadPromise) {
                this.prDownloaderDownloads.delete(downloadKey);
            }
        }
    }

    private async runPrDownloaderProcess(socket: Socket, name: string, downloadArg: string): Promise<boolean> {
        const prBinaryPath = resolvePrDownloaderPath({
            engineVersion: this.options.engineVersion,
            assetsPath: this.options.assetsPath,
            bundledAssetsPath: this.options.bundledAssetsPath,
            platform: this.options.platform,
        });
        const caCertPath = getCaCertPath();

        log.info(`Chobby launcher loopback downloading ${name} with ${downloadArg}`);

        return new Promise<boolean>((resolve) => {
            let sawErrorOutput = false;
            const prdProcess = spawn(prBinaryPath, ["--filesystem-writepath", this.options.assetsPath, downloadArg, name], {
                cwd: path.dirname(prBinaryPath),
                env: {
                    ...process.env,
                    PRD_RAPID_USE_STREAMER: "false",
                    PRD_RAPID_REPO_MASTER,
                    PRD_HTTP_SEARCH_URL,
                    ...(caCertPath && !process.env.PRD_SSL_CERT_FILE && { PRD_SSL_CERT_FILE: caCertPath }),
                },
            });
            this.trackChildProcess(prdProcess, `pr-downloader ${name}`);

            prdProcess.stdout?.on("data", (data: Buffer) => {
                for (const line of data
                    .toString("utf-8")
                    .split(/\r?\n|\r/)
                    .filter(Boolean)) {
                    if (line.startsWith("[Progress]")) {
                        const progress = parsePrDownloaderProgress(line);
                        this.send(socket, "DownloadProgress", {
                            name,
                            progress: progress.progress,
                            total: progress.total,
                        });
                        continue;
                    }
                    log.debug(`[CHOBBY LOOPBACK PR-DOWNLOADER] ${line}`);
                }
            });
            prdProcess.stderr?.on("data", (data: Buffer) => {
                for (const line of data
                    .toString("utf-8")
                    .split(/\r?\n|\r/)
                    .filter(Boolean)) {
                    if (line.includes("[Error]") || line.includes("Error:")) {
                        sawErrorOutput = true;
                        log.warn(`[CHOBBY LOOPBACK PR-DOWNLOADER] ${line}`);
                    } else {
                        log.debug(`[CHOBBY LOOPBACK PR-DOWNLOADER] ${line}`);
                    }
                }
            });
            prdProcess.on("error", (err) => {
                log.error(`Chobby loopback pr-downloader failed to start: ${err.message}`);
                this.sendDownloadFinished(socket, name, false);
                resolve(false);
            });
            prdProcess.on("exit", (code, signal) => {
                if (code === 0 && !sawErrorOutput) {
                    log.info(`Chobby loopback pr-downloader completed: ${name}`);
                    this.send(socket, "DownloadProgress", { name, progress: 1, total: 1 });
                    this.sendDownloadFinished(socket, name, true);
                    resolve(true);
                } else if (code === 0) {
                    log.warn(`Chobby loopback pr-downloader exited with code 0 after error output; treating ${name} as failed`);
                    this.sendDownloadFinished(socket, name, false);
                    resolve(false);
                } else {
                    log.warn(`Chobby loopback pr-downloader exited with code ${code}, signal ${signal}`);
                    this.sendDownloadFinished(socket, name, false);
                    resolve(false);
                }
            });
        });
    }

    private async handleResourceDownload(socket: Socket, name: string, resource: ChobbyResourceDownload | undefined) {
        if (!resource?.url || !resource.destination) {
            log.warn(`Chobby resource download ${name} is missing url or destination`);
            this.sendDownloadFinished(socket, name, false);
            return;
        }

        const destinationPath = this.resolveResourceDestinationPath(resource.destination);
        const downloadPath = resource.extract ? path.join(this.options.writeDataPath, RESOURCE_DOWNLOAD_DIR_NAME, safeDownloadFileName(resource.url, name)) : destinationPath;

        try {
            await fs.promises.mkdir(path.dirname(downloadPath), { recursive: true });
            await fs.promises.mkdir(path.dirname(destinationPath), { recursive: true });
            await this.downloadUrl(resource.url, downloadPath, (downloadedBytes, totalBytes) => {
                this.send(socket, "DownloadProgress", {
                    name,
                    progress: totalBytes > 0 ? downloadedBytes / totalBytes : 0,
                    total: totalBytes,
                });
            });

            if (resource.extract) {
                await fs.promises.mkdir(destinationPath, { recursive: true });
                await extract7z(downloadPath, destinationPath);
            }

            this.send(socket, "DownloadProgress", { name, progress: 1, total: 1 });
            this.sendDownloadFinished(socket, name, true);
            log.info(`Chobby resource download completed: ${resource.destination}`);
        } catch (err) {
            log.warn(`Chobby resource download failed for ${resource.destination}: ${err instanceof Error ? err.message : String(err)}`);
            this.sendDownloadFinished(socket, name, false, resource.optional);
        }
    }

    private resolveResourceDestinationPath(destination: string) {
        if (path.isAbsolute(destination)) {
            throw new Error(`Absolute Chobby resource destinations are not allowed: ${destination}`);
        }

        const destinationRoot = destination === "pool" || destination.startsWith("pool/") || destination.startsWith("engine/") ? this.options.assetsPath : this.options.writeDataPath;
        const resolvedRoot = path.resolve(destinationRoot);
        const resolvedDestination = path.resolve(resolvedRoot, destination);

        if (resolvedDestination !== resolvedRoot && !resolvedDestination.startsWith(`${resolvedRoot}${path.sep}`)) {
            throw new Error(`Chobby resource destination escapes the data root: ${destination}`);
        }

        return resolvedDestination;
    }

    private async downloadUrl(urlString: string, destinationPath: string, onProgress: DownloadProgressListener, redirects = 0): Promise<void> {
        if (redirects > MAX_HTTP_REDIRECTS) {
            throw new Error(`Too many redirects while downloading ${urlString}`);
        }

        const url = new URL(urlString);
        if (url.protocol !== "https:" && url.protocol !== "http:") {
            throw new Error(`Unsupported resource URL protocol: ${url.protocol}`);
        }

        const client = url.protocol === "https:" ? https : http;

        await new Promise<void>((resolve, reject) => {
            const request = client.get(
                url,
                {
                    headers: {
                        "user-agent": "BAR-Lobby-Chobby-Loopback",
                    },
                },
                (response) => {
                    const statusCode = response.statusCode ?? 0;
                    if (statusCode >= 300 && statusCode < 400 && response.headers.location) {
                        response.resume();
                        const nextUrl = new URL(response.headers.location, url).toString();
                        this.downloadUrl(nextUrl, destinationPath, onProgress, redirects + 1).then(resolve, reject);
                        return;
                    }

                    if (statusCode < 200 || statusCode >= 300) {
                        response.resume();
                        reject(new Error(`HTTP ${statusCode} while downloading ${urlString}`));
                        return;
                    }

                    const totalBytes = Number(response.headers["content-length"] ?? 0);
                    let downloadedBytes = 0;
                    const output = fs.createWriteStream(destinationPath);

                    response.on("data", (chunk: Buffer) => {
                        downloadedBytes += chunk.length;
                        onProgress(downloadedBytes, Number.isFinite(totalBytes) ? totalBytes : 0);
                    });
                    response.on("error", reject);
                    output.on("error", reject);
                    output.on("finish", () => resolve());
                    response.pipe(output);
                }
            );

            request.on("error", reject);
        });
    }

    private async handleStartNewSpring(command: ChobbyStartNewSpringCommand) {
        const engineVersion = this.normalizeEngineVersion(command.Engine);
        if (this.options.platform === "darwin") {
            const overlayResult = await prepareMacOSLuaUIOverlayForLaunch({
                bundledAssetsPath: this.options.bundledAssetsPath,
                writeDataPath: this.options.writeDataPath,
                lane: "bar-chobby",
                platform: this.options.platform,
            });
            if (overlayResult.prepared) {
                log.info(
                    `Prepared bar-chobby macOS LuaUI overlay: ${overlayResult.sourcePath}; quarantined=${overlayResult.quarantinedFiles?.length ?? 0}; preserved=${overlayResult.preservedFiles?.length ?? 0}`
                );
            } else {
                log.debug(`Skipped bar-chobby macOS LuaUI overlay preparation: ${overlayResult.reason ?? "unknown"}`);
            }
        }
        const runner = resolveNativeEngineRunner({
            engineVersion,
            assetsPath: this.options.assetsPath,
            bundledAssetsPath: this.options.bundledAssetsPath,
            platform: this.options.platform,
        });
        const enginePath = runner.enginePath.replaceAll("\\", "/");
        const env = getNativeEngineProcessEnv({
            assetsPath: this.options.assetsPath,
            bundledAssetsPath: this.options.bundledAssetsPath,
            enginePath,
            includeBundledAssetsInSpringDataDir: false,
            includeBundledEngineSupportInSpringDataDir: true,
            // The paired native engine owns the immutable presentation adaptations.
            includeBundledMacOSLuaUIOverlayInSpringDataDir: false,
            macOSLuaUIOverlayLane: "bar-chobby",
            writeDataPath: this.options.writeDataPath,
            platform: this.options.platform,
            baseEnv: process.env,
        });
        const launchArg = await this.resolveStartNewSpringLaunchArg(command);
        const args = ["--write-dir", this.options.writeDataPath, "--isolation", launchArg];

        log.info(`Chobby launcher loopback starting native engine ${engineVersion}: ${launchArg}`);
        if (this.options.platform === "darwin") {
            log.info(`${MACOS_NATIVE_ENGINE_ENV_DIAGNOSTIC_PROBE}: ${JSON.stringify(getNativeEngineProcessEnvDiagnostics(env))}`);
            log.info(`${MACOS_NATIVE_ENGINE_DATA_DIR_DIAGNOSTIC_PROBE}: ${JSON.stringify(getNativeEngineDataDirDiagnostics(env))}`);
            if (env.ZINK_DEBUG === MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE) {
                log.info(
                    [
                        "MACOS_RUNTIME_WORKAROUND",
                        `reason=${MACOS_MINIMAL_FPS_WORKAROUND_REASON}`,
                        `ZINK_DEBUG=${MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE}`,
                        `${MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV}=${env[MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV] ?? "<unset>"}`,
                        `${MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV}=${env[MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV] ?? "<unset>"}`,
                        "workaround_active=true",
                        "production_acceptance=false",
                        "track_owner=Thread07-runtime-backend",
                        "launch_context=chobby-start-new-spring",
                    ].join(" ")
                );
            }
        }
        const childProcess = spawn(runner.spawnCommand, args, {
            cwd: runner.enginePath,
            detached: true,
            stdio: "ignore",
            env,
        });
        this.trackChildProcess(childProcess, `native engine ${engineVersion}`);
    }

    private normalizeMacOSDisplaySpringSettings(settings: string) {
        if (this.options.platform !== "darwin") return settings;
        // Chobby's mode3 serializes Fullscreen1, mode2 explicitly serializes0.
        // Respect both. Borderless modes omit Fullscreen but set WindowBorderless1;
        // that is a window choice, not permission to force native fullscreen.
        if (/^\s*Fullscreen\s*=/m.test(settings)) return settings;
        const borderless = /^\s*WindowBorderless\s*=\s*1\s*$/m.test(settings);
        return `${settings.trimEnd()}\nFullscreen = ${borderless ? 0 : 1}\n`;
    }

    private async resolveStartNewSpringLaunchArg(command: ChobbyStartNewSpringCommand) {
        await fs.promises.mkdir(this.options.writeDataPath, { recursive: true });
        if (command.SpringSettings) {
            const springSettings = this.normalizeMacOSDisplaySpringSettings(command.SpringSettings);
            await fs.promises.writeFile(path.join(this.options.writeDataPath, "springsettings.cfg"), springSettings, "utf-8");
        }
        if (command.StartScriptContent) {
            const scriptPath = path.join(this.options.writeDataPath, `chobby-start-script-${Date.now()}.txt`);
            await fs.promises.writeFile(scriptPath, command.StartScriptContent, "utf-8");
            return scriptPath;
        }
        if (command.StartDemoName) {
            return command.StartDemoName;
        }

        throw new Error("StartNewSpring command is missing StartScriptContent or StartDemoName");
    }

    private normalizeEngineVersion(requestedEngineVersion: string | undefined) {
        const requested = requestedEngineVersion?.trim() || this.options.engineVersion;
        const currentRecoilName = `recoil_${this.options.engineVersion}`;
        const normalized = requested
            .replace(/^engine\//i, "")
            .replace(/^recoil_/i, "")
            .replace(/\s+BAR105$/i, "");

        if (requested === currentRecoilName || normalized === this.options.engineVersion) {
            return this.options.engineVersion;
        }

        return normalized;
    }

    private sendDownloadFinished(socket: Socket, name: string, isSuccess: boolean, isAborted = false) {
        this.send(socket, "DownloadFinished", {
            name,
            isSuccess,
            isAborted,
        });
    }

    private send(socket: Socket, name: string, command: unknown) {
        if (socket.destroyed) {
            return;
        }

        socket.write(`${JSON.stringify({ name, command })}\n`);
    }
}
