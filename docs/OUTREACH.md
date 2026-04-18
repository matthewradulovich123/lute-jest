# lute-jest — Outreach Drafts

> Drafts only. Do not send without notnice's review.

---

## Draft: Anime Reborn dev server announcement

**Channel:** #dev (or wherever team chat lives)
**Audience:** Yoda, oo, the rest of the team
**Length target:** under 1500 chars

> yo — been hacking on something this week. **lute-jest**: runs our jest specs directly under [Lute 1.0](https://github.com/luau-lang/lute) (the standalone Luau runtime that dropped yesterday), no Studio in the loop.
>
> the pitch: ~80% of our specs are pure logic — store reducers, math, flamework controller transitions. they don't need a DataModel, they need a Luau interpreter. right now we either boot Studio (10–60s, Windows-only) or hit Open Cloud (slow, quotas). lute-jest does it in <1s, on Linux CI, no license required.
>
> how it works:
> • Bun CLI compiles TS → Luau via rbxtsc
> • patched `require()` redirects `@rbxts/services` and `@flamework/networking` to polyfills
> • vendored jest-lua runs the suite in-process under Lute
> • sourcemap reverse so errors show `.ts:line:col`
> • hybrid mode for specs that genuinely need real Roblox APIs (DataStore, MessagingService, etc) — falls back to a Studio/Open-Cloud runner
>
> RFC is here: <https://github.com/matthewradulovich123/lute-jest/blob/main/docs/RFC.md>
>
> phase 1 (MVP, hello-world spec end-to-end) is in flight. would love eyes on the RFC before I get too deep — especially the polyfill strategy and the forbidden-API list for hybrid auto-routing. if there's a spec in our codebase you've always wanted to run faster, drop it in the thread, that's my Phase 2 target.

---

## Draft: Comment on jsdotlua/jest-lua#2

**URL:** <https://github.com/jsdotlua/jest-lua/issues/2>
**Tone:** friendly, collaborative, not pitchy

```markdown
Hey — wanted to flag this from the Lute side, since #2 has been the catch-all for "non-Roblox runtime support."

I've been building [**lute-jest**](https://github.com/matthewradulovich123/lute-jest), which runs roblox-ts jest specs directly under [Lute 1.0](https://github.com/luau-lang/lute) (released 2026-04-17). It vendors jest-lua and adapts the Roblox-specific seams behind a `require()` redirector + polyfill layer (`@rbxts/services`, `@flamework/networking`, datatypes). For the roblox-ts/jest workflow it's effectively a "Lute backend" answer to this issue.

Full design here: <https://github.com/matthewradulovich123/lute-jest/blob/main/docs/RFC.md>

A few open questions I'd love your take on:

1. **Vendor vs upstream.** Right now I vendor jest-lua so I can patch the Roblox-only call sites (Instance walks, signal internals, a couple of error-formatting paths). Would you be open to upstream PRs that gate those behind a runtime detector (`if game then ... else ... end`-style), so jest-lua itself runs on both Roblox and Lute from one source tree? That seems closer to the spirit of #2 than a permanent fork.

2. **Org home.** If lute-jest stabilizes, would it make more sense as a sibling project under [jsdotlua](https://github.com/jsdotlua) (closer to jest-lua's release cadence and tests), or to stay independent and just track upstream? No strong preference on my end — happy either way, just don't want to step on toes.

3. **Lune/Luvit.** I've intentionally scoped this to Lute because that's what I need for our Roblox CI, but the same redirector/polyfill split would extend to Lune trivially. If anyone's already exploring that I'd love to compare notes before we accidentally ship two slightly different polyfill layers.

Happy to open draft PRs for whichever direction makes sense, or to keep iterating in lute-jest and revisit once the MVP is green. Either way, wanted to drop this here so #2 doesn't look stalled.
```
