// SPDX-FileCopyrightText: 2026 The BAR Lobby Authors
//
// SPDX-License-Identifier: MIT

import { describe, expect, it, vi } from "vitest";

vi.mock("@main/services/config.service", () => ({ configService: { getConfig: () => ({ engineReleaseUrl: "https://files-cdn.beyondallreason.dev/find" }) } }));

import { getEngineReleaseCategory } from "@main/config/content-sources";

describe("content sources", () => {
    it("keeps existing Windows and Linux engine CDN categories", () => {
        expect(getEngineReleaseCategory("win32")).toBe("engine_windows64");
        expect(getEngineReleaseCategory("linux")).toBe("engine_linux64");
    });

    it("does not allow macOS to use the Linux engine CDN category", () => {
        expect(() => getEngineReleaseCategory("darwin")).toThrow(/refusing to use engine_linux64/);
    });
});
