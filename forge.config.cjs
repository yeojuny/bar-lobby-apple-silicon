const { VitePlugin } = require("@electron-forge/plugin-vite");
const { spawnSync } = require("node:child_process");
const { resolve } = require("node:path");

const projectRoot = __dirname;
const bundledAssetsRoot = process.env.BAR_BUNDLED_ASSETS_PATH?.trim() || resolve(projectRoot, "bundled-assets");
const laneOverlayPath = resolve(bundledAssetsRoot, "macos-luaui-overlays");
const overlayContractGuard = resolve(projectRoot, "tools/verify-macos-luaui-contract.mjs");
const overlayContractResult = spawnSync(process.execPath, [overlayContractGuard, laneOverlayPath], {
    cwd: projectRoot,
    encoding: "utf8",
});
if (overlayContractResult.status !== 0) {
    throw new Error(`macOS LuaUI contract rejected Electron Forge packaging:\n${overlayContractResult.stderr || overlayContractResult.error}`);
}
if (overlayContractResult.stdout) process.stdout.write(overlayContractResult.stdout);

const config = {
    plugins: [
        new VitePlugin({
            build: [
                {
                    entry: "src/main/main.ts",
                    config: "vite.main.config.mts",
                    target: "main",
                },
                {
                    entry: "src/preload/preload.ts",
                    config: "vite.preload.config.mts",
                    target: "preload",
                },
            ],
            renderer: [
                {
                    name: "main_window",
                    config: "vite.renderer.config.mts",
                },
            ],
        }),
    ],
};

module.exports = config;
