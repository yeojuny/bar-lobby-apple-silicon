// SPDX-FileCopyrightText: 2025 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import { EngineVersion } from "@main/content/engine/engine-version";
import { notificationsApi } from "@renderer/api/notifications";
import { computed, reactive } from "vue";

function getErrorMessage(error: unknown): string {
    return error instanceof Error ? error.message : "Engine download failed.";
}

export const enginesStore: {
    isInitialized: boolean;
    availableEngineVersions: EngineVersion[];
    selectedEngineVersion?: EngineVersion;
} = reactive({
    isInitialized: false,
    availableEngineVersions: [],
    selectedEngineVersion: undefined,
});

export const installedEngineVersions = computed(() => enginesStore.availableEngineVersions.filter((e) => e.installed));

export async function refreshEnginesStore() {
    const [versions, info] = await Promise.all([window.engine.listAvailableVersions(), window.info.getInfo()]);
    enginesStore.availableEngineVersions = versions;
    enginesStore.selectedEngineVersion = versions.find((e) => e.id === info.defaultEngineVersion);
    return info.defaultEngineVersion;
}

export async function downloadEngine(engineString: string) {
    await window.engine
        .downloadEngine(engineString)
        .then(async () => {
            enginesStore.availableEngineVersions = await window.engine.listAvailableVersions();
        })
        .catch((error) => {
            console.error("Failed to download engine:", engineString, error);
            notificationsApi.alert({ text: getErrorMessage(error), severity: "error" });
        });
}

export async function initEnginesStore() {
    window.downloads.onDownloadEngineComplete(async (downloadInfo) => {
        console.debug("Received engine download completed event", downloadInfo);
        enginesStore.availableEngineVersions = await window.engine.listAvailableVersions();
    });
    window.downloads.onDownloadEngineFail(async (downloadInfo) => {
        console.error("Engine download failed", downloadInfo);
        enginesStore.availableEngineVersions = await window.engine.listAvailableVersions();
    });

    const defaultEngineVersion = await refreshEnginesStore();
    if (!enginesStore.selectedEngineVersion) {
        console.warn(`Default engine version ${defaultEngineVersion} not found in available versions — engine download required.`);
    }

    enginesStore.isInitialized = true;
}
