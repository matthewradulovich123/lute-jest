# Jest-Lua compatibility status

## Goal

Run real `@rbxts/jest` (jsdotlua/jest-lua) tests under Lute, so people can keep
their existing test code instead of using lute-jest's homebrew runtime.

## Status: prototype loader, blocked on package flattening

`runtime/jest_lua_loader.luau` is a working prototype that:
- Maps `script.Parent` package navigation to `node_modules/@rbxts-js/<kebab>/src/init.lua`
- Maintains a kebab-case → PascalCase name map (LuauPolyfill, JestEnvironment, etc.)
- Wraps `require()` to handle both Instance-like sentinels and string specifiers

**It loads jest-globals' init.lua without crashing**, but resolution stops
there because the package init files reference siblings via patterns like
`script.Parent:WaitForChild("Expect")` — and in a Roblox build, all
packages get **flattened** into a single `Packages/` folder by Wally/Rojo.
That flattening doesn't happen in `node_modules/@rbxts-js/`.

## What would unblock this

1. **Build process emulation** — run jest-lua's `roblox-cli` / Rotrieve build
   step against `node_modules/@rbxts-js/`, producing a flat `Packages/` dir
   with PascalCase names. Then point the loader at that.
2. **Smarter sibling resolution** — when `script.Parent.X` misses in the
   current package's `src/`, fall back to `node_modules/@rbxts-js/<kebab>/src/init`
   based on the name map. Catches most cases but breaks deep imports.
3. **Upstream patch** — get jsdotlua/jest-lua to publish a "node-resolved"
   distribution that uses string require() instead of `script.Parent`.

(2) is the most tractable. Maybe one more sprint when there's appetite.

## Why we built lute-jest instead

The homebrew runtime is ~250 lines of Luau and covers the 80% of jest API
that game-logic unit tests actually use: describe/it/expect/beforeEach,
~12 matchers, mocks, hooks. It runs anything green-fielded immediately.

The 20% gap (snapshots, fake timers, async, jest.mock) is real but not
worth blocking shipping over. Phase 4+ may close it incrementally, OR
may flip to jest-lua via the loader once someone solves the flattening.
