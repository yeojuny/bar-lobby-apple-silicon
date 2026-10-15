// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import * as path from "path";
import { spawn } from "child_process";
import { logger } from "@main/utils/logger";
import { getEnginePath, WRITE_DATA_PATH, getAssetsPath, BUNDLED_ASSETS_PATH } from "@main/config/app";
import { getNativeEngineProcessEnv, resolveNativeEngineRunner } from "@main/config/native-engine-runner";

const log = logger("checksums.ts");

let checksumQueue: Promise<void> = Promise.resolve();

export function calcChecksum(engineVersion: string, archiveName: string): Promise<void> {
    checksumQueue = checksumQueue.then(() => runChecksumProcess(engineVersion, archiveName));
    return checksumQueue;
}

function runChecksumProcess(engineVersion: string, archiveName: string): Promise<void> {
    let enginePath = path.join(getEnginePath(), engineVersion).replaceAll("\\", "/");
    let binaryName = process.platform === "win32" ? "spring-headless.exe" : "./spring-headless";
    let env: NodeJS.ProcessEnv = { ...process.env, SPRING_DATADIR: getAssetsPath() };
    if (process.platform === "darwin") {
        // The native bundle supplies spring, whose --calc-checksum path exits
        // before graphical initialization. Resolve the requested version just
        // like gameplay; do not assume a separate spring-headless was bundled.
        try {
            const paths = { assetsPath: getAssetsPath(), bundledAssetsPath: BUNDLED_ASSETS_PATH };
            const runner = resolveNativeEngineRunner({ ...paths, engineVersion });
            enginePath = runner.enginePath;
            binaryName = runner.spawnCommand;
            env = getNativeEngineProcessEnv({
                ...paths,
                enginePath,
                writeDataPath: WRITE_DATA_PATH,
                includeBundledAssetsInSpringDataDir: false,
                includeBundledEngineSupportInSpringDataDir: true,
                includeBundledMacOSLuaUIOverlayInSpringDataDir: false,
            });
        } catch (error) {
            log.warn(`calcChecksum could not resolve native engine ${engineVersion}: ${error}`);
            return Promise.resolve();
        }
    }
    // --calc-checksum does not return a value to us; it causes the engine to write a checksum cache
    // file to disk that speeds up subsequent archive loading (avoids re-scanning on next launch).
    const args = ["--write-dir", WRITE_DATA_PATH, "--isolation", "--calc-checksum", archiveName];

    log.debug(`Calculating checksum for: ${archiveName}`);
    return new Promise<void>((resolve) => {
        const proc = spawn(binaryName, args, {
            cwd: enginePath,
            // Output is not consumed; avoid filling an unread pipe on large scans.
            stdio: "ignore",
            env,
        });
        proc.on("exit", (code) => {
            if (code !== 0) log.warn(`calcChecksum exited with code ${code} for: ${archiveName}`);
            resolve();
        });
        proc.on("error", (err) => {
            log.warn(`calcChecksum failed for ${archiveName}: ${err}`);
            resolve();
        });
    });
}
