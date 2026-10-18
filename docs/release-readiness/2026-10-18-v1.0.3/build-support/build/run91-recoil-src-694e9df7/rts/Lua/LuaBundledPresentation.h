/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
#pragma once

#include <algorithm>
#include <string>
#include <string_view>
#include <vector>

#include "LuaBundledPresentationSources.h"
#include "System/Sync/SHA512.hpp"

// Immutable unsynced presentation resources. No filesystem lookup, Lua state,
// environment, or privilege flag is accepted by this fixed-path source table.
namespace bundled_presentation {

inline std::string NormalizePath(std::string_view input)
{
	if (input.empty() || input.size() > 256 || input.front() == '/' || input.back() == '/')
		return {};
	std::string result;
	result.reserve(input.size());
	for (const unsigned char c: input) {
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == '/'))
			return {};
		result.push_back((c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c);
	}
	if (result.find("//") != std::string::npos)
		return {};
	for (size_t start = 0; start < result.size();) {
		const auto end = result.find('/', start);
		const auto component = std::string_view(result).substr(start, end - start);
		if (component == "." || component == "..")
			return {};
		if (end == std::string::npos)
			break;
		start = end + 1;
	}
	return result;
}

template<size_t N>
inline std::string_view FindSource(std::string_view path, const bundled_presentation_data::Source (&sources)[N])
{
	const auto normalized = NormalizePath(path);
	if (normalized.empty())
		return {};
	for (const auto& source: sources) {
		if (source.path == normalized)
			return source.bytes;
	}
	return {};
}

inline std::string_view FindWidget(std::string_view path)
{
	return FindSource(path, bundled_presentation_data::WIDGETS);
}

inline std::string_view FindPrivateSource(std::string_view path)
{
	return FindSource(path, bundled_presentation_data::PRIVATE_SOURCES);
}

// These two self-contained widgets use the ordinary archive widget loader.
// Never substitute same-name delegates (which include their official original),
// and never promote bytes read from RAW into archive widget privileges.
inline constexpr std::string_view HEALTHBAR_WIDGETS[] = {
	"luaui/widgets/gui_healthbars_gl4.lua",
	"luaui/widgets/api_unit_tracker_gl4.lua",
};

inline std::string_view FindStandaloneWidget(std::string_view path, std::string_view modes)
{
	if (modes.find('M') == std::string_view::npos)
		return {};
	const auto normalized = NormalizePath(path);
	for (const auto name: HEALTHBAR_WIDGETS) {
		if (normalized == name)
			return FindWidget(name);
	}
	return {};
}

inline void UpdateStandaloneWidgetList(std::vector<std::string>& files, std::string_view modes)
{
	const bool archive = modes.find('M') != std::string_view::npos;
	if (!archive && modes.find('R') == std::string_view::npos)
		return;
	for (const auto name: HEALTHBAR_WIDGETS) {
		// The compiled family is enumerated only as archive content, including
		// on handlers which enumerate RAW first. Other user widgets are intact.
		files.erase(std::remove_if(files.begin(), files.end(), [&](const auto& file) {
			return NormalizePath(file) == name;
		}), files.end());
		if (archive && !FindWidget(name).empty())
			files.emplace_back(name);
	}
}

inline bool Matches(std::string_view source, size_t size, std::string_view expected)
{
	if (source.size() != size || source.find('\0') != std::string_view::npos)
		return false;
	sha512::raw_digest raw {};
	sha512::hex_digest hex {};
	sha512::calc_digest(reinterpret_cast<const uint8_t*>(source.data()), source.size(), raw.data());
	sha512::dump_digest(raw, hex);
	return std::string_view(hex.data(), 128) == expected;
}

// Only the complete, exact official handler may gain this substitution point.
// Include passes the actual native provider as a vararg after setting the same
// caller fenv. A replaced VFS table in that fenv cannot spoof the provider.
inline bool AugmentWidgetHandler(std::string& source)
{
	const bool known = Matches(source, 138917, "fd298d1cef4ee2996877bf45fc9f19715cbd77eca8e8dbf4fe5c73643f9dd6e8ff3a0eaaf2a6d21da4349125432b0b0c46245c4648185ce097f4a7aaa0e2ee19")
		|| Matches(source, 141304, "738dd12f4df4d17fcb9c2079e0a071121896fbc975d9f9e5c5435721950a7e6436ee26ac88850fe8b9793663f585502eb0620c7610f43d7a26ba57fa6e5067cb")
		|| Matches(source, 103589, "b731d0b2df6ed98157f172586fbb49524593c2042f977922ce69f15efe68721aa36db0b77085b569fddfd9a483c0c7435c8e7db4f9289923d2402db4f03bc112");
	constexpr std::string_view anchor = "\tif text == nil then\n\t\treturn loadFailed(basename, \"missing file: \" .. filename)\n\tend";
	const auto first = source.find(anchor);
	if (!known || first == std::string::npos || source.find(anchor, first + anchor.size()) != std::string::npos)
		return false;
	source.insert(first,
		"\tlocal __barBundledText = __barBundledWidgetSource(filename)\n"
		"\tif __barBundledText ~= nil then\n"
		"\t\ttext = __barBundledText\n"
		"\t\tfromZip = true\n"
		"\tend\n");
	source.insert(0, "local __barBundledWidgetSource = ...\n");
	return true;
}

inline bool WrapLuaRulesHelper(std::string& source)
{
	const bool known = Matches(source, 45641, "81858ab150aceb7d84f324708f3b3c4a5c8101df03c2a3a0597cc64413fea8ff7db558b711b18e930aa577bf7b0c6b96bfde83c342ca94508f72021742372436")
		|| Matches(source, 44927, "bab25be79d429bbbb766df84bc07b9662cc8a7e5bd88a8ea566cac9bea745ee7a0c5f28798b7b436a2f12ba87ccb9901e5a4a6e0ba228988058a8641ccb877ef");
	if (!known)
		return false;
	source = "local function __barOriginalHelper()\n" + source
		+ "\nend\nlocal function __barAdaptHelper(...)\n"
		+ std::string(bundled_presentation_data::LUA_RULES_ADAPTER)
		+ "\nend\nreturn __barAdaptHelper(__barOriginalHelper())\n";
	return true;
}

inline void AddDistributionWidget(std::vector<std::string>& files)
{
	constexpr std::string_view name = "luaui/widgets/gui_pip_macos_minimap_overlay.lua";
	if (FindWidget(name).empty())
		return;
	bool found = false;
	files.erase(std::remove_if(files.begin(), files.end(), [&](const auto& file) {
		if (NormalizePath(file) != name)
			return false;
		if (found)
			return true;
		found = true;
		return false;
	}), files.end());
	if (!found)
		files.emplace_back("LuaUI/Widgets/gui_pip_macos_minimap_overlay.lua");
}

} // namespace bundled_presentation
