// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import fs from "fs";
import path from "path";
import { createHash, randomUUID } from "node:crypto";

export const BUNDLED_ASSETS_DIR_NAME = "bundled-assets";
export const MACOS_LUAUI_OVERLAYS_DIR_NAME = "macos-luaui-overlays";

export type MacOSLuaUIOverlayLane = "bar-chobby" | "bar-lobby";

type PathExists = (filePath: string) => boolean;

export interface NativeEnginePaths {
    assetsPath: string;
    bundledAssetsPath?: string;
    enginePath?: string;
    includeBundledAssetsInSpringDataDir?: boolean;
    includeBundledEngineSupportInSpringDataDir?: boolean;
    includeBundledMacOSLuaUIOverlayInSpringDataDir?: boolean;
    macOSLuaUIOverlayLane?: MacOSLuaUIOverlayLane;
}

export interface NativeEngineResolverOptions extends NativeEnginePaths {
    engineVersion: string;
    platform?: NodeJS.Platform;
    pathExists?: PathExists;
}

export interface NativeEngineProcessEnvOptions extends NativeEnginePaths {
    writeDataPath?: string;
    /** Defaults to <writeDataPath>/renderer.json; read only when bundled macOS MoltenVK is used. */
    rendererConfigPath?: string;
    platform?: NodeJS.Platform;
    baseEnv?: NodeJS.ProcessEnv;
    pathExists?: PathExists;
}

export interface MacOSLuaUIOverlayPrepareOptions {
    bundledAssetsPath?: string;
    writeDataPath: string;
    lane: MacOSLuaUIOverlayLane;
    platform?: NodeJS.Platform;
}

export interface MacOSLuaUIOverlayPrepareResult {
    prepared: boolean;
    lane: MacOSLuaUIOverlayLane;
    sourcePath?: string;
    quarantinePath?: string;
    quarantinedFiles?: string[];
    preservedFiles?: string[];
    reason?: string;
}

interface MacOSLuaUIOverlayManifest {
    schemaVersion: 1;
    lane: MacOSLuaUIOverlayLane;
    files: string[];
}

interface LegacyManagedFile {
    path: string;
    sha256: string[];
}

interface LegacyManagedFilesManifest {
    schemaVersion: 1;
    files: LegacyManagedFile[];
}

export interface NativeEngineRunner {
    enginePath: string;
    binaryFileName: string;
    spawnCommand: string;
}

export interface MacOSGraphicsRuntimePaths {
    vulkanBackend: MacOSVulkanBackend;
    sdl3LibPath: string;
    mesaZinkLibPath: string;
    vulkanLoaderLibPath: string;
    vulkanBackendLibPath: string;
    vulkanBackendICDPath: string;
    vulkanBackendRequiredLibraryPath: string;
    moltenVKLibPath: string;
    moltenVKICDPath: string;
    kosmicKrispLibPath: string;
    kosmicKrispICDPath: string;
    fontconfigConfigDirPath: string;
    fontconfigFilePath: string;
}

export type MacOSVulkanBackend = "moltenvk" | "kosmickrisp";
export type MacOSMetalBackend = "METAL3" | "METAL4";
export type MacOSRendererPreference = {
    renderer: MacOSMetalBackend;
    overriddenBy: "BAR_METAL_BACKEND" | "MVK_CONFIG_USE_METAL4" | null;
};

