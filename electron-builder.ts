import type { Configuration } from "app-builder-lib";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { createPinnedBundledAssets } from "./packaging/pinned-bundled-assets";

/**
 * @see https://www.electron.build/configuration
 */
// Reviewed experimental release inputs. The external lock remains mandatory;
// protected local candidates are not modified by this packaging configuration.
const bundledAssets = createPinnedBundledAssets(process.env, {
    id: "healthbar-standalone-1.0.3-20261018",
    lanes: {
        "bar-chobby": {
            engineDirectory: "2026.07.04",
            springSha256: "5416abb83d5611c22e8a2c4b841b8647d5c6f2f4ef59f9b304d9b909edc0daa8",
        },
        "bar-lobby": {
            engineDirectory: "2026.09.01-24-g01efdf4 master",
            springSha256: "7d32a46c5d0e95be1f06291757c84cdddb49c2d5b9136eab6696751076d23ae7",
        },
    },
});

const projectRoot = resolve(".");
const overlayContractGuard = resolve(projectRoot, "tools/verify-macos-luaui-contract.mjs");

const config: Configuration = {
    appId: "io.github.yeojuny.bar",
    // Should be the same as APP_NAME in src/main/config/app.ts and in
    // workaround in installer.nsh.
    productName: "BAR",
    buildVersion: "1.0.3",
    extraMetadata: {
        version: "1.0.3",
        repository: { type: "git", url: "https://github.com/yeojuny/bar-lobby-apple-silicon.git" },
    },

    asar: true,
    disableDefaultIgnoredFiles: true,
    files: ["./.vite/**", "!.vite/**/*.map", "!node_modules", "./node_modules/7zip-bin/**"],
    directories: { buildResources: "buildResources" },
    asarUnpack: ["resources/**"],
    beforePack: (context) => {
        if (context.electronPlatformName !== "darwin") return;
        const { overlayPath } = bundledAssets.validate();
        const result = spawnSync(process.execPath, [overlayContractGuard, overlayPath], {
            cwd: projectRoot,
            encoding: "utf8",
        });
        if (result.status !== 0) {
            throw new Error(`macOS LuaUI contract rejected electron-builder packaging:\n${result.stderr || result.error}`);
        }
        if (result.stdout) process.stdout.write(result.stdout);
    },

    // Release uploads are controlled separately after the exact artifact passes
    // review. Explicit null also prevents token-based publisher autodetection.
    publish: null,
    fileAssociations: [
        { ext: "barreplay", description: "BAR Replay Highlight", role: "Viewer", icon: "icon.ico", name: "BAR Replay Highlight" },
        {
            ext: "sdfz",
            description: "BAR Replay File",
            role: "Viewer",
            // electron-builder resolves this to icon.icns on macOS, using the
            // original port artwork while preserving the Windows association.
            icon: "icon.ico",
            name: "BAR Replay",
        },
    ],

    // Windows
    win: {
        target: ["nsis"],
        extraResources: [
            {
                from: "buildResources/cacert.pem",
                to: "cacert.pem",
            },
        ],
    },
    nsis: {
        artifactName: "${productName}-${version}-setup.${ext}",
        uninstallDisplayName: "Beyond All Reason",
        shortcutName: "Beyond All Reason",
        oneClick: true,
        perMachine: false,
        allowToChangeInstallationDirectory: false,
        include: "build/installer.nsh",
    },

    // Linux
    linux: {
        target: ["AppImage"],
        category: "Game",
    },
    appImage: {},

    // Optional release target, applied to the separately verified prepackaged
    // app. Keep the default macOS target below as dir during validation.
    dmg: {
        title: "BAR ${version}",
        background: "buildResources/dmg-background.png",
        window: { width: 680, height: 420 },
        iconSize: 104,
        iconTextSize: 14,
        sign: false,
        contents: [
            { x: 176, y: 205 },
            { x: 504, y: 205, type: "link", path: "/Applications" },
        ],
    },

    // macOS
    mac: {
        target: ["dir"],
        // The wrapper resolves mac/<process.arch>/7za. Keep its exact ARM64
        // payload and attribution without shipping unused platform binaries.
        files: [
            // Platform strings form a separate matcher after global FileSet
            // normalization. Keep it positive so it cannot default to **/*.
            "./.vite/**",
            "!.vite/**/*.map",
            "!node_modules/7zip-bin/!(index.js|package.json|LICENSE.txt|mac){,/**/*}",
            "!node_modules/7zip-bin/mac/!(arm64){,/**/*}",
            "!node_modules/7zip-bin/mac/arm64/!(7za){,/**/*}",
        ],
        // Includes the required, lock-pinned third-party notices. Corresponding
        // source archives are separate release assets, outside this app tree.
        extraResources: bundledAssets.extraResources,
        category: "public.app-category.games",
        icon: "buildResources/icon.icns",
        minimumSystemVersion: "27.0",
        identity: null,
    },
};

export default config;
