# lute-jest — Task Tracker

> Goal: Run roblox-ts/Luau jest tests under Lute, no Roblox runtime needed.

## Phase 1 — MVP (proof of concept)
- [ ] **P1.1** Install Lute on the VPS, verify it runs basic Luau scripts
- [ ] **P1.2** Vendor jest-lua, identify Roblox-specific dependencies that block running under Lute
- [ ] **P1.3** Build polyfill layer: Instance tree, RBXScriptSignal, basic services as empty mocks
- [ ] **P1.4** `require()` redirector — intercept `@rbxts/*` and `@flamework/*` imports, route to polyfills
- [ ] **P1.5** Bun CLI wrapper: `lute-jest [args]` — runs rbxtsc compile, then spawns lute with runner.luau
- [ ] **P1.6** Hello-world spec: pure-logic test (1+1=2) compiles and runs end-to-end
- [ ] **P1.7** Source-map reverse: Luau errors → .ts:line:col

## Phase 2 — Real coverage
- [ ] **P2.1** Auto-mock `@rbxts/services` — return Proxy-like tables that record calls
- [ ] **P2.2** Auto-mock `@flamework/networking` — events/functions become spy objects
- [ ] **P2.3** Vector3, CFrame, UDim2, Color3 math implementations
- [ ] **P2.4** Wire up Lute coverage instrumentation (port from jest-roblox-cli)
- [ ] **P2.5** Run a real spec from Anime-Reborn-Simulation under lute-jest

## Phase 3 — Hybrid mode
- [ ] **P3.1** `--mode lute` (default) and `--mode studio` (fallback to jest-roblox-cli)
- [ ] **P3.2** Auto-detect: route specs that import forbidden APIs (DataStore, MemoryStore) to studio mode
- [ ] **P3.3** Unified output formatter so both modes look the same

## Outreach
- [x] **O.1** Write RFC doc (`docs/RFC.md`) — proposal + architecture + benefits
- [x] **O.2** Comment on jsdotlua/jest-lua issue #2 — draft in `docs/OUTREACH.md` (notnice to send manually)
- [x] **O.3** N/A — decision: no outreach to christopher-buss (per notnice)

## Status legend
- `[ ]` not started
- `[~]` in progress
- `[x]` done
- `[!]` blocked
