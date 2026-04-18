# RFC: lute-jest — running roblox-ts jest tests under Lute

**Status:** Draft
**Author:** notnice (matthewradulovich123)
**Date:** 2026-04-18
**Repo:** <https://github.com/matthewradulovich123/lute-jest>

---

## TL;DR

Run roblox-ts/Luau jest specs directly under [Lute 1.0](https://github.com/luau-lang/lute) — no Roblox Studio, no Open Cloud worker, no `.rbxl` round-trip. A Bun CLI compiles your TS, a `require()` redirector swaps `@rbxts/services` and `@flamework/networking` for polyfills, jest-lua runs in-process, and a sourcemap reverse turns Luau stack frames back into `.ts:line:col`. Tests that genuinely need real Roblox APIs fall back to christopher-buss/jest-roblox-cli via `--mode studio`.

The result: pure-logic specs run in **<1s cold** instead of 10–60s of Studio boot, CI doesn't need a Windows runner with a Roblox license, and the dev loop stops feeling like a punishment.

---

## Motivation

Today, if you write jest specs against a roblox-ts codebase you have exactly two options:

1. **Studio backend** (jest-roblox-cli's `--studio` mode). Boots Roblox Studio, syncs via Rojo, runs the suite, scrapes output. Slow (10–60s startup), requires a desktop OS with a logged-in Roblox account, flaky on CI, and entirely unusable on Linux runners.
2. **Open Cloud backend** (jest-roblox-cli's `--cloud` mode). Uploads a place file, fires off an Open Cloud Luau execution task, polls for results. Eliminates the Studio dependency but inherits Open Cloud's quotas, latency (seconds per run minimum), and the ergonomics of "your test runner is an HTTP API on someone else's server."

For ~80% of the specs we write in Anime Reborn — pure logic, math, store reducers, flamework controller transitions, polyfilled service interactions — neither option makes sense. We don't actually need a DataModel. We need a Luau interpreter that can `require()` our code and run `expect(thing).toBe(otherThing)`.

Lute 1.0 (released 2026-04-17) is exactly that: a standalone Luau runtime, distributable through rokit, with a stable C API and FFI. It's already used by jest-roblox-cli for **coverage instrumentation** but not as the actual runtime. lute-jest closes that gap.

---

## Goals

- **G1.** Run jest specs written against `@rbxts/jest-globals` end-to-end under Lute, with no Roblox process involved.
- **G2.** Cold start under one second for a small suite. No JVM-style warmup.
- **G3.** Native CI on Linux. `lute-jest` should drop into a GitHub Actions ubuntu-latest runner with `rokit install` + `bun install`.
- **G4.** Errors point at TypeScript source — `.ts:line:col`, not `.luau`.
- **G5.** Hybrid escape hatch: when a spec genuinely needs the real engine, defer to jest-roblox-cli without making the user rewrite anything.
- **G6.** Compatible with the existing rbxts-jest type definitions and rbxts-transformer-jest hoisting transform. Don't fork the user-facing API.

## Non-goals

- **NG1.** We are **not** reimplementing Roblox. No physics, no rendering, no real Workspace simulation.
- **NG2.** Not a replacement for jest-roblox-cli. It complements it. If your spec needs `DataStoreService` to actually persist, run it in studio mode.
- **NG3.** Not a generic Luau test runner — it's specifically for the roblox-ts/jest workflow. (A pure Luau jest port for Lute is a related but separate project, see "Open questions.")
- **NG4.** Not a port of every `@rbxts/*` package. Polyfills cover the common surface (services, signals, datatypes, networking). Long-tail packages get auto-mocked or the user supplies their own mock.

---

## Detailed design

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Bun CLI (lute-jest)                                         │
│  ─────────────────────────────────────────────────────────   │
│  1. Parse args (jest-cli compatible: --watch, -t, etc.)      │
│  2. Spawn rbxtsc → ./out/*.luau + sourcemap.json             │
│  3. Generate runner.luau (entrypoint that loads jest-lua)    │
│  4. spawn lute runner.luau --                                │
│  5. Pipe stdout, post-process: rewrite .luau frames → .ts    │
│  6. Exit code = jest exit code                               │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│  Lute process                                                │
│  ─────────────────────────────────────────────────────────   │
│  runner.luau                                                 │
│    ├── require-redirector  (patched _G.require)              │
│    │     ├── @rbxts/services       → polyfills/services      │
│    │     ├── @flamework/networking → polyfills/networking    │
│    │     ├── @rbxts/*              → out/node_modules/...    │
│    │     └── ./out/...             → file system             │
│    │                                                         │
│    ├── jest-lua (vendored, Lute-adapted)                     │
│    │     ├── expect, describe, it, beforeEach…               │
│    │     ├── jest.fn, jest.mock, jest.spyOn                  │
│    │     └── reporters → JSON over stdout                    │
│    │                                                         │
│    └── polyfills/                                            │
│          ├── datatypes (Vector3, CFrame, UDim2, Color3, …)   │
│          ├── services  (Players, RunService, …, all stubs)   │
│          ├── signals   (RBXScriptSignal in pure Luau)        │
│          └── networking (events/functions → spy objects)     │
└──────────────────────────────────────────────────────────────┘
```

### `require()` redirection

Lute exposes `require` via `@lute/require` and lets us install a custom resolver before any user code loads. The redirector is a single Luau file that the generated `runner.luau` loads first:

```lua
local resolve = require("@lute/require")
local POLYFILL_ROOT = "lute-jest/polyfills"

local rules = {
    { prefix = "@rbxts/services",        target = POLYFILL_ROOT .. "/services" },
    { prefix = "@flamework/networking",  target = POLYFILL_ROOT .. "/networking" },
    { prefix = "@rbxts/",                target = "out/node_modules/" },
    -- everything else falls through to the default file-system resolver
}

resolve.setHook(function(spec, fromFile)
    for _, rule in rules do
        if spec:sub(1, #rule.prefix) == rule.prefix then
            return rule.target .. spec:sub(#rule.prefix + 1)
        end
    end
    return nil  -- default
end)
```

The exact API surface depends on Lute 1.0's final require hook (we'll pin to whichever shape ships); fallback is monkey-patching `_G.require` before the suite loads.

### Polyfill strategy

Three tiers:

1. **Real implementation** for things that are pure math: `Vector3`, `CFrame`, `UDim2`, `Color3`, `Region3`. These get straight-line Luau ports of the documented behavior. Verified against a "datatypes parity" spec suite that runs in both Studio and Lute.
2. **Functional stubs** for things with observable behavior we care about: `RBXScriptSignal` (Connect/Fire/Wait), `Players.PlayerAdded`, `RunService.Heartbeat`. These behave like real signals but never fire on their own — tests fire them manually.
3. **Spy mocks** for everything else: `DataStoreService`, `MemoryStoreService`, `HttpService`, `MarketplaceService`. Every method returns `jest.fn()` by default, so calls are recorded and assertable. Users override with `jest.mock()` when they need specific return values.

Flamework networking is special: events and functions become spy objects whose `:Fire` / `:Invoke` are `jest.fn()`, and whose `.OnServerEvent` / `.OnClientInvoke` are signal stubs you can fire from the test. This matches how most flamework networking tests are already written.

### Source-map reverse

`rbxtsc` already emits `out/sourcemap.json` (rojo-style). The CLI parses that once at startup and builds an in-memory `(luauPath, line) → (tsPath, line, col)` map. Every line of jest output gets passed through a regex that finds `path/to/file.luau:42` patterns and rewrites them. Stack frames inside Lute's own runtime are filtered out unless `--verbose`.

For `expect(...).toBe(...)` mismatches, we also intercept jest-lua's failure message construction so the "at" line in the diff points at the `.ts` location, not the compiled output.

### Hybrid mode

`lute-jest --mode hybrid` (the eventual default) does this:

1. Static-analyze each spec file at compile time. If it imports any module on the **forbidden list** (`DataStoreService`, `MemoryStoreService`, `MessagingService`, anything that needs server-only Roblox infrastructure to be meaningful), tag it `studio-only`.
2. Run all `lute-safe` specs in-process under Lute.
3. Shell out to `jest-roblox-cli --studio` (or `--cloud`) for the studio-only specs, with the same CLI args forwarded.
4. Merge the two result streams into one report. Coverage is a union.

`--mode lute` skips step 3 and fails any spec that hits a forbidden API. `--mode studio` skips Lute entirely and is just a passthrough to jest-roblox-cli, kept for parity testing.

---

## Comparison

| Capability                       | jest-roblox-cli `--studio` | jest-roblox-cli `--cloud` | **lute-jest `--mode lute`** | **lute-jest `--mode hybrid`** |
| -------------------------------- | -------------------------- | ------------------------- | --------------------------- | ----------------------------- |
| Cold start (small suite)         | 10–60 s                    | 5–15 s                    | **<1 s**                    | <1 s + studio for tagged      |
| Linux CI, no license             | ❌                         | ✅                         | ✅                           | ✅ (cloud fallback)            |
| Real Roblox APIs                 | ✅                         | ✅                         | ❌ (polyfills only)          | ✅ (for tagged specs)          |
| Coverage                         | ✅ (Lute instrument)       | ✅ (Lute instrument)       | ✅ (Lute native)             | ✅ (merged)                    |
| Per-test isolation cost          | low (in one Studio)        | high (per request)        | very low                    | low                           |
| Works offline                    | ✅                         | ❌                         | ✅                           | depends                       |
| Source = `.ts` in errors        | ✅ (already)               | ✅                         | ✅                           | ✅                             |

---

## Roadmap

Mirrors `TASKS.md`. Phase numbers map 1:1 to the P*.* / O.* items there.

### Phase 1 — MVP (proof of concept)
- Install Lute on the dev VPS, verify basic Luau runs.
- Vendor jest-lua, identify the Roblox-only seams.
- Minimal polyfills: Instance tree shell, `RBXScriptSignal`, empty service stubs.
- `require()` redirector for `@rbxts/*` and `@flamework/*`.
- Bun CLI: compile via rbxtsc, spawn lute, pipe output.
- Hello-world spec (`expect(1 + 1).toBe(2)`) green end-to-end.
- Source-map reverse: `.luau` frames rewritten to `.ts`.

### Phase 2 — Real coverage
- Auto-mock `@rbxts/services`: services return Proxy-like recording tables.
- Auto-mock `@flamework/networking`: spy events/functions.
- Real datatypes: `Vector3`, `CFrame`, `UDim2`, `Color3` math.
- Wire up Lute's coverage instrumentation (port the bits jest-roblox-cli already uses).
- Run an actual spec from the Anime Reborn sequel codebase under lute-jest.

### Phase 3 — Hybrid mode
- `--mode lute` (default) and `--mode studio` (jest-roblox-cli passthrough).
- Static analysis to auto-route forbidden-API specs to studio mode.
- Unified output formatter: hybrid runs look like one suite.

### Phase 4 (post-RFC, speculative)
- Watch mode that re-runs only changed specs, leveraging Lute's fast cold start.
- VS Code adapter (jest-extension compatible).
- Optional: publish polyfills as a standalone `@rbxts/lute-polyfills` package so other tools can reuse them.

---

## Risks and open questions

**R1. Polyfill drift.** The polyfills will lag real Roblox behavior. Mitigation: a "datatypes parity" suite that runs both under Lute and under Studio in CI, fails if results diverge. For service stubs, we explicitly don't promise behavioral parity — they're spies, not simulators.

**R2. Tests that depend on real Roblox networking semantics** (replication ordering, RemoteEvent rate limiting, player join/leave timing). These genuinely can't run under Lute and shouldn't try to. Hybrid mode's auto-tagging needs to be conservative — when in doubt, route to studio.

**R3. Lute API churn pre-1.0 has been heavy.** With 1.0 shipped (2026-04-17) the public API should be stable, but we'll pin to a specific Lute version in `rokit.toml` and bump deliberately.

**R4. jest-lua is a moving target.** We vendor it (don't depend on it as a submodule) so we can patch Roblox-specific calls. Cost: we have to manually pull upstream changes. Worth it for reliability.

**R5. Flamework networking spy ergonomics.** Real flamework networking has decorators and runtime metadata. Our spy version skips all that and just hands you `jest.fn()` for each event. For most tests this is what you want; for tests that exercise the decorator pipeline itself, use `--mode studio`.

**Open questions:**

- **OQ1.** Should the polyfills live in this repo or be a separate package? Argument for separate: other Lute-based tools (REPL, scripts) could use them. Argument for here: tighter coupling to lute-jest's expectations.
- **OQ2.** Should this live under [jsdotlua](https://github.com/jsdotlua) (since it's effectively answering jest-lua issue #2 for the Lute case)? Or stay independent and just play nice with jest-lua upstream?
- **OQ3.** Should we collaborate with christopher-buss to make this a `--mode lute` flag inside jest-roblox-cli rather than a separate tool? See `docs/OUTREACH.md`.
- **OQ4.** Pure-Luau (non-roblox-ts) jest support. Out of scope for now, but the plumbing would be 80% the same. Defer until someone asks.

---

## Prior art

- **[jsdotlua/jest-lua](https://github.com/jsdotlua/jest-lua)** — the canonical Jest port for Lua, currently Roblox-only at runtime. [Issue #2](https://github.com/jsdotlua/jest-lua/issues/2) is the open ask for non-Roblox runtime support; this RFC answers it for Lute specifically.
- **[christopher-buss/jest-roblox-cli](https://github.com/christopher-buss/jest-roblox-cli)** — runs roblox-ts/Luau jest specs via Open Cloud or Studio, uses Lute internally for **coverage instrumentation** but not as the test runtime itself. lute-jest extends Lute's role from "coverage tool" to "test runtime."
- **[christopher-buss/rbxts-transformer-jest](https://github.com/christopher-buss/rbxts-transformer-jest)** — TypeScript transformer that hoists `jest.mock(...)` calls above imports at compile time. lute-jest expects this transformer to be installed; we don't reinvent the hoist.
- **[littensy/rbxts-jest](https://github.com/littensy/rbxts-jest)** — TypeScript type definitions for Jest Lua. Unchanged consumer surface — `import { expect, describe, it } from "@rbxts/jest-globals"` works in both worlds.
- **[luau-lang/lute](https://github.com/luau-lang/lute)** — the standalone Luau runtime, 1.0 released 2026-04-17. Provides the in-process require hook and FFI we build on.
- **[rojo-rbx/rokit](https://github.com/rojo-rbx/rokit)** — toolchain manager. `rokit add luau-lang/lute` is how end users install Lute alongside roblox-ts/rojo.
- **[oven-sh/bun](https://github.com/oven-sh/bun)** — JS runtime for the CLI orchestrator. Picked over Node for cold-start speed; the CLI feels "instant" instead of "loading."

---

## Appendix: end-user UX (target)

```bash
# install
rokit add luau-lang/lute
bun add -D lute-jest

# package.json
"scripts": {
  "test": "lute-jest",
  "test:watch": "lute-jest --watch",
  "test:studio": "lute-jest --mode studio"
}

# CI (.github/workflows/test.yml)
- uses: oven-sh/setup-bun@v2
- uses: rojo-rbx/setup-rokit@v1
- run: bun install
- run: bun test    # ~2s for a 100-spec pure-logic suite
```

That's the whole pitch: `bun test` works on Linux CI, in seconds, against your existing roblox-ts jest specs, with no Studio in the loop.