const LEGACY_DRIVER_DISCOVERY_ENV_KEYS = ["VK_ADD_DRIVER_FILES", "DYLD_FALLBACK_LIBRARY_PATH"] as const;
const MACOS_DIAGNOSTIC_BASELINE_ENV_KEYS = ["ZINK_DEBUG", "MESA_GLTHREAD", "GALLIUM_THREAD"] as const;
export const MACOS_VULKAN_BACKEND_ENV = "BAR_MACOS_VULKAN_BACKEND";
export const MACOS_METAL_BACKEND_ENV = "BAR_METAL_BACKEND";
export const MACOS_METAL_BACKEND_REQUESTED_ENV = "BAR_METAL_BACKEND_REQUESTED";
export const MACOS_MOLTENVK_METAL4_ENV = "MVK_CONFIG_USE_METAL4";
export const MACOS_RENDERER_CONFIG_FILE_NAME = "renderer.json";
const MAX_RENDERER_CONFIG_BYTES = 4096;
export const MACOS_VULKAN_LOADER_BUNDLE_ONLY_ENV = "VK_LOADER_SEARCH_ONLY_IN_BUNDLE";
export const MACOS_KOSMICKRISP_BACKEND_MARKER = "bar-vulkan-backend-kosmickrisp";
export const MACOS_DIAGNOSTIC_ENGINE_ENV_GATE = "BAR_MACOS_ALLOW_DIAGNOSTIC_ENGINE_ENV";
export const MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV = "BAR_MACOS_ENABLE_MINIMAL_FPS_WORKAROUND";
export const MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV = "BAR_MACOS_DISABLE_MINIMAL_FPS_WORKAROUND";
export const MACOS_MINIMAL_FPS_WORKAROUND_REASON = "minimal_fps_baseline";
export const MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE = "quiet,flushsync";
export const MACOS_DIAGNOSTIC_ZINK_DEBUG_VALUE = MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE;
const MACOS_RUNTIME_ENV_KEYS = [
    "SPRING_DATADIR",
    "DYLD_LIBRARY_PATH",
    "VK_DRIVER_FILES",
    "VK_ICD_FILENAMES",
    "MESA_LOADER_DRIVER_OVERRIDE",
    "GALLIUM_DRIVER",
    "EGL_PLATFORM",
    "MESA_GL_VERSION_OVERRIDE",
    "MESA_GLSL_VERSION_OVERRIDE",
    MACOS_VULKAN_LOADER_BUNDLE_ONLY_ENV,
    "FONTCONFIG_FILE",
    "FONTCONFIG_PATH",
    "XDG_CACHE_HOME",
    "MESA_SHADER_CACHE_DIR",
    "MESA_GLSL_CACHE_DIR",
    MACOS_VULKAN_BACKEND_ENV,
    MACOS_METAL_BACKEND_REQUESTED_ENV,
    MACOS_MOLTENVK_METAL4_ENV,
    MACOS_DIAGNOSTIC_ENGINE_ENV_GATE,
    MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV,
    MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV,
] as const;

export const MACOS_NATIVE_ENGINE_ENV_DIAGNOSTIC_PROBE = "MACOS_DIAGNOSTIC_PROBE native-engine-env";
export const MACOS_NATIVE_ENGINE_DATA_DIR_DIAGNOSTIC_PROBE = "MACOS_DIAGNOSTIC_PROBE native-engine-data-dirs";

export function getBundledAssetsPath(resourcesPath: string): string {
    return path.join(resourcesPath, BUNDLED_ASSETS_DIR_NAME);
}

export function getMacOSLuaUIOverlayRootPath(bundledAssetsPath: string): string {
    return path.join(bundledAssetsPath, MACOS_LUAUI_OVERLAYS_DIR_NAME);
}

export function getMacOSLuaUIOverlayPath(bundledAssetsPath: string, lane: MacOSLuaUIOverlayLane): string {
    return path.join(getMacOSLuaUIOverlayRootPath(bundledAssetsPath), lane);
}

function normalizeManagedRelativePath(relativePath: string): string {
    const normalizedPath = path.posix.normalize(relativePath.replaceAll("\\", "/"));
    if (path.posix.isAbsolute(normalizedPath) || normalizedPath === ".." || normalizedPath.startsWith("../")) {
        throw new Error(`Unsafe macOS LuaUI overlay path: ${relativePath}`);
    }
    return normalizedPath;
}

async function readJsonFile<T>(filePath: string): Promise<T> {
    return JSON.parse(await fs.promises.readFile(filePath, "utf-8")) as T;
}

