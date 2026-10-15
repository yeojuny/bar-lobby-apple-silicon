// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import path from "path";
import fs from "fs";
import os from "os";
import { createHash } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
    getEngineRootSearchPaths,
    getEngineVersionSearchPaths,
    getMacOSLuaUIOverlayPath,
    getMacOSGraphicsRuntimePaths,
    getNativeEngineDataDirDiagnostics,
    getNativeEngineProcessEnvDiagnostics,
    getNativeEngineProcessEnv,
    getMacOSRendererPreference,
    setMacOSRendererPreference,
    MACOS_DIAGNOSTIC_ENGINE_ENV_GATE,
    MACOS_DIAGNOSTIC_ZINK_DEBUG_VALUE,
    MACOS_KOSMICKRISP_BACKEND_MARKER,
    MACOS_METAL_BACKEND_ENV,
    MACOS_METAL_BACKEND_REQUESTED_ENV,
    MACOS_MOLTENVK_METAL4_ENV,
    MACOS_RENDERER_CONFIG_FILE_NAME,
    MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV,
    MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV,
    MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE,
    MACOS_NATIVE_ENGINE_DATA_DIR_DIAGNOSTIC_PROBE,
    MACOS_NATIVE_ENGINE_ENV_DIAGNOSTIC_PROBE,
    MACOS_VULKAN_BACKEND_ENV,
    MACOS_VULKAN_LOADER_BUNDLE_ONLY_ENV,
    getPrDownloaderBinaryFileName,
    getSpringDataDir,
    resolveNativeEngineRunner,
    resolveEngineVersionPath,
    resolvePrDownloaderPath,
    prepareMacOSLuaUIOverlayForLaunch,
} from "@main/config/native-engine-runner";
import type { NativeEngineProcessEnvOptions } from "@main/config/native-engine-runner";

const assetsPath = "/Users/test/Library/Application Support/BeyondAllReason/assets";
const writeDataPath = "/Users/test/Library/Application Support/BeyondAllReason/data";
const bundledAssetsPath = "/Applications/BAR.app/Contents/Resources/bundled-assets";
const bundledEnginePath = path.join(bundledAssetsPath, "engine", "2025.06.21");

