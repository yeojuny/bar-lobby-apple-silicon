// SPDX-FileCopyrightText: 2025 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import { BUNDLED_ASSETS_PATH, CONFIG_PATH, WRITE_DATA_PATH } from "@main/config/app";
import { getMacOSRendererPreference, setMacOSRendererPreference, MACOS_RENDERER_CONFIG_FILE_NAME } from "@main/config/native-engine-runner";
import { FileStore } from "@main/json/file-store";
import { settingsSchema } from "@main/json/model/settings";

import { ipcMain } from "@main/typed-ipc";
import path from "path";

const settingsStore = new FileStore<typeof settingsSchema>(path.join(CONFIG_PATH, "settings.json"), settingsSchema);

async function init() {
    await settingsStore.init();
}

function getSettings() {
    return settingsStore.model;
}

async function updateSettings(data: Partial<typeof settingsSchema>) {
    return await settingsStore.update(data);
}

function toggleFullscreen() {
    settingsStore.update({ fullscreen: !settingsStore.model.fullscreen });
}

function registerIpcHandlers() {
    ipcMain.handle("settings:get", () => getSettings());
    ipcMain.handle("settings:update", (_, data: Partial<Settings>) => updateSettings(data));
    ipcMain.handle("settings:toggleFullscreen", () => toggleFullscreen());
    ipcMain.handle("settings:getMetalRenderer", () => {
        if (process.platform !== "darwin" || !BUNDLED_ASSETS_PATH) return null;
        return getMacOSRendererPreference(path.join(WRITE_DATA_PATH, MACOS_RENDERER_CONFIG_FILE_NAME), process.env);
    });
    ipcMain.handle("settings:setMetalRenderer", (_, renderer) => {
        if (process.platform !== "darwin" || !BUNDLED_ASSETS_PATH) throw new Error("Metal selection requires the bundled macOS runtime.");
        return setMacOSRendererPreference(path.join(WRITE_DATA_PATH, MACOS_RENDERER_CONFIG_FILE_NAME), renderer, process.env);
    });
}

export type Settings = typeof settingsStore.model;
export const settingsService = {
    init,
    registerIpcHandlers,
    getSettings,
    updateSettings,
};