async function sha256File(filePath: string): Promise<string> {
    return createHash("sha256").update(await fs.promises.readFile(filePath)).digest("hex");
}

async function uniqueQuarantinePath(destinationPath: string): Promise<string> {
    if (!(await fs.promises.stat(destinationPath).catch(() => undefined))) {
        return destinationPath;
    }
    return `${destinationPath}.${Date.now()}`;
}

export async function prepareMacOSLuaUIOverlayForLaunch({
    bundledAssetsPath,
    writeDataPath,
    lane,
    platform = process.platform,
}: MacOSLuaUIOverlayPrepareOptions): Promise<MacOSLuaUIOverlayPrepareResult> {
    if (platform !== "darwin") {
        return { prepared: false, lane, reason: "not-macos" };
    }
    if (!bundledAssetsPath) {
        return { prepared: false, lane, reason: "missing-bundled-assets-path" };
    }

    const overlayRootPath = getMacOSLuaUIOverlayRootPath(bundledAssetsPath);
    const sourcePath = getMacOSLuaUIOverlayPath(bundledAssetsPath, lane);
    const sourceStats = await fs.promises.stat(path.join(sourcePath, "LuaUI")).catch((err: NodeJS.ErrnoException) => {
        if (err.code === "ENOENT") {
            return undefined;
        }
        throw err;
    });
    if (!sourceStats?.isDirectory()) {
        return { prepared: false, lane, sourcePath, reason: "missing-lane-overlay-luaui" };
    }

    const overlayManifest = await readJsonFile<MacOSLuaUIOverlayManifest>(path.join(sourcePath, "manifest.json"));
    if (overlayManifest.schemaVersion !== 1 || overlayManifest.lane !== lane) {
        throw new Error(`Invalid macOS LuaUI overlay manifest for ${lane}`);
    }
    for (const relativePath of overlayManifest.files) {
        const normalizedPath = normalizeManagedRelativePath(relativePath);
        const fileStats = await fs.promises.stat(path.join(sourcePath, normalizedPath)).catch(() => undefined);
        if (!fileStats?.isFile()) {
            throw new Error(`Missing ${lane} overlay file declared by manifest: ${normalizedPath}`);
        }
    }

    const legacyManifestPath = path.join(overlayRootPath, "legacy-managed-files.json");
    const legacyManifest = await readJsonFile<LegacyManagedFilesManifest>(legacyManifestPath).catch(() => ({ schemaVersion: 1 as const, files: [] }));
    if (legacyManifest.schemaVersion !== 1) {
        throw new Error("Invalid legacy macOS LuaUI managed-files manifest");
    }

    const quarantinePath = path.join(writeDataPath, "bar-macos-quarantine", "legacy-shared-overlay-v1");
    const quarantinedFiles: string[] = [];
    const preservedFiles: string[] = [];
    for (const entry of legacyManifest.files) {
        const normalizedPath = normalizeManagedRelativePath(entry.path);
        const writablePath = path.join(writeDataPath, normalizedPath);
        const writableStats = await fs.promises.stat(writablePath).catch(() => undefined);
        if (!writableStats?.isFile()) {
            continue;
        }

        const writableHash = await sha256File(writablePath);
        if (!entry.sha256.includes(writableHash)) {
            preservedFiles.push(normalizedPath);
            continue;
        }

        const destinationPath = await uniqueQuarantinePath(path.join(quarantinePath, normalizedPath));
        await fs.promises.mkdir(path.dirname(destinationPath), { recursive: true });
        await fs.promises.rename(writablePath, destinationPath);
        quarantinedFiles.push(normalizedPath);
    }

    return { prepared: true, lane, sourcePath, quarantinePath, quarantinedFiles, preservedFiles };
}

export function getEngineRootSearchPaths({ assetsPath, bundledAssetsPath }: NativeEnginePaths): string[] {
    return [path.join(assetsPath, "engine"), ...(bundledAssetsPath ? [path.join(bundledAssetsPath, "engine")] : [])];
}

