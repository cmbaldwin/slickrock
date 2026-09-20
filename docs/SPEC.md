# Slickrock — design

A Ruby gem that random-walks a web UI in a real browser and shouts when the app
breaks underneath it.

Named for the Slickrock Trail in Moab: an unmarked route where you follow
painted dots across bare rock and pick your own way. That is the gem — no
scripted path, just a surface and a walker.

## Why this exists

Two bugs shipped to production on 2026-09-18 and neither was caught by a large,
healthy test suite:

1. **Pay-at-counter 422'd on every attempt.** A per-form CSRF token posted to a
   `formaction` URL. A browser test already clicked that exact button and
   passed, because the test env sets `allow_forgery_protection = false`.
2. **"Continue shopping" and every cart line's "edit" did nothing.** Both sit
   inside turbo-frames whose destinations have no matching frame, so Turbo
   fetched the page and discarded it. `rack_test` ignores frames and follows the
   `href`, so a rack_test test passes against the bug.

Both are *invisible to assertions someone thought to write*, and both are
blindingly obvious to anything that clicks the button and then asks "did the
page break?". Neither needs a model to find. They need a walker and an oracle.

**The thesis: the oracle is the valuable half, and it requires no AI.** The
model only helps choose *where* to walk.

## What it is

A loop:

```
snapshot → check invariants → choose an action → perform it → repeat
```

- **Snapshot** — url, title, visible text, console messages, and the list of
  interactive controls.
- **Check** — run every oracle against the snapshot. A violation aborts the walk
  and reports how to reproduce it.
- **Choose** — pick the next control. Uniform random by default; weighted by
  classification when steering is enabled.
- **Perform** — click it, or type into it.

## What it is not

- **Not a replacement for deterministic tests.** It finds crashes and violated
  invariants. It cannot tell you a price is *wrong*, only that it contradicts an
  invariant you stated.
- **Not a CI gate.** A randomised test that blocks a deploy is a randomised
  deploy. It runs on demand and in a nightly-style job.
- **Not a recorder.** It does not generate test files. A failure produces a seed
  and a step list; a human decides what deserves a permanent test.

## Architecture

Four parts, each replaceable.

### 1. Driver — how to touch a browser

An adapter interface, so the gem is not married to Capybara:

```ruby
visit(url)          # navigate
current_url         # String
title               # String
text                # visible page text
controls            # [Control] — interactive, visible, enabled
click(control)
fill(control, value)
console_messages    # [{level:, text:}] since last call
screenshot(path)
```

`Control` is `Struct.new(:ref, :label, :kind, :enabled, :meta)`.
`kind` is `:button | :link | :field | :select | :checkbox | :radio`.
`ref` is driver-private (a Capybara node, a Playwright selector).

**Capybara adapter ships first** — it is what the target app has. A Playwright
adapter is possible precisely because the interface is this small.

### 2. Oracle — what counts as broken

A list of objects responding to `call(snapshot) -> nil | Violation`. Built-ins,
each written from a real failure:

| Oracle | Catches |
|---|---|
| `NoServerError` | Rails 500 page, "We're sorry, but something went wrong" |
| `NoStaleSession` | the 422 `unprocessable_entity` page — **bug #1** |
| `NoTurboFrameMiss` | console `did not contain the expected <turbo-frame` — **bug #2** |
| `NoJsError` | uncaught JS exceptions in console |
| `NoBlankPage` | navigated somewhere with no content |

Plus app-supplied lambdas for domain invariants:

```ruby
oracle << ->(s) { "total mismatch" if s.text =~ /Total ¥(\d+)/ && ... }
```

An oracle returns a short string (the violation) or nil. The walker wraps it
with the seed, step index and journey.

### 3. Steering — where to walk next

Default is uniform random over enabled controls.

`Steering::Jev` classifies the page's control labels in one keyless call to
`classifier.dev` (model `jev`), then weights selection by category:

```ruby
weights: {
  "adds or changes cart contents" => 5,
  "changes an option or setting"  => 3,
  "navigates away"                => 2,
  "completes a purchase"          => 1,
  "destructive or irreversible"   => 0,
}
```

Measured on the target app's real controls: "Pay with Stripe" → *completes a
purchase* at 0.99, "← Continue shopping" → *navigates away* at 1.00, `+`/`−` →
*adds or changes* at 1.00. Ambiguous controls (`×`, `Edit`) land at 0.53–0.61,
which is why low-confidence answers fall back to the default weight rather than
being trusted.

**Steering must be optional and degradable.** No key is required, but the
network can still fail; any error falls back to uniform random and the walk
continues. A test that fails because a classifier was down is worthless.

Labels are cached per page-signature so a 40-step walk is a handful of calls,
not 40.

### 4. Journey — reproducibility

Every walk is driven by `Random.new(seed)` and prints its seed on start and on
failure. `Journey` records each step (`url`, `label`, `kind`, `action`).

A violation raises `Slickrock::Violation` carrying seed, step index, the
journey, and a screenshot path. Re-running with the same seed replays the same
walk, **provided the app starts in the same state** — which is a caveat the
report states plainly rather than pretending determinism it cannot guarantee.

## Public API

Minimal surface:

```ruby
Slickrock.walk(
  start:,                     # path or url
  driver:,                    # Slickrock::Drivers::Capybara.new(page)
  steps:    40,
  seed:     Random.new_seed,
  oracle:   Slickrock::Oracle.defaults,
  steering: nil,              # or Slickrock::Steering::Jev.new
  avoid:    [],               # label patterns never clicked (e.g. /log ?out/i)
  on_step:  nil               # callback for logging
) # => Slickrock::Result
```

Plus a test mixin so the common case is one line:

```ruby
class CartFuzzTest < ApplicationSystemTestCase
  include Slickrock::Minitest

  test "the cart survives a random walk" do
    slickrock_walk cart_path, steps: 40
  end
end
```

## Decisions worth recording

- **Oracles return strings, not booleans.** The message *is* the report.
- **`avoid:` is a blunt regexp list, not a classifier job.** "Never click log
  out" must not depend on a network call.
- **Controls are re-read every step.** The DOM changes under you; caching nodes
  across a click is how monkey testers produce stale-element noise instead of
  bugs.
- **The walk stops at the first violation.** Continuing past a broken page finds
  cascading nonsense, not new bugs.
- **No `sleep`.** Waiting is the driver's job (Capybara auto-waits).

## Testing the tester

The gem's own suite uses a `Drivers::Fake` — a scripted page graph with no
browser — so walker, oracle, steering and journey are tested deterministically
and fast. The Capybara adapter gets a small integration test against a static
Rack app. `Steering::Jev` is tested against a stubbed HTTP response plus one
opt-in live test.

## Out of scope for v0.1

Playwright adapter, form-value generation beyond simple strings, multi-tab,
authentication flows, coverage reporting, test generation from a journey.