describe("native engine runner contract", () => {
    it("searches mutable assets before immutable bundled assets", () => {
        expect(getEngineRootSearchPaths({ assetsPath, bundledAssetsPath })).toEqual([path.join(assetsPath, "engine"), path.join(bundledAssetsPath, "engine")]);
        expect(getEngineVersionSearchPaths({ engineVersion: "2025.06.21", assetsPath, bundledAssetsPath })).toEqual([
            path.join(assetsPath, "engine", "2025.06.21"),
            path.join(bundledAssetsPath, "engine", "2025.06.21"),
        ]);
    });

    it.each(["2026.07.04", "2026.09.10-0-g694e9df7", "2025.01.3-rc1", "105.1.1-2449-gf1234a9 BAR105", "local engine candidate"])("preserves a valid engine directory %s and mutable-first resolution", (engineVersion) => {
        const mutableEnginePath = path.join(assetsPath, "engine", engineVersion);
        const options = { engineVersion, assetsPath, bundledAssetsPath, platform: "darwin" as const, pathExists: () => true };
        expect(getEngineVersionSearchPaths(options)).toEqual([mutableEnginePath, path.join(bundledAssetsPath, "engine", engineVersion)]);
        expect(resolveEngineVersionPath(options)).toBe(mutableEnginePath);
        expect(resolveNativeEngineRunner(options).enginePath).toBe(mutableEnginePath);
        expect(resolvePrDownloaderPath(options)).toBe(path.join(mutableEnginePath, "pr-downloader"));
    });

    it.each(["", "   ", ".", "..", " .. ", "../2026.07.04", "2026.07.04/../other", "2026.07.04\\spring", "/tmp/engine", "C:", "C:engine", "C:\\engine", "\\\\server\\engine", "2026\u0000.07", "2026\n.07", "2026\u007f.07", "2026\u2028.07"])("rejects unsafe engine directories in every shared resolver: %j", (engineVersion) => {
        const options = { engineVersion, assetsPath, bundledAssetsPath, platform: "darwin" as const, pathExists: () => true };
        expect(() => getEngineVersionSearchPaths(options)).toThrow(/Invalid engine version/);
        expect(() => resolveEngineVersionPath(options)).toThrow(/Invalid engine version/);
        expect(() => resolveNativeEngineRunner(options)).toThrow(/Invalid engine version/);
        expect(() => resolvePrDownloaderPath(options)).toThrow(/Invalid engine version/);
        expect(() => resolveNativeEngineRunner({ ...options, platform: "win32" })).toThrow(/Invalid engine version/);
    });

    it("keeps the native macOS engine binary named spring", () => {
        const bundledSpringPath = path.join(bundledAssetsPath, "engine", "2025.06.21", "spring");
        const runner = resolveNativeEngineRunner({
            engineVersion: "2025.06.21",
            assetsPath,
            bundledAssetsPath,
            platform: "darwin",
            pathExists: (filePath) => filePath === bundledSpringPath,
        });

        expect(runner).toEqual({
            enginePath: path.dirname(bundledSpringPath),
            binaryFileName: "spring",
            spawnCommand: "./spring",
        });
    });

    it("treats pr-downloader as part of the native macOS engine artifact", () => {
        const bundledPrDownloaderPath = path.join(bundledAssetsPath, "engine", "2025.06.21", "pr-downloader");

        expect(getPrDownloaderBinaryFileName("darwin")).toBe("pr-downloader");
        expect(
            resolvePrDownloaderPath({
                engineVersion: "2025.06.21",
                assetsPath,
                bundledAssetsPath,
                platform: "darwin",
                pathExists: (filePath) => filePath === bundledPrDownloaderPath,
            })
        ).toBe(bundledPrDownloaderPath);
    });

    it("refuses to silently fall back when the macOS engine is unavailable", () => {
        expect(() =>
            resolveNativeEngineRunner({
                engineVersion: "2025.06.21",
                assetsPath,
                bundledAssetsPath,
                platform: "darwin",
                pathExists: () => false,
            })
        ).toThrow(/must not use engine_linux64/);
    });

    it("passes mutable assets, immutable bundled assets, and the selected engine path through SPRING_DATADIR", () => {
        expect(getSpringDataDir({ assetsPath, bundledAssetsPath, enginePath: bundledEnginePath }, (filePath) => filePath === bundledAssetsPath || filePath === bundledEnginePath)).toBe(
            `${assetsPath}${path.delimiter}${bundledAssetsPath}${path.delimiter}${bundledEnginePath}`
        );
    });

    it("can keep bundled overlay content out of SPRING_DATADIR while still exposing the selected engine path", () => {
        expect(
            getSpringDataDir(
                {
                    assetsPath,
                    bundledAssetsPath,
                    enginePath: bundledEnginePath,
                    includeBundledAssetsInSpringDataDir: false,
                },
                (filePath) => filePath === bundledAssetsPath || filePath === bundledEnginePath
            )
        ).toBe(`${assetsPath}${path.delimiter}${bundledEnginePath}`);
    });

    it("can expose bundled engine support data without exposing bundled Lua overlays", () => {
        const engineFontsPath = path.join(bundledAssetsPath, "engine-fonts");
        const fontsPath = path.join(bundledAssetsPath, "fonts");

        expect(
            getSpringDataDir(
                {
                    assetsPath,
                    bundledAssetsPath,
                    enginePath: bundledEnginePath,
                    includeBundledAssetsInSpringDataDir: false,
                    includeBundledEngineSupportInSpringDataDir: true,
                },
                (filePath) => [bundledAssetsPath, engineFontsPath, fontsPath, bundledEnginePath].includes(filePath)
            )
        ).toBe(`${assetsPath}${path.delimiter}${engineFontsPath}${path.delimiter}${fontsPath}${path.delimiter}${bundledEnginePath}`);
    });

    it("can expose only the bundled macOS LuaUI overlay for Chobby multiplayer", () => {
        const overlayPath = getMacOSLuaUIOverlayPath(bundledAssetsPath, "bar-chobby");
        const engineFontsPath = path.join(bundledAssetsPath, "engine-fonts");
        const fontsPath = path.join(bundledAssetsPath, "fonts");

        expect(
            getSpringDataDir(
                {
                    assetsPath,
                    bundledAssetsPath,
                    enginePath: bundledEnginePath,
                    includeBundledAssetsInSpringDataDir: false,
                    includeBundledEngineSupportInSpringDataDir: true,
                    includeBundledMacOSLuaUIOverlayInSpringDataDir: true,
                    macOSLuaUIOverlayLane: "bar-chobby",
                },
                (filePath) => [bundledAssetsPath, overlayPath, path.join(overlayPath, "LuaUI"), engineFontsPath, fontsPath, bundledEnginePath].includes(filePath)
            )
        ).toBe(`${overlayPath}${path.delimiter}${assetsPath}${path.delimiter}${engineFontsPath}${path.delimiter}${fontsPath}${path.delimiter}${bundledEnginePath}`);
    });

    it("keeps lane overlays immutable and quarantines known legacy writable copies", async () => {
        const tempDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "bar-luaui-overlay-"));
        try {
            const localBundledAssetsPath = path.join(tempDir, "BAR.app", "Contents", "Resources", "bundled-assets");
            const localWriteDataPath = path.join(tempDir, "data");
            const overlayPath = path.join(localBundledAssetsPath, "macos-luaui-overlays", "bar-chobby");
            const overlayWidgetPath = path.join(overlayPath, "LuaUI", "Widgets", "gfx_decals_gl4.lua");
            const legacyWidgetPath = path.join(localWriteDataPath, "LuaUI", "Widgets", "gui_unit_stats.lua");
            const customWidgetPath = path.join(localWriteDataPath, "LuaUI", "Widgets", "gui_pip.lua");
            const legacyText = "legacy\n";
            const legacyHash = createHash("sha256").update(legacyText).digest("hex");
            await fs.promises.mkdir(path.dirname(overlayWidgetPath), { recursive: true });
            await fs.promises.writeFile(overlayWidgetPath, "return true\n", "utf-8");
            await fs.promises.writeFile(
                path.join(overlayPath, "manifest.json"),
                JSON.stringify({ schemaVersion: 1, lane: "bar-chobby", files: ["LuaUI/Widgets/gfx_decals_gl4.lua"] }),
                "utf-8"
            );
            await fs.promises.mkdir(path.dirname(legacyWidgetPath), { recursive: true });
            await fs.promises.writeFile(legacyWidgetPath, legacyText, "utf-8");
            await fs.promises.writeFile(customWidgetPath, "user-customized\n", "utf-8");
            await fs.promises.writeFile(
                path.join(localBundledAssetsPath, "macos-luaui-overlays", "legacy-managed-files.json"),
                JSON.stringify({
                    schemaVersion: 1,
                    files: [
                        { path: "LuaUI/Widgets/gui_unit_stats.lua", sha256: [legacyHash] },
                        { path: "LuaUI/Widgets/gui_pip.lua", sha256: [legacyHash] },
                    ],
                }),
                "utf-8"
            );

            const result = await prepareMacOSLuaUIOverlayForLaunch({
                bundledAssetsPath: localBundledAssetsPath,
                writeDataPath: localWriteDataPath,
                lane: "bar-chobby",
                platform: "darwin",
            });

            expect(result.prepared).toBe(true);
            expect(result.lane).toBe("bar-chobby");
            expect(result.quarantinedFiles).toEqual(["LuaUI/Widgets/gui_unit_stats.lua"]);
            expect(result.preservedFiles).toEqual(["LuaUI/Widgets/gui_pip.lua"]);
            await expect(fs.promises.readFile(customWidgetPath, "utf-8")).resolves.toBe("user-customized\n");
            await expect(fs.promises.stat(legacyWidgetPath)).rejects.toThrow();
            await expect(fs.promises.readFile(overlayWidgetPath, "utf-8")).resolves.toBe("return true\n");
        } finally {
            await fs.promises.rm(tempDir, { recursive: true, force: true });
        }
    });

    it("adds the bundled macOS Mesa/Zink/MoltenVK runtime environment without the minimal-FPS fallback by default", () => {
        const runtimePaths = getMacOSGraphicsRuntimePaths(bundledAssetsPath);
        const requiredFiles = new Set([
            bundledAssetsPath,
            bundledEnginePath,
            path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
            path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
            path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
            path.join(runtimePaths.moltenVKLibPath, "libMoltenVK.dylib"),
            runtimePaths.moltenVKICDPath,
            runtimePaths.fontconfigFilePath,
        ]);

        const env = getNativeEngineProcessEnv({
            assetsPath,
            bundledAssetsPath,
            enginePath: bundledEnginePath,
            writeDataPath,
            platform: "darwin",
            baseEnv: {
                DYLD_LIBRARY_PATH: "/tmp/old-dyld",
                DYLD_FALLBACK_LIBRARY_PATH: "/tmp/fallback",
                VK_ADD_DRIVER_FILES: "/tmp/other-driver.json",
                ZINK_DEBUG: "flushsync",
                MESA_GLTHREAD: "0",
                GALLIUM_THREAD: "0",
            },
            pathExists: (filePath) => requiredFiles.has(filePath),
        });

        expect(env.SPRING_DATADIR).toBe(`${assetsPath}${path.delimiter}${bundledAssetsPath}${path.delimiter}${bundledEnginePath}`);
        expect(env[MACOS_VULKAN_BACKEND_ENV]).toBe("moltenvk");
        expect(env.DYLD_LIBRARY_PATH).toBe([runtimePaths.sdl3LibPath, runtimePaths.mesaZinkLibPath, runtimePaths.vulkanLoaderLibPath, runtimePaths.moltenVKLibPath].join(path.delimiter));
        expect(env.VK_DRIVER_FILES).toBe(runtimePaths.moltenVKICDPath);
        expect(env.VK_ICD_FILENAMES).toBe(runtimePaths.moltenVKICDPath);
        expect(env.MESA_LOADER_DRIVER_OVERRIDE).toBe("zink");
        expect(env.GALLIUM_DRIVER).toBe("zink");
        expect(env.EGL_PLATFORM).toBe("cocoa");
        expect(env.MESA_GL_VERSION_OVERRIDE).toBe("4.6COMPAT");
        expect(env.MESA_GLSL_VERSION_OVERRIDE).toBe("460");
        expect(env[MACOS_VULKAN_LOADER_BUNDLE_ONLY_ENV]).toBe("1");
        expect(env.FONTCONFIG_FILE).toBe(runtimePaths.fontconfigFilePath);
        expect(env.FONTCONFIG_PATH).toBe(runtimePaths.fontconfigConfigDirPath);
        expect(env.XDG_CACHE_HOME).toBe(path.join(writeDataPath, "cache", "metal3"));
        expect(env.VK_ADD_DRIVER_FILES).toBeUndefined();
        expect(env.DYLD_FALLBACK_LIBRARY_PATH).toBeUndefined();
        expect(env.ZINK_DEBUG).toBeUndefined();
        expect(env.MESA_GLTHREAD).toBeUndefined();
        expect(env.GALLIUM_THREAD).toBeUndefined();
    });

    it("keeps Chobby multiplayer's SPRING_DATADIR on official content plus bundled engine support and the exact engine", () => {
        const runtimePaths = getMacOSGraphicsRuntimePaths(bundledAssetsPath);
        const engineFontsPath = path.join(bundledAssetsPath, "engine-fonts");
        const fontsPath = path.join(bundledAssetsPath, "fonts");
        const overlayPath = getMacOSLuaUIOverlayPath(bundledAssetsPath, "bar-chobby");
        const requiredFiles = new Set([
            bundledAssetsPath,
            overlayPath,
            path.join(overlayPath, "LuaUI"),
            engineFontsPath,
            fontsPath,
            bundledEnginePath,
            path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
            path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
            path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
            path.join(runtimePaths.moltenVKLibPath, "libMoltenVK.dylib"),
            runtimePaths.moltenVKICDPath,
            runtimePaths.fontconfigFilePath,
        ]);

        const env = getNativeEngineProcessEnv({
            assetsPath,
            bundledAssetsPath,
            enginePath: bundledEnginePath,
            includeBundledAssetsInSpringDataDir: false,
            includeBundledEngineSupportInSpringDataDir: true,
            includeBundledMacOSLuaUIOverlayInSpringDataDir: true,
                    macOSLuaUIOverlayLane: "bar-chobby",
            writeDataPath,
            platform: "darwin",
            baseEnv: {},
            pathExists: (filePath) => requiredFiles.has(filePath),
        });

        expect(env.SPRING_DATADIR).toBe(`${overlayPath}${path.delimiter}${assetsPath}${path.delimiter}${engineFontsPath}${path.delimiter}${fontsPath}${path.delimiter}${bundledEnginePath}`);
        expect(env[MACOS_VULKAN_BACKEND_ENV]).toBe("moltenvk");
        expect(env.ZINK_DEBUG).toBeUndefined();
    });

    it("can select the bundled macOS Mesa/Zink/KosmicKrisp runtime by app marker", () => {
        const runtimePaths = getMacOSGraphicsRuntimePaths(bundledAssetsPath, "kosmickrisp");
        const kosmicKrispMarkerPath = path.join(path.dirname(bundledAssetsPath), MACOS_KOSMICKRISP_BACKEND_MARKER);
        const requiredFiles = new Set([
            bundledAssetsPath,
            bundledEnginePath,
            path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
            path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
            path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
            path.join(runtimePaths.kosmicKrispLibPath, "libvulkan_kosmickrisp.dylib"),
            runtimePaths.kosmicKrispICDPath,
            runtimePaths.fontconfigFilePath,
            kosmicKrispMarkerPath,
        ]);

        const env = getNativeEngineProcessEnv({
            assetsPath,
            bundledAssetsPath,
            enginePath: bundledEnginePath,
            writeDataPath,
            platform: "darwin",
            baseEnv: {},
            pathExists: (filePath) => requiredFiles.has(filePath),
        });

        expect(env[MACOS_VULKAN_BACKEND_ENV]).toBe("kosmickrisp");
        expect(env.DYLD_LIBRARY_PATH).toBe([runtimePaths.sdl3LibPath, runtimePaths.mesaZinkLibPath, runtimePaths.vulkanLoaderLibPath, runtimePaths.kosmicKrispLibPath].join(path.delimiter));
        expect(env.VK_DRIVER_FILES).toBe(runtimePaths.kosmicKrispICDPath);
        expect(env.VK_ICD_FILENAMES).toBe(runtimePaths.kosmicKrispICDPath);
    });

    it("can explicitly enable the minimal-FPS fallback for backend A/B diagnostics", () => {
        const runtimePaths = getMacOSGraphicsRuntimePaths(bundledAssetsPath);
        const requiredFiles = new Set([
            bundledAssetsPath,
            bundledEnginePath,
            path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
            path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
            path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
            path.join(runtimePaths.moltenVKLibPath, "libMoltenVK.dylib"),
            runtimePaths.moltenVKICDPath,
            runtimePaths.fontconfigFilePath,
        ]);

        const env = getNativeEngineProcessEnv({
            assetsPath,
            bundledAssetsPath,
            enginePath: bundledEnginePath,
            writeDataPath,
            platform: "darwin",
            baseEnv: {
                [MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV]: "1",
                ZINK_DEBUG: "flushsync",
                MESA_GLTHREAD: "0",
                GALLIUM_THREAD: "0",
            },
            pathExists: (filePath) => requiredFiles.has(filePath),
        });

        expect(env[MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV]).toBe("1");
        expect(env.ZINK_DEBUG).toBe(MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE);
        expect(env.MESA_GLTHREAD).toBeUndefined();
        expect(env.GALLIUM_THREAD).toBeUndefined();
    });

    it("keeps the explicit macOS diagnostic gate compatible with the minimal-FPS workaround", () => {
        const runtimePaths = getMacOSGraphicsRuntimePaths(bundledAssetsPath);
        const requiredFiles = new Set([
            bundledAssetsPath,
            bundledEnginePath,
            path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
            path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
            path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
            path.join(runtimePaths.moltenVKLibPath, "libMoltenVK.dylib"),
            runtimePaths.moltenVKICDPath,
            runtimePaths.fontconfigFilePath,
        ]);

        const env = getNativeEngineProcessEnv({
            assetsPath,
            bundledAssetsPath,
            enginePath: bundledEnginePath,
            writeDataPath,
            platform: "darwin",
            baseEnv: {
                [MACOS_DIAGNOSTIC_ENGINE_ENV_GATE]: "1",
                ZINK_DEBUG: "flushsync",
                MESA_GLTHREAD: "0",
                GALLIUM_THREAD: "0",
            },
            pathExists: (filePath) => requiredFiles.has(filePath),
        });

        expect(env[MACOS_DIAGNOSTIC_ENGINE_ENV_GATE]).toBe("1");
        expect(env.ZINK_DEBUG).toBe(MACOS_MINIMAL_FPS_WORKAROUND_ZINK_DEBUG_VALUE);
        expect(env.MESA_GLTHREAD).toBeUndefined();
        expect(env.GALLIUM_THREAD).toBeUndefined();
    });

    it("does not treat non-1 opt-in values as enabling the minimal-FPS fallback", () => {
        const runtimePaths = getMacOSGraphicsRuntimePaths(bundledAssetsPath);
        const requiredFiles = new Set([
            bundledAssetsPath,
            bundledEnginePath,
            path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
            path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
            path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
            path.join(runtimePaths.moltenVKLibPath, "libMoltenVK.dylib"),
            runtimePaths.moltenVKICDPath,
            runtimePaths.fontconfigFilePath,
        ]);

        const env = getNativeEngineProcessEnv({
            assetsPath,
            bundledAssetsPath,
            enginePath: bundledEnginePath,
            writeDataPath,
            platform: "darwin",
            baseEnv: {
                [MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV]: "true",
                ZINK_DEBUG: "flushsync",
            },
            pathExists: (filePath) => requiredFiles.has(filePath),
        });

        expect(env[MACOS_MINIMAL_FPS_WORKAROUND_ENABLE_ENV]).toBe("true");
        expect(env.ZINK_DEBUG).toBeUndefined();
    });

    it("formats the temporary macOS native engine env diagnostic probe", () => {
        expect(MACOS_NATIVE_ENGINE_ENV_DIAGNOSTIC_PROBE).toBe("MACOS_DIAGNOSTIC_PROBE native-engine-env");
        expect(
            getNativeEngineProcessEnvDiagnostics({
                [MACOS_DIAGNOSTIC_ENGINE_ENV_GATE]: "1",
                [MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV]: "1",
                SPRING_DATADIR: "/tmp/data",
                MESA_LOADER_DRIVER_OVERRIDE: "zink",
                ZINK_DEBUG: MACOS_DIAGNOSTIC_ZINK_DEBUG_VALUE,
            })
        ).toEqual(
            expect.objectContaining({
                [MACOS_DIAGNOSTIC_ENGINE_ENV_GATE]: "1",
                [MACOS_MINIMAL_FPS_WORKAROUND_DISABLE_ENV]: "1",
                SPRING_DATADIR: "/tmp/data",
                MESA_LOADER_DRIVER_OVERRIDE: "zink",
                ZINK_DEBUG: MACOS_DIAGNOSTIC_ZINK_DEBUG_VALUE,
                MESA_GLTHREAD: "<unset>",
                GALLIUM_THREAD: "<unset>",
            })
        );
    });

    it("formats the temporary macOS native engine data-dir diagnostic probe", () => {
        const overlayPath = getMacOSLuaUIOverlayPath(bundledAssetsPath, "bar-chobby");
        const springDataDir = [overlayPath, assetsPath, bundledEnginePath].join(path.delimiter);

        expect(MACOS_NATIVE_ENGINE_DATA_DIR_DIAGNOSTIC_PROBE).toBe("MACOS_DIAGNOSTIC_PROBE native-engine-data-dirs");
        expect(
            getNativeEngineDataDirDiagnostics(
                {
                    SPRING_DATADIR: springDataDir,
                },
                (filePath) => [overlayPath, path.join(overlayPath, "LuaUI"), assetsPath, bundledEnginePath, path.join(bundledEnginePath, "spring")].includes(filePath),
                "darwin"
            )
        ).toEqual([
            expect.objectContaining({
                index: 0,
                path: overlayPath,
                exists: true,
                hasLuaUI: true,
                hasLuaRules: false,
                hasEngineBinary: false,
            }),
            expect.objectContaining({
                index: 1,
                path: assetsPath,
                exists: true,
                hasLuaUI: false,
            }),
            expect.objectContaining({
                index: 2,
                path: bundledEnginePath,
                exists: true,
                hasEngineBinary: true,
            }),
        ]);
    });

    it("preserves the existing Linux engine path and SPRING_DATADIR shape", () => {
        const runner = resolveNativeEngineRunner({
            engineVersion: "2025.06.21",
            assetsPath,
            platform: "linux",
            pathExists: () => false,
        });

        expect(runner).toEqual({
            enginePath: path.join(assetsPath, "engine", "2025.06.21"),
            binaryFileName: "spring",
            spawnCommand: "./spring",
        });
        expect(getSpringDataDir({ assetsPath }, () => false)).toBe(assetsPath);
    });
});

