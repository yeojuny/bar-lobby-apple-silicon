# S2: environment mutex failure and cleanup

Apply SDL [52ef28ae](https://github.com/libsdl-org/SDL/commit/52ef28aebadaf6fd3478cf06a8c3337c7214262d) on the accepted S1 source base. Environment creation now checks mutex creation before creating the table, returns NULL/freeing the environment on mutex failure, and destroys the mutex when the later table creation fails. Existing per-query locking is unchanged.

The complete three-file [patch](change.patch) also extends the existing testautomation runner with explicit lowercase `--no-init` CPU-only support and adds a focused failure/cleanup case to its existing Stdlib suite. All mandatory selected runs used `--no-init` and skipped zero tests. Before the production fix, one of 57 environment assertions failed as expected. Afterward, 57 focused environment + 53 existing environment + 117 cumulative S1 UTF-8 assertions passed (227 total), loading the actual changed raw SDL with the same rebuilt test executable.

Reconstruct **public candidate.4 port SDL archive -> complete S1 patch -> complete S2 patch**. The S2 Stdlib preimage is S1's postimage, not pristine upstream. See [manifest](manifest.json), [recipe](recipe.md), [validation](validation.json), and [applied audit](applied-audit.json). SDL's existing source license and credits remain in the base archive.

This does not publish a new app or change Release/Homebrew/V1. OS-level mutex-init failure, global-singleton concurrency, other platforms, a new binary export census, and app/GPU/game/FPS/MP acceptance are not certified by these focused results.
