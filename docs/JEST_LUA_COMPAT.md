# jest-lua compatibility status

## TL;DR

The loader (`runtime/jest_lua_loader.luau`) successfully boots every
package's `init.lua` from `node_modules/@rbxts-js/`. Cross-package
require chains work. The remaining blocker is **architectural, not
technical**: `JestGlobals` itself raises `"Do not import JestGlobals
outside of the Jest 3 test environment"` — the package only works
when bootstrapped by `jest-core.runCLI()`, which spawns a full
worker/environment/circus stack.

So lute-jest can't just "use jest-lua's matchers" — running their
matchers means running their entire runner, which is a from-scratch port.

## What the loader actually solves

It removes every Roblox-specific blocker for *loading* jest-lua source:

- **`script.Parent.X` package navigation** — emulated against the
  flat `node_modules/@rbxts-js/<kebab>/src/init.lua` layout via a
  kebab→PascalCase name map (53 entries).
- **`script.X` sub-module access** — virtual `script` per loaded file,
  with `__index` resolving siblings to disk paths.
- **`script.Parent.Parent[...]` chains** — `_makeFolder` walks up dirs
  and bottoms out in a `_makePackagesFolder` that handles cross-pkg lookups.
- **`fs.exists` yielding inside `__index`** — pre-walk filesystem at
  `configure()` time and answer existence checks from a static set
  (Lute can't yield across metamethod boundaries).
- **Roblox globals** — `game`, `task`, `typeof`, `Instance`, `Vector3`,
  `wait`, `tick`, `spawn` injected into the env from `polyfills.luau`.

After all that, `jest-globals/src/index.lua` line 37 (the actual
jest entry point) runs and throws its sentinel error. That error is
the design — jest-lua doesn't expose stand-alone matchers.

## What it would take to finish

To make existing `@rbxts/jest` test files pass under Lute you'd need
to either:

1. **Boot jest-core** — work backwards from `jest-core.runCLI()` and
   wire up every dep (jest-runner, jest-circus, jest-jasmine2,
   jest-runtime, jest-message-util, jest-reporters, ...). Each will
   surface its own Roblox-specific bits (Worker pool, file watchers,
   snapshot serialization).
2. **Bypass the gate** — patch `jest-globals/src/index.lua` to skip
   the `error()`. Then ad-hoc run `it`/`expect`/`describe` from raw
   exports. Brittle — `expect(x):toBe(y)` needs `MatcherState` setup
   that only `jest-circus` builds.
3. **Translate the bridge** — write a thin shim where lute-jest's
   homebrew runner *exposes* jest-globals-shaped exports
   (`describe`, `it`, `expect`) backed by our own implementation, so
   existing test files written to `@rbxts/jest-globals` work
   unchanged. This is the most pragmatic path.

(3) is the right next move. Most existing test files only use
~10 jest API surfaces; what we already have covers it.

## What's in the repo

- `runtime/jest_lua_loader.luau` (~280 LoC) — the loader
- `runtime/polyfills.luau` — Roblox globals (game, task, etc.)
- This document

The loader is **not wired into the runner** by default. It's a
research artifact / proof-of-concept for path (3). The default
`bun cli/index.ts` still uses lute-jest's homebrew jest at
`runtime/jest.luau`, which is what 27/27 tests currently pass with.