describe("bundled macOS MoltenVK renderer preferences", () => {
    let tempDir: string;
    let localWriteDataPath: string;
    let configPath: string;

    beforeEach(() => {
        tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "bar-renderer-preference-"));
        localWriteDataPath = path.join(tempDir, "data");
        fs.mkdirSync(localWriteDataPath);
        configPath = path.join(localWriteDataPath, MACOS_RENDERER_CONFIG_FILE_NAME);
    });

    afterEach(() => {
        vi.restoreAllMocks();
        fs.rmSync(tempDir, { recursive: true, force: true });
    });

    function launchEnv(overrides: Partial<NativeEngineProcessEnvOptions> = {}) {
        const runtimePaths = getMacOSGraphicsRuntimePaths(bundledAssetsPath);
        const requiredFiles = new Set([
            bundledAssetsPath,
            bundledEnginePath,
            path.join(runtimePaths.sdl3LibPath, "libSDL3.0.dylib"),
            path.join(runtimePaths.mesaZinkLibPath, "libEGL.1.dylib"),
            path.join(runtimePaths.vulkanLoaderLibPath, "libvulkan.1.dylib"),
            path.join(runtimePaths.moltenVKLibPath, "libMoltenVK.dylib"),
            runtimePaths.moltenVKICDPath,
            runtimePaths.fontconfigFilePath,
        ]);
        return getNativeEngineProcessEnv({
            assetsPath,
            bundledAssetsPath,
            enginePath: bundledEnginePath,
            writeDataPath: localWriteDataPath,
            platform: "darwin",
            baseEnv: {},
            pathExists: (filePath) => requiredFiles.has(filePath),
            ...overrides,
        });
    }

    it("defaults to Metal3 without creating a preference or cache and preserves wait/cost defaults", () => {
        const env = launchEnv();
        expect(env[MACOS_MOLTENVK_METAL4_ENV]).toBe("0");
        expect(env[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBe("METAL3");
        expect(env.XDG_CACHE_HOME).toBe(path.join(localWriteDataPath, "cache", "metal3"));
        expect(env.BAR_ZINK_MVK_DISABLE_ASYNC_WAIT).toBe("1");
        expect(env.MVK_CONFIG_BACKEND_COST_STATS).toBeUndefined();
        expect(fs.readdirSync(localWriteDataPath)).toEqual([]);
    });

    it.each(["METAL3", "METAL4"] as const)("reads the shared %s file preference without modifying it", (renderer) => {
        const content = JSON.stringify({ renderer });
        fs.writeFileSync(configPath, content);
        for (const lane of ["bar-lobby", "bar-chobby"] as const) {
            const env = launchEnv({ macOSLuaUIOverlayLane: lane });
            expect(env[MACOS_MOLTENVK_METAL4_ENV]).toBe(renderer === "METAL4" ? "1" : "0");
            expect(env[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBe(renderer);
            expect(env.XDG_CACHE_HOME).toBe(path.join(localWriteDataPath, "cache", renderer.toLowerCase()));
        }
        expect(fs.readFileSync(configPath, "utf-8")).toBe(content);
        expect(fs.readdirSync(localWriteDataPath)).toEqual([MACOS_RENDERER_CONFIG_FILE_NAME]);
    });

    it("supports an explicit configuration path ahead of the default data file", () => {
        fs.writeFileSync(configPath, '{"renderer":"METAL3"}');
        const explicitPath = path.join(tempDir, "chosen-renderer.json");
        fs.writeFileSync(explicitPath, '{"renderer":"METAL4"}');
        expect(launchEnv({ rendererConfigPath: explicitPath })[MACOS_MOLTENVK_METAL4_ENV]).toBe("1");
        expect(fs.readFileSync(configPath, "utf-8")).toBe('{"renderer":"METAL3"}');
    });

    it.each(["METAL3", "METAL4"] as const)("prefers explicit BAR_METAL_BACKEND=%s over both other sources", (renderer) => {
        fs.writeFileSync(configPath, JSON.stringify({ renderer: renderer === "METAL4" ? "METAL3" : "METAL4" }));
        const env = launchEnv({ baseEnv: {
            [MACOS_METAL_BACKEND_ENV]: renderer,
            [MACOS_MOLTENVK_METAL4_ENV]: renderer === "METAL4" ? "0" : "1",
        } });
        expect(env[MACOS_MOLTENVK_METAL4_ENV]).toBe(renderer === "METAL4" ? "1" : "0");
        expect(env[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBe(renderer);
    });

    it.each(["0", "1"])("preserves the legacy explicit MVK_CONFIG_USE_METAL4=%s override ahead of the file", (value) => {
        fs.writeFileSync(configPath, JSON.stringify({ renderer: value === "1" ? "METAL3" : "METAL4" }));
        const env = launchEnv({ baseEnv: { [MACOS_MOLTENVK_METAL4_ENV]: value } });
        expect(env[MACOS_MOLTENVK_METAL4_ENV]).toBe(value);
        expect(env[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBe(value === "1" ? "METAL4" : "METAL3");
    });

    it("lets a valid environment override recover from an invalid preference file", () => {
        fs.writeFileSync(configPath, "broken JSON");
        expect(launchEnv({ baseEnv: { [MACOS_METAL_BACKEND_ENV]: "METAL3" } })[MACOS_MOLTENVK_METAL4_ENV]).toBe("0");
        expect(launchEnv({ baseEnv: { [MACOS_MOLTENVK_METAL4_ENV]: "1" } })[MACOS_MOLTENVK_METAL4_ENV]).toBe("1");
    });

    it.each(["", "metal4", "1", "METAL5", " METAL3"])("rejects invalid BAR_METAL_BACKEND=%j clearly", (value) => {
        expect(() => launchEnv({ baseEnv: { [MACOS_METAL_BACKEND_ENV]: value } })).toThrow(/BAR_METAL_BACKEND must be METAL3 or METAL4/);
    });

    it.each(["", "true", "METAL4", "2"])("rejects invalid legacy overrides even when BAR_METAL_BACKEND is valid: %j", (value) => {
        expect(() => launchEnv({ baseEnv: { [MACOS_METAL_BACKEND_ENV]: "METAL3", [MACOS_MOLTENVK_METAL4_ENV]: value } })).toThrow(/MVK_CONFIG_USE_METAL4 must be 0 or 1/);
    });

    it.each(["", "{", "null", "[]", "{}", '"METAL4"', '{"renderer":4}', '{"renderer":"metal4"}', '{"renderer":"METAL3","unexpected":true}'])("rejects invalid preference content with a bounded, useful error: %j", (content) => {
        fs.writeFileSync(configPath, content);
        expect(() => launchEnv()).toThrow(/Invalid renderer preference.*renderer.*METAL3.*METAL4/);
    });

    it("accepts a valid preference at the 4 KiB limit and rejects larger metadata without echoing it", () => {
        fs.writeFileSync(configPath, '{"renderer":"METAL4"}'.padEnd(4096, " "));
        expect(launchEnv()[MACOS_MOLTENVK_METAL4_ENV]).toBe("1");
        const oversized = "sensitive-sample-content".repeat(200);
        fs.writeFileSync(configPath, oversized);
        let caught: unknown;
        try { launchEnv(); } catch (error) { caught = error; }
        expect(caught).toBeInstanceOf(Error);
        expect((caught as Error).message).toMatch(/at most 4096 bytes/);
        expect((caught as Error).message).not.toContain("sensitive-sample-content");
        expect((caught as Error).message.length).toBeLessThan(300);
        expect(fs.readFileSync(configPath, "utf-8")).toBe(oversized);
    });

    it("rejects non-file preferences without creating or replacing them", () => {
        fs.mkdirSync(configPath);
        expect(() => launchEnv()).toThrow(/regular file/);
        expect(fs.statSync(configPath).isDirectory()).toBe(true);
    });

    it("reads once per launch, separates backend caches and never mutates prior results or base/global environment", () => {
        const baseEnv = Object.freeze({ KEEP_ME: "unchanged", XDG_CACHE_HOME: "/tmp/old-cache" });
        const beforeGlobal = { ...process.env };
        fs.writeFileSync(configPath, '{"renderer":"METAL3"}');
        const first = launchEnv({ baseEnv });
        fs.writeFileSync(configPath, '{"renderer":"METAL4"}');
        const second = launchEnv({ baseEnv });
        fs.writeFileSync(configPath, '{"renderer":"METAL3"}');
        const third = launchEnv({ baseEnv });
        expect(first[MACOS_MOLTENVK_METAL4_ENV]).toBe("0");
        expect(second[MACOS_MOLTENVK_METAL4_ENV]).toBe("1");
        expect(third[MACOS_MOLTENVK_METAL4_ENV]).toBe("0");
        expect(first.XDG_CACHE_HOME).not.toBe(second.XDG_CACHE_HOME);
        expect(first.XDG_CACHE_HOME).toBe(third.XDG_CACHE_HOME);
        expect(baseEnv).toEqual({ KEEP_ME: "unchanged", XDG_CACHE_HOME: "/tmp/old-cache" });
        expect(process.env).toEqual(beforeGlobal);
        expect(second.KEEP_ME).toBe("unchanged");
    });

    it.each([
        { MESA_SHADER_CACHE_DIR: "/tmp/chosen-shader-cache" },
        { MESA_GLSL_CACHE_DIR: "/tmp/chosen-legacy-cache" },
        { MESA_SHADER_CACHE_DIR: "/tmp/new cache", MESA_GLSL_CACHE_DIR: "/tmp/old cache" },
    ])("scopes each user-provided Mesa cache base once for both backends: %j", (overrides) => {
        const baseEnv = Object.freeze({ ...overrides });
        for (const renderer of ["METAL3", "METAL4", "METAL3"] as const) {
            fs.writeFileSync(configPath, JSON.stringify({ renderer }));
            const env = launchEnv({ baseEnv });
            for (const key of ["MESA_SHADER_CACHE_DIR", "MESA_GLSL_CACHE_DIR"] as const) {
                const cacheBase = overrides[key];
                expect(env[key]).toBe(cacheBase ? path.join(cacheBase, renderer.toLowerCase()) : undefined);
            }
            expect(env.XDG_CACHE_HOME).toBe(path.join(localWriteDataPath, "cache", renderer.toLowerCase()));
        }
        expect(baseEnv).toEqual(overrides);
    });

    it("removes empty Mesa cache overrides only from the child environment so XDG can apply", () => {
        const baseEnv = Object.freeze({ MESA_SHADER_CACHE_DIR: "", MESA_GLSL_CACHE_DIR: "" });
        const env = launchEnv({ baseEnv });
        expect(env.MESA_SHADER_CACHE_DIR).toBeUndefined();
        expect(env.MESA_GLSL_CACHE_DIR).toBeUndefined();
        expect(env.XDG_CACHE_HOME).toBe(path.join(localWriteDataPath, "cache", "metal3"));
        expect(baseEnv).toEqual({ MESA_SHADER_CACHE_DIR: "", MESA_GLSL_CACHE_DIR: "" });
    });

    it.each(["linux", "win32"] as const)("leaves renderer overrides and cache behavior untouched on %s", (platform) => {
        fs.writeFileSync(configPath, "invalid");
        const env = launchEnv({ platform, baseEnv: {
            [MACOS_METAL_BACKEND_ENV]: "unrelated-value",
            [MACOS_MOLTENVK_METAL4_ENV]: "unrelated-value",
            MESA_SHADER_CACHE_DIR: "/tmp/platform-shaders",
            MESA_GLSL_CACHE_DIR: "/tmp/platform-legacy",
            XDG_CACHE_HOME: "/tmp/platform-cache",
        } });
        expect(env[MACOS_MOLTENVK_METAL4_ENV]).toBe("unrelated-value");
        expect(env[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBeUndefined();
        expect(env.MESA_SHADER_CACHE_DIR).toBe("/tmp/platform-shaders");
        expect(env.MESA_GLSL_CACHE_DIR).toBe("/tmp/platform-legacy");
        expect(env.XDG_CACHE_HOME).toBe("/tmp/platform-cache");
    });

    it("does not read renderer preferences for unbundled macOS or an incomplete bundled runtime", () => {
        fs.writeFileSync(configPath, "invalid");
        const baseEnv = { [MACOS_MOLTENVK_METAL4_ENV]: "untouched", XDG_CACHE_HOME: "/tmp/existing-cache" };
        expect(launchEnv({ bundledAssetsPath: undefined, baseEnv })[MACOS_MOLTENVK_METAL4_ENV]).toBe("untouched");
        const incomplete = launchEnv({ baseEnv, pathExists: () => false });
        expect(incomplete[MACOS_MOLTENVK_METAL4_ENV]).toBe("untouched");
        expect(incomplete.XDG_CACHE_HOME).toBe("/tmp/existing-cache");
    });

    it("preserves KosmicKrisp's existing environment and cache without reading MoltenVK preferences", () => {
        fs.writeFileSync(configPath, "invalid");
        const env = launchEnv({ baseEnv: {
            [MACOS_VULKAN_BACKEND_ENV]: "kosmickrisp",
            [MACOS_METAL_BACKEND_ENV]: "unrelated-value",
            [MACOS_MOLTENVK_METAL4_ENV]: "untouched",
            MESA_SHADER_CACHE_DIR: "/tmp/kk-shaders",
            MESA_GLSL_CACHE_DIR: "/tmp/kk-legacy",
        }, pathExists: () => true });
        expect(env[MACOS_VULKAN_BACKEND_ENV]).toBe("kosmickrisp");
        expect(env[MACOS_MOLTENVK_METAL4_ENV]).toBe("untouched");
        expect(env[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBeUndefined();
        expect(env.MESA_SHADER_CACHE_DIR).toBe("/tmp/kk-shaders");
        expect(env.MESA_GLSL_CACHE_DIR).toBe("/tmp/kk-legacy");
        expect(env.XDG_CACHE_HOME).toBe(path.join(localWriteDataPath, "cache"));
    });

    it("logs the requested renderer without claiming actual native activation", () => {
        const diagnostics = getNativeEngineProcessEnvDiagnostics(launchEnv({ baseEnv: { [MACOS_METAL_BACKEND_ENV]: "METAL4" } }));
        expect(diagnostics[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBe("METAL4");
        expect(diagnostics[MACOS_MOLTENVK_METAL4_ENV]).toBe("1");
        expect(Object.keys(diagnostics).some((key) => /actual|active/i.test(key))).toBe(false);
    });

    it("reports the next-launch default without creating user preferences", () => {
        expect(getMacOSRendererPreference(configPath, {})).toEqual({ renderer: "METAL3", overriddenBy: null });
        expect(fs.existsSync(configPath)).toBe(false);
    });

    it("shares UI selections with both launch lanes and keeps captured running environments unchanged", () => {
        const baseEnv = Object.freeze({});
        const running = launchEnv();
        for (const renderer of ["METAL4", "METAL3"] as const) {
            expect(setMacOSRendererPreference(configPath, renderer, baseEnv)).toEqual({ renderer, overriddenBy: null });
            for (const lane of ["bar-lobby", "bar-chobby"] as const) {
                expect(launchEnv({ macOSLuaUIOverlayLane: lane })[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBe(renderer);
            }
            expect(getMacOSRendererPreference(configPath, baseEnv).renderer).toBe(renderer);
        }
        expect(running[MACOS_METAL_BACKEND_REQUESTED_ENV]).toBe("METAL3");
        expect(baseEnv).toEqual({});
        expect(fs.readdirSync(localWriteDataPath)).toEqual([MACOS_RENDERER_CONFIG_FILE_NAME]);
    });

    it.each([null, undefined, "metal4", "", 4, {}, { renderer: "METAL4" }])("rejects an invalid UI choice without touching the existing preference: %j", (renderer) => {
        fs.writeFileSync(configPath, '{"renderer":"METAL3"}');
        expect(() => setMacOSRendererPreference(configPath, renderer, {})).toThrow("Renderer must be METAL3 or METAL4.");
        expect(fs.readFileSync(configPath, "utf-8")).toBe('{"renderer":"METAL3"}');
        expect(fs.readdirSync(localWriteDataPath)).toEqual([MACOS_RENDERER_CONFIG_FILE_NAME]);
    });

    it.each([
        [MACOS_METAL_BACKEND_ENV, "METAL4"],
        [MACOS_MOLTENVK_METAL4_ENV, "1"],
    ])("reports a valid %s override and refuses a misleading preference save", (key, value) => {
        fs.writeFileSync(configPath, "invalid old preference");
        const env = Object.freeze({ [key]: value });
        expect(getMacOSRendererPreference(configPath, env)).toEqual({ renderer: "METAL4", overriddenBy: key });
        expect(() => setMacOSRendererPreference(configPath, "METAL3", env)).toThrow("controlled by");
        expect(fs.readFileSync(configPath, "utf-8")).toBe("invalid old preference");
    });

    it("validates even a lower-priority malformed override before any UI write", () => {
        expect(() => setMacOSRendererPreference(configPath, "METAL3", {
            [MACOS_METAL_BACKEND_ENV]: "METAL4", [MACOS_MOLTENVK_METAL4_ENV]: "invalid",
        })).toThrow("must be 0 or 1");
        expect(fs.existsSync(configPath)).toBe(false);
    });

    it("can repair malformed preference content with a valid UI selection", () => {
        fs.writeFileSync(configPath, "invalid old preference");
        expect(() => getMacOSRendererPreference(configPath, {})).toThrow("Invalid renderer preference");
        setMacOSRendererPreference(configPath, "METAL4", {});
        expect(getMacOSRendererPreference(configPath, {}).renderer).toBe("METAL4");
    });

    it("keeps the old complete preference until an atomic replacement succeeds", () => {
        fs.writeFileSync(configPath, '{"renderer":"METAL3"}');
        const rename = fs.renameSync;
        vi.spyOn(fs, "renameSync").mockImplementation((from, to) => {
            expect(getMacOSRendererPreference(configPath, {}).renderer).toBe("METAL3");
            expect(JSON.parse(fs.readFileSync(from, "utf-8"))).toEqual({ renderer: "METAL4" });
            rename(from, to);
        });
        setMacOSRendererPreference(configPath, "METAL4", {});
        expect(getMacOSRendererPreference(configPath, {}).renderer).toBe("METAL4");
        expect(fs.readdirSync(localWriteDataPath)).toEqual([MACOS_RENDERER_CONFIG_FILE_NAME]);
    });

    it("preserves the old preference and removes its temporary file if replacement fails", () => {
        fs.writeFileSync(configPath, '{"renderer":"METAL3"}');
        vi.spyOn(fs, "renameSync").mockImplementation(() => { throw new Error("replacement failed"); });
        expect(() => setMacOSRendererPreference(configPath, "METAL4", {})).toThrow("replacement failed");
        expect(getMacOSRendererPreference(configPath, {}).renderer).toBe("METAL3");
        expect(fs.readdirSync(localWriteDataPath)).toEqual([MACOS_RENDERER_CONFIG_FILE_NAME]);
    });
});
