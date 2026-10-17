// SPDX-FileCopyrightText: 2025 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import { describe, it, expect, vi } from "vitest";
import { shallowMount } from "@vue/test-utils";
import App from "@renderer/App.vue";

Object.defineProperty(window, "barNavigation", {
    value: {
        onNavigateTo: vi.fn(),
    },
    writable: true,
});

vi.mock("@renderer/store/settings.store", () => ({
    settingsStore: {
        isInitialized: true,
        skipIntro: true,
        devMode: false,
    },
}));
vi.mock("@renderer/router", () => ({ router: { currentRoute: { value: { path: "/" } }, push: vi.fn(), replace: vi.fn() } }));

vi.mock("@renderer/store/infos.store", () => ({
    infosStore: {
        lobby: { version: "1.2.3" },
    },
}));

vi.mock("@renderer/store/battle.store", () => ({
    battleStore: {
        isLobbyOpened: false,
        isSelectingGameMode: false,
    },
}));

vi.mock("@renderer/store/me.store", () => ({
    me: { isAuthenticated: true },
    auth: { playOffline: vi.fn() },
}));

vi.mock("@renderer/store/tachyon.store", () => ({
    tachyonStore: { isConnected: true },
}));

vi.mock("@renderer/utils/play-random-music", () => ({
    playRandomMusic: vi.fn(),
}));

vi.mock("@renderer/composables/useGlobalKeybindings", () => ({
    useGlobalKeybindings: vi.fn(),
}));

// Mock child components
vi.mock("@/renderer/components/battle/StickyBattle.vue", () => ({ default: { name: "StickyBattle", template: "<div />" } }));
vi.mock("@/renderer/components/misc/Background.vue", () => ({ default: { name: "Background", template: "<div />" } }));
vi.mock("@/renderer/components/misc/DebugSidebar.vue", () => ({ default: { name: "DebugSidebar", template: "<div />" } }));
vi.mock("@/renderer/components/misc/Error.vue", () => ({ default: { name: "Error", template: "<div />" } }));
vi.mock("@/renderer/components/misc/InitialSetup.vue", () => ({ default: { name: "InitialSetup", template: "<div />" } }));
vi.mock("@/renderer/components/misc/IntroVideo.vue", () => ({ default: { name: "IntroVideo", template: "<div />" } }));
vi.mock("@/renderer/components/navbar/NavBar.vue", () => ({ default: { name: "NavBar", template: "<div />" } }));
vi.mock("@/renderer/components/navbar/Settings.vue", () => ({ default: { name: "Settings", template: "<div />" } }));
vi.mock("@/renderer/components/navbar/ServerSettings.vue", () => ({ default: { name: "ServerSettings", template: "<div />" } }));
vi.mock("@/renderer/components/notifications/Notifications.vue", () => ({ default: { name: "Notifications", template: "<div />" } }));
vi.mock("@/renderer/components/prompts/PromptContainer.vue", () => ({ default: { name: "PromptContainer", template: "<div />" } }));
vi.mock("@/renderer/components/common/Loader.vue", () => ({ default: { name: "Loader", template: "<div />" } }));
vi.mock("@/renderer/components/battle/FullscreenGameModeSelector.vue", () => ({ default: { name: "FullscreenGameModeSelector", template: "<div />" } }));

// Router mock
vi.mock("vue-router", () => ({
    useRouter: () => ({
        currentRoute: { value: { meta: {} } },
        push: vi.fn(),
        beforeEach: vi.fn(),
        afterEach: vi.fn(),
    }),
}));
vi.mock("@renderer/router", () => ({ router: { push: vi.fn() } }));

describe("App.vue", () => {
    it("renders the App root and lobby version", () => {
        const wrapper = shallowMount(App, {
            global: {
                stubs: ["RouterView", "Transition", "Suspense", "KeepAlive"],
            },
        });
        expect(wrapper.find("#wrapper").exists()).toBe(true);
        expect(wrapper.text()).toContain("1.2.3");
        expect(wrapper.findComponent({ name: "Error" }).exists()).toBe(true);
    });
});

describe("Renderer engine initialization", () => {
    it.each([
        ["darwin", "2026.09.01-24-g01efdf4 master"],
        ["linux", "2026.07.04"],
        ["win32", "2026.07.04"],
    ])("selects the canonical main-process config for %s after versions arrive", async (_platform, defaultEngineVersion) => {
        vi.resetModules();
        const config = { defaultEngineVersion };
        vi.doMock("@renderer/store/config.store", () => ({ configStore: config }));
        const names = ["engine", "content"] as const;
        const previous = names.map((name) => [name, Object.getOwnPropertyDescriptor(window, name)] as const);
        const versions = [
            { id: "2026.07.04", ais: [], installed: true },
            { id: "2026.09.01-24-g01efdf4 master", ais: [], installed: true },
        ];
        let completeVersions!: (value: typeof versions) => void;
        const delayed = new Promise<typeof versions>((resolve) => { completeVersions = resolve; });
        const listAvailableVersions = vi.fn().mockReturnValueOnce(delayed).mockResolvedValue(versions);
        Object.defineProperty(window, "engine", { configurable: true, value: { listAvailableVersions } });
        Object.defineProperty(window, "content", { configurable: true, value: { onSettled: vi.fn() } });
        const { enginesStore, initEnginesStore, refreshEnginesStore } = await import("@renderer/store/engine.store");
        try {
            const initialized = initEnginesStore();
            expect(listAvailableVersions).toHaveBeenCalledOnce();
            await Promise.resolve();
            expect(enginesStore.isInitialized).toBe(false);
            expect(enginesStore.selectedEngineVersion).toBeUndefined();
            completeVersions(versions);
            await initialized;
            expect(enginesStore.isInitialized).toBe(true);
            expect(enginesStore.selectedEngineVersion).toMatchObject({ id: defaultEngineVersion });
            config.defaultEngineVersion = versions.find((version) => version.id !== defaultEngineVersion)!.id;
            await refreshEnginesStore();
            expect(listAvailableVersions).toHaveBeenCalledTimes(2);
            expect(enginesStore.selectedEngineVersion).toMatchObject({ id: config.defaultEngineVersion });
        } finally {
            vi.doUnmock("@renderer/store/config.store");
            for (const [name, descriptor] of previous) {
                if (descriptor) Object.defineProperty(window, name, descriptor);
                else Reflect.deleteProperty(window, name);
            }
        }
    });
});
