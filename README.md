# lute-jest

Run roblox-ts/Luau jest-style tests under [Lute](https://github.com/luau-lang/lute) — no Roblox Studio, no Open Cloud worker, no licenses. Pure standalone Luau runtime.

## Status: Phase 1 MVP working ✅

```
Files: 4 passed, 0 failed, 4 total  (60ms)
```

15 tests pass across 4 example specs covering:
- Pure logic (`expect`, `describe`, `it`, hooks, mocks)
- `@rbxts/services` polyfill (Workspace, ReplicatedStorage, dynamic services)
- `Instance.new` with `:GetChildren`, `:IsA`, `:Destroy` etc.
- Datatypes: `Vector3`, `Vector2`, `UDim2`, `Color3`, `CFrame`, `Enum`
- `game:GetService(...)` global
- `@flamework/networking` auto-mock (events, functions)

## Quickstart

```bash
# install Lute (one-time)
curl -L https://github.com/luau-lang/lute/releases/download/v1.0.0/lute-linux-x86_64.zip -o /tmp/lute.zip
unzip -d /tmp/lute-bin /tmp/lute.zip
chmod +x /tmp/lute-bin/lute

# run examples
bun cli/index.ts examples/
```

## Architecture

```
bun cli/index.ts <spec>
  └─ spawns: lute runtime/runner.luau <spec>
       ├─ luau.compile + luau.load with custom env
       ├─ wrappedRequire:
       │    ├─ @rbxts/* / @flamework/* → polyfills
       │    ├─ @rbxts/jest-globals      → vendored jest
       │    ├─ ./relative               → fs read + recursive load
       │    └─ @std/* / @lute/*         → native passthrough
       └─ jest._run() reports pass/fail, exits 0/1
```

All polyfills live in a single file (`runtime/polyfills.luau`) to avoid require-cycle drama. The jest runtime (`runtime/jest.luau`) is a from-scratch ~250-line implementation of `describe`/`it`/`expect`/`beforeEach`/`jest.fn()` etc.

## Roadmap

- **Phase 1 (DONE):** MVP, examples, hello-world specs ✅
- **Phase 2:** roblox-ts compile integration (`rbxtsc` → load `out/`), source-map reverse for stack traces, more matchers (`toMatchObject`, `toMatchSnapshot`), real `@rbxts/charm` semantics, `Instance.new` with full parent metatable
- **Phase 3:** Hybrid `--mode lute|studio|auto` — auto-detect tests that need Studio (roblox-only APIs) vs ones that work under Lute, route accordingly

## Files

- `runtime/jest.luau` — jest-style test runtime (describe/it/expect/mocks/hooks)
- `runtime/polyfills.luau` — all roblox polyfills (services, datatypes, signal, instance, flamework, sift, t, charm)
- `runtime/runner.luau` — Lute entry point: custom require + spec executor
- `cli/index.ts` — Bun CLI: discovers `*.spec.luau` / `*.test.luau`, spawns runner per file
- `examples/` — sample specs proving each polyfill works
- `docs/RFC.md` — design rationale and roadmap
