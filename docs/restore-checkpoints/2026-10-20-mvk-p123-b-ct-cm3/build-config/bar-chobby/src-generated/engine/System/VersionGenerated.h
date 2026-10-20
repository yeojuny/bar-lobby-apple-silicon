/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */

/*
 * Do NOT include this file directly, but include the wrapper instead.
 * This prevents wasteful recompiling.
 */

#ifndef VERSION_GENERATED_H
#define VERSION_GENERATED_H

/// examples: "83.0" "83.0.1-13-g1234567 develop"
static constexpr const char* SPRING_VERSION_ENGINE            = "2026.07.04";

/// examples: "83"
static constexpr const char* SPRING_VERSION_ENGINE_MAJOR      = "2026";

/// examples: "83"
static constexpr const char* SPRING_VERSION_ENGINE_MINOR      = "07";

/// examples: "0"
static constexpr const char* SPRING_VERSION_ENGINE_PATCH_SET  = "04";

/// examples: "13"
static constexpr const char* SPRING_VERSION_ENGINE_COMMITS    = "";

/// examples: "1234567"
static constexpr const char* SPRING_VERSION_ENGINE_HASH       = "";

/// examples: "develop"
static constexpr const char* SPRING_VERSION_ENGINE_BRANCH     = "";

/// examples: "what a splendid day, isn't it?"
static constexpr const char* SPRING_VERSION_ENGINE_ADDITIONAL = "BAR-1.0.3";

/// examples: true, false
static constexpr bool        SPRING_VERSION_ENGINE_RELEASE    = 1;

#endif // VERSION_GENERATED_H

 
 
 
