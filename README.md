# lute-jest

Run roblox-ts/Luau jest-style tests under [Lute](https://github.com/luau-lang/lute) — no Roblox Studio, no Open Cloud worker, no licenses. Pure standalone Luau runtime.

## Status: Phase 2 working ✅ — real .ts code through rbxtsc → lute-jest

```
Files: 2 passed, 0 failed, 2 total  (33ms)
Tests: 7 passed across math.spec.ts + inventory.spec.ts (real classes, iterators, hooks)
```

Also runs hand-written .spec.luau directly (Phase 1):

```
Files: 4 passed, 0 failed, 4 total  (60ms)  — examples/
```

Covers:
- Pure logic (`expect`, `describe`, `it`, hooks, `jest.fn()`)
- `@rbxts/services` polyfill (Workspace, ReplicatedStorage, dynamic services)
- `Instance.new` with `:GetChildren`, `:IsA`, `:Destroy`, `:Clone` etc.
- Datatypes: `Vector3`, `Vector2`, `UDim2`, `Color3`, `CFrame`, `Enum`
- `game:GetService(...)` global
- `@flamework/networking` auto-mock
- `@rbxts/jest-globals` import (compiled output uses `expect():toBe()` colon syntax)
- TS classes, ES6 array methods, iterators (via roblox-ts inlined helpers)

## Quickstart

```bash
# install Lute (one-time)
curl -L https://github.com/luau-lang/lute/releases/download/v1.0.0/lute-linux-x86_64.zip -o /tmp/lute.zip
unzip -d /tmp/lute-bin /tmp/lute.zip
chmod +x /tmp/lute-bin/lute

# run hand-written Luau specs
bun cli/index.ts examples/

# run a roblox-ts project end-to-end
bun cli/index.ts examples-ts/   # auto-detects tsconfig.json, runs rbxtsc, then runs out/
```

## Architecture

```
bun cli/index.ts <target>
  ├─ if target is a roblox-ts project (has tsconfig.json):
  │     bunx rbxtsc -p target/  → walk target/out/
  └─ for each *.spec.luau:
        spawn: lute runtime/runner.luau <spec>
          ├─ luau.compile + luau.load with custom env
          ├─ wrappedRequire:
          │    ├─ @rbxts/* / @flamework/* → polyfills
          │    ├─ @rbxts/jest-globals      → vendored jest
          │    ├─ ./relative               → fs read + recursive load
          │    └─ @std/* / @lute/*         → native passthrough
          ├─ RuntimeLib intercept: WaitForChild("RuntimeLib") → sentinel
          │    require(sentinel) → TS table with TS.import() that resolves
          │    ("TS", ...) → outDir/...luau, ("rbxts_include", ...) → polyfill
          └─ jest._run() reports pass/fail, exits 0/1
```

## Files

- `runtime/jest.luau` — jest-style test runtime (describe/it/expect/mocks/hooks). Supports both `.toBe()` and `:toBe()` calling conventions.
- `runtime/polyfills.luau` — all roblox polyfills in one file (services, datatypes, signal, instance, flamework, sift, t, charm)
- `runtime/runtime_lib.luau` — fake `TS` table for roblox-ts compiled output (TS.import resolves outDir + polyfill registry)
- `runtime/runner.luau` — Lute entry: custom require + spec executor + Instance interception for RuntimeLib
- `cli/index.ts` — Bun CLI: discovers `*.spec.luau` / `*.test.luau`, auto-compiles roblox-ts projects, spawns runner per file
- `examples/` — hand-written Luau specs proving each polyfill works
- `examples-ts/` — real roblox-ts project compiled and tested through the full pipeline
- `docs/RFC.md` — design rationale and roadmap

## Roadmap

- **Phase 1 (DONE):** MVP, hand-written Luau specs ✅
- **Phase 2 (DONE):** rbxtsc integration, RuntimeLib intercept, real TS classes/iterators ✅
- **Phase 3:** source-map reverse for stack traces (`.ts:line:col`), more matchers (`toMatchObject`, snapshots), real `@rbxts/charm` semantics, parallel runner
- **Phase 4:** Hybrid `--mode lute|studio|auto` — detect tests that need real Studio APIs (DataStores, raycasts, physics) and route them to a Studio MCP fallback