export function getEngineVersionSearchPaths(options: NativeEnginePaths & { engineVersion: string }): string[] {
    const version = options.engineVersion;
    if (typeof version !== "string" || !version.trim() || version.trim() === "." || version.trim() === ".." || /[\\/:\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(version)) {
        throw new Error(`Invalid engine version ${JSON.stringify(version)}: expected one directory name without separators, drive prefixes or control characters.`);
    }
    return getEngineRootSearchPaths(options).map((engineRoot) => path.join(engineRoot, options.engineVersion));
}

export function getEngineBinaryFileName(platform: NodeJS.Platform = process.platform): string {
    return platform === "win32" ? "spring.exe" : "spring";
}

export function getEngineSpawnCommand(platform: NodeJS.Platform = process.platform): string {
    return platform === "win32" ? "spring.exe" : "./spring";
}

export function getPrDownloaderBinaryFileName(platform: NodeJS.Platform = process.platform): string {
    return platform === "win32" ? "pr-downloader.exe" : "pr-downloader";
}

export function getSpringDataDir(
    {
        assetsPath,
        bundledAssetsPath,
        enginePath,
        includeBundledAssetsInSpringDataDir = true,
        includeBundledEngineSupportInSpringDataDir = false,
        includeBundledMacOSLuaUIOverlayInSpringDataDir = false,
        macOSLuaUIOverlayLane,
    }: NativeEnginePaths,
    pathExists: PathExists = fs.existsSync
): string {
    const dataDirs: string[] = [];
    if (includeBundledMacOSLuaUIOverlayInSpringDataDir && bundledAssetsPath) {
        if (!macOSLuaUIOverlayLane) {
            throw new Error("A macOS LuaUI overlay lane is required when the overlay is enabled");
        }
        const overlayPath = getMacOSLuaUIOverlayPath(bundledAssetsPath, macOSLuaUIOverlayLane);
        if (pathExists(path.join(overlayPath, "LuaUI")) && !dataDirs.includes(overlayPath)) {
            dataDirs.push(overlayPath);
        }
    }
    dataDirs.push(assetsPath);
    if (includeBundledAssetsInSpringDataDir && bundledAssetsPath && pathExists(bundledAssetsPath)) {
        dataDirs.push(bundledAssetsPath);
    }
    if (!includeBundledAssetsInSpringDataDir && includeBundledEngineSupportInSpringDataDir && bundledAssetsPath && pathExists(bundledAssetsPath)) {
        for (const supportDirName of ["engine-fonts", "fonts"]) {
            const supportDir = path.join(bundledAssetsPath, supportDirName);
            if (pathExists(supportDir) && !dataDirs.includes(supportDir)) {
                dataDirs.push(supportDir);
            }
        }
    }
    if (enginePath && pathExists(enginePath) && !dataDirs.includes(enginePath)) {
        dataDirs.push(enginePath);
    }
    return dataDirs.join(path.delimiter);
}

function normalizeMacOSVulkanBackend(value: string | undefined): MacOSVulkanBackend | undefined {
    return value === "moltenvk" || value === "kosmickrisp" ? value : undefined;
}

function getMacOSKosmicKrispBackendMarkerPath(bundledAssetsPath: string): string {
    return path.join(path.dirname(bundledAssetsPath), MACOS_KOSMICKRISP_BACKEND_MARKER);
}

function resolveMacOSVulkanBackend(bundledAssetsPath: string, env: NodeJS.ProcessEnv, pathExists: PathExists): MacOSVulkanBackend {
    return normalizeMacOSVulkanBackend(env[MACOS_VULKAN_BACKEND_ENV]) ?? (pathExists(getMacOSKosmicKrispBackendMarkerPath(bundledAssetsPath)) ? "kosmickrisp" : "moltenvk");
}

export function getMacOSGraphicsRuntimePaths(bundledAssetsPath: string, vulkanBackend: MacOSVulkanBackend = "moltenvk"): MacOSGraphicsRuntimePaths {
    const runtimePath = path.join(bundledAssetsPath, "runtime");
    const moltenVKPath = path.join(runtimePath, "moltenvk-pr2746");
    const kosmicKrispPath = path.join(runtimePath, "kosmickrisp");
    const fontconfigPath = path.join(runtimePath, "fontconfig");
    const moltenVKLibPath = path.join(moltenVKPath, "lib");
    const moltenVKICDPath = path.join(moltenVKPath, "MoltenVK_icd.json");
    const kosmicKrispLibPath = path.join(kosmicKrispPath, "lib");
    const kosmicKrispICDPath = path.join(kosmicKrispPath, "kosmickrisp_mesa_icd.json");
    const vulkanBackendLibPath = vulkanBackend === "kosmickrisp" ? kosmicKrispLibPath : moltenVKLibPath;
    const vulkanBackendICDPath = vulkanBackend === "kosmickrisp" ? kosmicKrispICDPath : moltenVKICDPath;
    const vulkanBackendRequiredLibraryPath = vulkanBackend === "kosmickrisp" ? path.join(kosmicKrispLibPath, "libvulkan_kosmickrisp.dylib") : path.join(moltenVKLibPath, "libMoltenVK.dylib");
    return {
        vulkanBackend,
        sdl3LibPath: path.join(runtimePath, "sdl3", "lib"),
        mesaZinkLibPath: path.join(runtimePath, "mesa-zink", "lib"),
        vulkanLoaderLibPath: path.join(runtimePath, "vulkan-loader", "lib"),
        vulkanBackendLibPath,
        vulkanBackendICDPath,
        vulkanBackendRequiredLibraryPath,
        moltenVKLibPath,
        moltenVKICDPath,
        kosmicKrispLibPath,
        kosmicKrispICDPath,
        fontconfigConfigDirPath: fontconfigPath,
        fontconfigFilePath: path.join(fontconfigPath, "fonts.conf"),
    };
}

function getMacOSWritableDataPath(options: NativeEngineProcessEnvOptions): string {
    return options.writeDataPath ?? path.resolve(options.assetsPath, "..", "data");
}

function readMacOSRendererPreference(configPath: string): MacOSMetalBackend {
    let descriptor: number | undefined;
    try {
        // A bounded regular-file read also rejects pipes/devices and a file growing after fstat.
        descriptor = fs.openSync(configPath, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
        const stats = fs.fstatSync(descriptor);
        if (!stats.isFile() || stats.size > MAX_RENDERER_CONFIG_BYTES) {
            throw new Error(`Renderer preference must be a regular file of at most ${MAX_RENDERER_CONFIG_BYTES} bytes: ${configPath}`);
        }
        const buffer = Buffer.alloc(MAX_RENDERER_CONFIG_BYTES + 1);
        const bytesRead = fs.readSync(descriptor, buffer, 0, buffer.length, 0);
        if (bytesRead > MAX_RENDERER_CONFIG_BYTES) {
            throw new Error(`Renderer preference exceeds ${MAX_RENDERER_CONFIG_BYTES} bytes: ${configPath}`);
        }
        let preference: unknown;
        try {
            preference = JSON.parse(buffer.subarray(0, bytesRead).toString("utf-8"));
        } catch {
            // Do not echo potentially large or sensitive file contents into launch errors.
            throw new Error(`Invalid renderer preference JSON at ${configPath}; expected {"renderer":"METAL3"} or {"renderer":"METAL4"}.`);
        }
        if (
            typeof preference !== "object" || preference === null || Array.isArray(preference) ||
            Object.keys(preference).length !== 1 || !("renderer" in preference) ||
            (preference.renderer !== "METAL3" && preference.renderer !== "METAL4")
        ) {
            throw new Error(`Invalid renderer preference at ${configPath}; expected {"renderer":"METAL3"} or {"renderer":"METAL4"}.`);
        }
        return preference.renderer;
    } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") return "METAL3";
        throw error;
    } finally {
        if (descriptor !== undefined) fs.closeSync(descriptor);
    }
}

/**
 * Per-engine-launch request: BAR_METAL_BACKEND > MVK_CONFIG_USE_METAL4 >
 * <writeDataPath>/renderer.json ({"renderer":"METAL3"|"METAL4"}) > METAL3.
 * Both explicit environment values must be valid; an environment override skips
 * the file. Never writes preferences. Native activation still requires runtime proof.
 */
function getMacOSMetalOverride(env: NodeJS.ProcessEnv): MacOSRendererPreference | undefined {
    const backend = env[MACOS_METAL_BACKEND_ENV];
    const metal4 = env[MACOS_MOLTENVK_METAL4_ENV];
    if (backend !== undefined && backend !== "METAL3" && backend !== "METAL4") {
        throw new Error(`${MACOS_METAL_BACKEND_ENV} must be METAL3 or METAL4.`);
    }
    if (metal4 !== undefined && metal4 !== "0" && metal4 !== "1") {
        throw new Error(`${MACOS_MOLTENVK_METAL4_ENV} must be 0 or 1.`);
    }
    if (backend !== undefined) return { renderer: backend, overriddenBy: MACOS_METAL_BACKEND_ENV };
    if (metal4 !== undefined) return { renderer: metal4 === "1" ? "METAL4" : "METAL3", overriddenBy: MACOS_MOLTENVK_METAL4_ENV };
    return undefined;
}

export function getMacOSRendererPreference(configPath: string, env: NodeJS.ProcessEnv): MacOSRendererPreference {
    return getMacOSMetalOverride(env) ?? { renderer: readMacOSRendererPreference(configPath), overriddenBy: null };
}

/** Save the same next-launch preference used by both native engine lanes. */
export function setMacOSRendererPreference(configPath: string, renderer: unknown, env: NodeJS.ProcessEnv): MacOSRendererPreference {
    if (renderer !== "METAL3" && renderer !== "METAL4") throw new Error("Renderer must be METAL3 or METAL4.");
    const override = getMacOSMetalOverride(env);
    if (override) throw new Error(`Renderer is controlled by the ${override.overriddenBy} launch setting.`);

    // A sibling temporary file and atomic rename leave readers with a complete
    // old or new preference. No process environment or running engine is changed.
    fs.mkdirSync(path.dirname(configPath), { recursive: true });
    const temporary = `${configPath}.${randomUUID()}.tmp`;
    try {
        fs.writeFileSync(temporary, JSON.stringify({ renderer }) + "\n", { flag: "wx", mode: 0o600 });
        fs.renameSync(temporary, configPath);
    } finally {
        fs.rmSync(temporary, { force: true });
    }
    return { renderer, overriddenBy: null };
}

function resolveMacOSMetalBackend(options: NativeEngineProcessEnvOptions, env: NodeJS.ProcessEnv): MacOSMetalBackend {
    return getMacOSRendererPreference(
        options.rendererConfigPath ?? path.join(getMacOSWritableDataPath(options), MACOS_RENDERER_CONFIG_FILE_NAME), env
    ).renderer;
}

function scrubMacOSNativeEngineEnv(env: NodeJS.ProcessEnv) {
    for (const key of [...LEGACY_DRIVER_DISCOVERY_ENV_KEYS, ...MACOS_DIAGNOSTIC_BASELINE_ENV_KEYS]) {
        delete env[key];
    }
}

function isMacOSDiagnosticEngineEnvGateEnabled(env: NodeJS.ProcessEnv) {
    return env[MACOS_DIAGNOSTIC_ENGINE_ENV_GATE] === "1";
}

function isMacOSMinimalFpsWorkaroundEnabled(env: NodeJS.ProcessEnv) {
    return env[MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV] === "1";
}

function applyMacOSMinimalFpsWorkaroundEnv(env: NodeJS.ProcessEnv) {
    if (!isMacOSMinimalFpsWorkaroundEnabled(env)) {
        return env;
    }

    return {
        ...env,
        ZINK_DEBUG: MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE,
    };
}

function applyMacOSDiagnosticEngineEnv(env: NodeJS.ProcessEnv) {
    if (!isMacOSDiagnosticEngineEnvGateEnabled(env)) {
        return env;
    }

    return {
        ...env,
        ZINK_DEBUG: MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE,
    };
}

export function getNativeEngineProcessEnvDiagnostics(env: NodeJS.ProcessEnv): Record<string, string> {
    const keys = [...MACOS_RUNTIME_ENV_KEYS, ...LEGACY_DRIVER_DISCOVERY_ENV_KEYS, ...MACOS_DIAGNOSTIC_BASELINE_ENV_KEYS];
    return Object.fromEntries(keys.map((key) => [key, env[key] ?? "<unset>"]));
}

export function getNativeEngineDataDirDiagnostics(
    env: NodeJS.ProcessEnv,
    pathExists: PathExists = fs.existsSync,
    platform: NodeJS.Platform = process.platform
): Array<Record<string, string | number | boolean>> {
    const springDataDir = env.SPRING_DATADIR ?? "";
    return springDataDir
        .split(path.delimiter)
        .filter(Boolean)
        .map((entry, index) => ({
            index,
            path: entry,
            exists: pathExists(entry),
            hasLuaUI: pathExists(path.join(entry, "LuaUI")),
            hasLuaRules: pathExists(path.join(entry, "LuaRules")),
            hasEngineFonts: pathExists(path.join(entry, "fonts")) || pathExists(path.join(entry, "engine-fonts")),
            hasEngineBinary: pathExists(path.join(entry, getEngineBinaryFileName(platform))),
        }));
}

export function getNativeEngineProcessEnv(options: NativeEngineProcessEnvOptions): NodeJS.ProcessEnv {
    const platform = options.platform ?? process.platform;
    const pathExists = options.pathExists ?? fs.existsSync;
    const env: NodeJS.ProcessEnv = {
        ...(options.baseEnv ?? process.env),
        SPRING_DATADIR: getSpringDataDir(options, pathExists),
    };

    if (platform !== "darwin" || !options.bundledAssetsPath) {
        return env;
    }

    scrubMacOSNativeEngineEnv(env);

    const vulkanBackend = resolveMacOSVulkanBackend(options.bundledAssetsPath, env, pathExists);
    const runtimePaths = getMacOSGraphicsRuntimePaths(options.bundledAssetsPath, vulkanBackend);
    const requiredRuntimeFiles = [
        path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
        path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
        path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
        runtimePaths.vulkanBackendRequiredLibraryPath,
        runtimePaths.vulkanBackendICDPath,
        runtimePaths.fontconfigFilePath,
    ];

    if (!requiredRuntimeFiles.every(pathExists)) {
        return env;
    }

    const metalBackend = vulkanBackend === "moltenvk" ? resolveMacOSMetalBackend(options, env) : undefined;
    const rendererEnv = metalBackend ? {
        ...env,
        [MACOS_METAL_BACKEND_REQUESTED_ENV]: metalBackend,
        [MACOS_MOLTENVK_METAL4_ENV]: metalBackend === "METAL4" ? "1" : "0",
    } : env;
    if (metalBackend) {
        // Mesa prefers its new/legacy cache overrides over XDG_CACHE_HOME.
        // Each inherited override is a user-selected base, scoped once from the
        // original input environment; repeat launches never append to prior output.
        // Mesa treats an empty override as set, so remove it to allow XDG fallback.
        for (const key of ["MESA_SHADER_CACHE_DIR", "MESA_GLSL_CACHE_DIR"]) {
            const cacheBase = env[key];
            if (cacheBase) rendererEnv[key] = path.join(cacheBase, metalBackend.toLowerCase());
            else if (cacheBase === "") delete rendererEnv[key];
        }
    }

    return applyMacOSDiagnosticEngineEnv(
        applyMacOSMinimalFpsWorkaroundEnv({
            ...rendererEnv,
            // User default 2026-10-09; explicit 0 remains available for comparisons.
            BAR_ZINK_MVK_DISABLE_ASYNC_WAIT: env.BAR_ZINK_MVK_DISABLE_ASYNC_WAIT ?? "1",
            [MACOS_VULKAN_BACKEND_ENV]: runtimePaths.vulkanBackend,
            DYLD_LIBRARY_PATH: [runtimePaths.sdl3LibPath, runtimePaths.mesaZinkLibPath, runtimePaths.vulkanLoaderLibPath, runtimePaths.vulkanBackendLibPath].join(path.delimiter),
            VK_DRIVER_FILES: runtimePaths.vulkanBackendICDPath,
            VK_ICD_FILENAMES: runtimePaths.vulkanBackendICDPath,
            MESA_LOADER_DRIVER_OVERRIDE: "zink",
            GALLIUM_DRIVER: "zink",
            EGL_PLATFORM: "cocoa",
            MESA_GL_VERSION_OVERRIDE: "4.6COMPAT",
            MESA_GLSL_VERSION_OVERRIDE: "460",
            [MACOS_VULKAN_LOADER_BUNDLE_ONLY_ENV]: "1",
            FONTCONFIG_FILE: runtimePaths.fontconfigFilePath,
            FONTCONFIG_PATH: runtimePaths.fontconfigConfigDirPath,
            XDG_CACHE_HOME: path.join(getMacOSWritableDataPath(options), "cache", ...(metalBackend ? [metalBackend.toLowerCase()] : [])),
        })
    );
}

export function resolveEngineVersionPath(options: NativeEngineResolverOptions): string {
    const pathExists = options.pathExists ?? fs.existsSync;
    const searchPaths = getEngineVersionSearchPaths(options);
    return searchPaths.find((enginePath) => pathExists(enginePath)) ?? searchPaths[0];
}

export function resolveNativeEngineRunner(options: NativeEngineResolverOptions): NativeEngineRunner {
    const platform = options.platform ?? process.platform;
    const binaryFileName = getEngineBinaryFileName(platform);
    const spawnCommand = getEngineSpawnCommand(platform);
    const pathExists = options.pathExists ?? fs.existsSync;
    const searchPaths = getEngineVersionSearchPaths(options);

    if (platform !== "darwin") {
        return {
            enginePath: searchPaths[0],
            binaryFileName,
            spawnCommand,
        };
    }

    const enginePath = searchPaths.find((candidate) => pathExists(path.join(candidate, binaryFileName)));
    if (!enginePath) {
        throw new Error(
            [
                `Native macOS engine ${options.engineVersion} is unavailable.`,
                `Expected ${binaryFileName} at one of: ${searchPaths.join(", ")}.`,
                "The macOS lobby must not use engine_linux64; bundle or install a native macOS engine artifact first.",
            ].join(" ")
        );
    }

    return {
        enginePath,
        binaryFileName,
        spawnCommand,
    };
}

export function resolvePrDownloaderPath(options: NativeEngineResolverOptions): string {
    const platform = options.platform ?? process.platform;
    const binaryFileName = getPrDownloaderBinaryFileName(platform);
    const pathExists = options.pathExists ?? fs.existsSync;
    const searchPaths = getEngineVersionSearchPaths(options);

    if (platform !== "darwin") {
        return path.join(searchPaths[0], binaryFileName);
    }

    const prDownloaderPath = searchPaths.map((candidate) => path.join(candidate, binaryFileName)).find(pathExists);
    if (!prDownloaderPath) {
        throw new Error(
            [
                `Native macOS pr-downloader for engine ${options.engineVersion} is unavailable.`,
                `Expected ${binaryFileName} at one of: ${searchPaths.join(", ")}.`,
                "pr-downloader is part of the native macOS engine artifact and writes downloads to the mutable assets path.",
            ].join(" ")
        );
    }

    return prDownloaderPath;
}
