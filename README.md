# Slickrock

A Ruby gem that random-walks a web UI in a real browser and shouts when the
app breaks underneath it.

Named for the Slickrock Trail in Moab: an unmarked route where you follow
painted dots across bare rock and pick your own way. That is the gem — no
scripted path, just a surface and a walker.

## Why this exists

Two bugs shipped to production on 2026-09-18 and neither was caught by a
large, healthy test suite:

1. **Pay-at-counter 422'd on every attempt.** A per-form CSRF token posted to
   a `formaction` URL. A browser test already clicked that exact button and
   passed, because the test env sets `allow_forgery_protection = false`.
2. **"Continue shopping" and every cart line's "edit" did nothing.** Both sit
   inside turbo-frames whose destinations have no matching frame, so Turbo
   fetched the page and discarded it. `rack_test` ignores frames and follows
   the `href`, so a rack_test test passes against the bug.

Both are *invisible to assertions someone thought to write*, and both are
blindingly obvious to anything that clicks the button and then asks "did the
page break?". Neither needs a model to find. They need a walker and an oracle.

**The thesis: the oracle is the valuable half, and it requires no AI.** The
model only helps choose *where* to walk.

## How it works

```
snapshot → check invariants → choose an action → perform it → repeat
```

- **Snapshot** — url, title, visible text, console messages, interactive controls.
- **Check** — every oracle runs before acting (and once more after the final
  action). First violation aborts with a full reproduction report.
- **Choose** — uniform random by default; Jev-weighted when steering is on.
- **Perform** — click it, or fill it.

A failure produces a **seed and a step list** — same seed replays the identical
journey. A human decides what earns a permanent deterministic test.

## Status

Early build (v0.1.0). Landed: value objects (`Control`, `Snapshot`,
`Journey`, `Result`, `Violation` with reproduction-shaped messages) and the
`Drivers::Fake` scripted page graph, 20 tests green. On the roadmap
(`docs/PLAN.md`): the `Walker` loop, the five built-in oracles, the Capybara
driver, keyless Jev steering, and the minitest mixin. First consumer will be
the Ako Tacos POS Rails app.

## Quickstart (today — no browser needed)

```ruby
gem "slickrock", github: "cmbaldwin/slickrock", group: :test
```

```ruby
driver = Slickrock::Drivers::Fake.new(pages: {
  "/cart" => { title: "Cart", text: "2 items",
               controls: [["Checkout", :link, "/checkout"]],
               console: [], status: 200 }
})
driver.visit("/cart")
driver.current_url # => "/cart"
```

## Oracles (roadmap — each its own class, keyword-configured)

| Oracle | Catches |
| --- | --- |
| `NoServerError` | Rails 500 page text/title |
| `NoStaleSession` | 422/auth-expiry page (wording configurable) |
| `NoTurboFrameMiss` | console "did not contain the expected \<turbo-frame" |
| `NoJsError` | uncaught console errors minus ignore-list |
| `NoBlankPage` | visible text under N chars |

Plus app lambdas for domain invariants. Oracles answer `message or nil` —
they never raise, never fetch, never sleep.

## Steering (roadmap — no key required)

One `classifier.dev` POST over control labels; confidence < 0.6 falls back to
uniform random; every network error rescues into random with a 5s timeout.

## What this will not find

Wrong prices, wrong copy, wrong business logic — anything needing a spec, not
an invariant. It finds crashes and contradictions. It runs on demand and
nightly, never as a deploy gate: a randomised test that blocks a deploy is a
randomised deploy.

## Development

```bash
bundle install
bundle exec rake test   # minitest
bundle exec rubocop
```

Ruby 3.2+, zero runtime dependencies (Capybara etc. are dev-only).
`# frozen_string_literal: true` everywhere. Design: `docs/SPEC.md`,
build order: `docs/PLAN.md`. MIT.
