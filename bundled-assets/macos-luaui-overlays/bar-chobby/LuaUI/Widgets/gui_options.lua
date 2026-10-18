local archivePath = "LuaUI/Widgets/gui_options.lua"
-- Source/application evidence only; this does not certify GPU or game acceptance.
WG.BARMacOSOverlayStatus = WG.BARMacOSOverlayStatus or {}
local searchStatus = {
	archivePath = archivePath, required = true, status = "pending",
	applied = false, satisfied = false, archiveLoaded = false,
}
WG.BARMacOSOverlayStatus.optionsSearch = searchStatus
local function setSearchStatus(state, reason)
	searchStatus.status = state
	searchStatus.applied = state == "applied"
	searchStatus.satisfied = state == "applied" or state == "already-present"
	searchStatus.reason = reason
	Spring.Echo("[BAR macOS][OVERLAY-CONTRACT] options-search status=" .. state
		.. " applied=" .. tostring(searchStatus.applied)
		.. " satisfied=" .. tostring(searchStatus.satisfied) .. " required=true"
		.. (reason and (" reason=" .. reason) or ""))
end

local function replaceOnce(source, needle, replacement)
	local startPos = string.find(source, needle, 1, true)
	if not startPos then
		return source, false
	end
	return string.sub(source, 1, startPos - 1)
		.. replacement
		.. string.sub(source, startPos + #needle), true
end

local function runArchiveWidget(source)
	local compiler = loadstring or load
	local chunk, loadError = compiler(source, "@" .. archivePath .. " [BAR macOS ZIP delegate]")
	if not chunk then
		setSearchStatus("failed", "archive compile: " .. tostring(loadError))
		error(loadError)
	end
	if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
	local ok, result = pcall(chunk)
	if not ok then
		setSearchStatus("failed", "archive load: " .. tostring(result))
		error(result)
	end
	searchStatus.archiveLoaded = true
	return result
end

-- This is ONLY an Options UI classification, never a shader-stage capability.
-- Respect an authoritative native false. Older exports need positive backend
-- identity plus the real GL4 flag; do not infer GS support or mutate Platform.
local function hasAppleTranslationUiProfile()
	if not Platform then return false end
	if Platform.glHaveZinkMoltenVK ~= nil then
		return Platform.glHaveZinkMoltenVK == true
	end
	if not Platform.glHaveGL4 then return false end
	local vendor = string.lower(tostring(Platform.glVendor or "") .. " "
		.. tostring(Platform.gpuVendor or ""))
	local renderer = string.lower(tostring(Platform.glRenderer or "") .. " "
		.. tostring(Platform.gpu or ""))
	return string.find(vendor, "mesa", 1, true) ~= nil
		and string.find(renderer, "zink", 1, true) ~= nil
		and string.find(renderer, "moltenvk", 1, true) ~= nil
end

local appleUiProfile = hasAppleTranslationUiProfile()
local source = VFS.LoadFile(archivePath, VFS.ZIP_ONLY)
if type(source) ~= "string" then
	setSearchStatus("failed", "archive widget unavailable")
	error("[BAR macOS] archive Options widget was not found")
end
source = string.gsub(source, "\r\n", "\n")

if not string.find(source, "Platform.glHaveZinkMoltenVK", 1, true) then
	local appleBranch = [[
elseif barMacOSUiProfile then
	-- GUI quality classification only; CUS and GS capabilities are unchanged.
	isPotatoGpu = false
elseif Platform.glHaveNVidia then]]
	local patched
	source, patched = replaceOnce(source, "elseif Platform.glHaveNVidia then", appleBranch)
	if not patched then
		Spring.Echo("[Run91 macOS Options] GPU classification hook skipped: upstream layout changed")
	elseif appleUiProfile then
		Spring.Echo("[Run91 macOS Options] Apple translation UI profile selected; no shader capability override")
	else
		Spring.Echo("[Run91 macOS Options] no confirmed Apple translation UI profile; upstream classification retained")
	end
end
source = "local barMacOSUiProfile = " .. tostring(appleUiProfile) .. "\n" .. source

-- RUN64_MACOS_MSAA_CAP: retain the existing validated Off/2x/4x sample policy.
local RUN64_MACOS_MSAA_CAP = true
if RUN64_MACOS_MSAA_CAP and appleUiProfile then
	local msaaOptionCount
	source, msaaOptionCount = source:gsub('"x4", "x8"', '"x4"')
	if msaaOptionCount ~= 1 then
		error("Run64 macOS Options delegate could not cap the official MSAA list")
	end
	if Spring.GetConfigInt("MSAALevel", 0) > 4 then
		Spring.SetConfigInt("MSAALevel", 4)
	end
	Spring.Echo("[Run64 macOS Options] valid MSAA choices: Off, x2, x4")
end

-- RUN94_OPTIONS_SEARCH_DEDUP: direct matches must be marked before context rows.
do
	local needle = "\t\t\tif not shown[option] then\n\t\t\t\tresult[#result + 1] = option\n\t\t\tend"
	local replacement = "\t\t\tif not shown[option] then\n\t\t\t\tshown[option] = true\n\t\t\t\tresult[#result + 1] = option\n\t\t\tend"
	local startPos, endPos = string.find(source, needle, 1, true)
	local alreadyFixed, fixedEnd = string.find(source, replacement, 1, true)
	-- Current official Options marks an option before recursively showing its
	-- parent. Recognize that complete implementation without rewriting it.
	local recursive = "\t\tlocal shown = {}\n\t\tlocal result = {}\n\t\tlocal function show(option)\n"
		.. "\t\t\tif not shown[option] then\n\t\t\t\tshown[option] = true\n"
		.. "\t\t\t\tif option.parentOption then\n\t\t\t\t\tshow(option.parentOption)\n\t\t\t\tend\n"
		.. "\t\t\t\tresult[#result + 1] = option\n\t\t\t\tif option.spacer then\n"
		.. "\t\t\t\t\tresult[#result + 1] = option.spacer\n\t\t\t\tend\n\t\t\tend\n\t\tend"
	local recursiveStart, recursiveEnd = string.find(source, recursive, 1, true)
	if recursiveStart and not startPos and not alreadyFixed
		and not string.find(source, recursive, recursiveEnd + 1, true) then
		setSearchStatus("already-present", "official recursive search guard")
	elseif not recursiveStart and startPos and not string.find(source, needle, endPos + 1, true) and not alreadyFixed then
		source = replaceOnce(source, needle, replacement)
		setSearchStatus("applied")
	elseif not recursiveStart and not startPos and alreadyFixed and not string.find(source, replacement, fixedEnd + 1, true) then
		setSearchStatus("already-present")
	else
		-- Keep official Options available, but reject this outcome as a required
		-- patch success. Duplicate fixed anchors are ambiguous too.
		setSearchStatus("fallback", "search anchor missing, ambiguous, or mixed")
	end
end

-- Use the archive's own preset and option handlers once. Keeping this closure
-- beside presetKeys avoids depending on the translated labels or list order.
local defaultsAnchor = "\tlocal presetNames = {}"
local defaultsHook = [=[
	function widget:BARMacOSApplyGraphicsDefaults()
		if not barMacOSUiProfile or Spring.GetConfigInt("BARMacOSGraphicsDefaults102", 0) == 1 then return end
		local ultraIndex
		for index, key in ipairs(presetKeys) do
			if key == "ultra" then ultraIndex = index end
		end
		local preset, aa, fog = getOption("preset"), getOption("msaa"), getOption("fogdiaglines")
		if not ultraIndex or not preset or not aa or not fog then
			Spring.Echo("[BAR macOS Options] initial graphics defaults unavailable; settings retained")
			return
		end
		applyOptionValue(preset, ultraIndex, true)
		applyOptionValue(aa, 1, true)
		applyOptionValue(fog, 0, true)
		Spring.SetConfigInt("BARMacOSGraphicsDefaults102", 1)
	end
	function widget:BARMacOSApplyCameraDefault()
		if not barMacOSUiProfile or Spring.GetConfigInt("BARMacOSSpringCamera102", 0) == 1 then return end
		local camera = getOption("camera")
		if not camera or not camera.options or #camera.options ~= 5 then
			Spring.Echo("[BAR macOS Options] initial Spring camera unavailable; settings retained")
			return
		end
		-- Official camera index 3 selects engine mode 2 via viewspring. Run after
		-- Camera Remember has restored its saved state, then preserve later choices.
		applyOptionValue(camera, 3, true)
		Spring.SetConfigInt("BARMacOSSpringCamera102", 1)
	end
	local presetNames = {}
]=]
local defaultsStart, defaultsEnd = string.find(source, defaultsAnchor, 1, true)
if defaultsStart and not string.find(source, defaultsAnchor, defaultsEnd + 1, true) then
	source = replaceOnce(source, defaultsAnchor, defaultsHook)
else
	Spring.Echo("[BAR macOS Options] initial graphics hook unavailable; archive settings retained")
end

local archiveResult = runArchiveWidget(source)
local archiveInitialize = widget.Initialize
local archiveUpdate = widget.Update
local graphicsDefaultsPending = true
local cloudsRestoreKey = "BARMacOSCloudsRestoreRun91"
function widget:Initialize(...)
	local result
	if archiveInitialize then result = archiveInitialize(self, ...) end
	-- Restore the user's earlier cloud preference once, after normal Options
	-- setup. Do not rewrite a live BYAR.lua or override later user changes.
	if Spring.GetConfigInt(cloudsRestoreKey, 0) == 0 then
		Spring.SendCommands("luaui enablewidget Volumetric Clouds")
		Spring.SetConfigInt(cloudsRestoreKey, 1)
		Spring.Echo("[Run91 macOS Options] one-time Volumetric Clouds enable requested")
	end
	return result
end
function widget:Update(...)
	local result
	if archiveUpdate then result = archiveUpdate(self, ...) end
	-- Wait until all widgets, including saved camera and effects, initialized.
	if graphicsDefaultsPending then
		graphicsDefaultsPending = false
		if self.BARMacOSApplyGraphicsDefaults then self:BARMacOSApplyGraphicsDefaults() end
		if self.BARMacOSApplyCameraDefault then self:BARMacOSApplyCameraDefault() end
	end
	return result
end
return archiveResult
