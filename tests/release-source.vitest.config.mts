// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
// SPDX-License-Identifier: MIT

import { defineConfig } from "vitest/config";
import path from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));

export default defineConfig({
    root,
    cacheDir: path.join(tmpdir(), `bar-release-source-vitest-${process.pid}`),
    resolve: { alias: { "@main": path.join(root, "src/main"), $: path.join(root, "vendor") } },
    test: {
        environment: "node",
        fileParallelism: false,
        maxWorkers: 1,
        minWorkers: 1,
        include: [
            "tests/unit/main/auto-updater.spec.ts",
            "tests/unit/main/auto-updater-lifecycle.spec.ts",
            "tests/unit/main/pinned-bundled-assets.spec.ts",
        ],
    },
});
