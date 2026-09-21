# Slickrock

A Ruby gem that walks a web UI in a real browser and shouts when the app
breaks underneath it. **Jev** — TypeSafe's decision model — picks where to
walk; plain-Ruby oracles decide what counts as broken.

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

**The thesis: the oracle is the valuable half, and it requires no AI.** Jev is
the other half — it spends the step budget where bugs live, one typed question
per page, for fractions of a cent per walk (numbers in [Steering](#steering--jev-picks-the-next-click)).
Without it the walk is uniform random and still finds both bugs above; with it
it finds them sooner.

## How it works

```
snapshot → check invariants → choose an action → perform it → repeat
```

- **Snapshot** — url, title, visible text, console messages, interactive controls.
- **Check** — every oracle runs before acting (and once more after the final
  action). First violation aborts with a full reproduction report.
- **Choose** — Jev ranks the controls and weights the draw; uniform random without it.
- **Perform** — click it, or fill it.

A failure produces a **seed and a step list** — same seed replays the identical
journey. A human decides what earns a permanent deterministic test.

## Status

v0.1.0, in build. Core is in: value objects, `Drivers::Fake`, the five
oracles, the `Walker`, `Steering::Jev`, `Drivers::Capybara`, and the
`Slickrock::Minitest` mixin. First consumer is the Ako Tacos POS Rails app;
the deploy-time walk (Phase 4) lives there. Build order: `docs/PLAN.md`.

## Quickstart

```ruby
# Gemfile
group :test do
  gem "slickrock", github: "cmbaldwin/slickrock"
end
```

A walk returns a `Result` — it does not raise. Turning a violation into a test
failure is the caller's job, which keeps the library usable from a deploy
script that wants to serialise the outcome rather than catch an exception.

```ruby
result = Slickrock.walk(
  start:  "/cart",
  driver: Slickrock::Drivers::Capybara.new(page),
  steps:  40,
  avoid:  [ /Pay with/i, /log ?out/i ]   # never clicked, ever
)

puts result.seed                  # replay handle, printed on every run
raise result.violation.message unless result.ok?
```

From a system test the mixin is one line. A walk returns a `Result` rather
than raising, so the mixin is the thing that turns a violation into a
failure — a deploy script can serialise the same result instead.

```ruby
class CartFuzzTest < ApplicationSystemTestCase
  include Slickrock::Minitest

  test "the cart survives a random walk" do
    slickrock_walk cart_path, steps: 40, avoid: [ /Pay with/i, /log ?out/i ]
  end
end
```

No browser required to try the loop — `Drivers::Fake` is a scripted page graph,
and it is what the gem's own suite runs against (in about a millisecond):

```ruby
Slickrock.walk(
  start:  "/cart",
  driver: Slickrock::Drivers::Fake.new(pages: {
    "/cart"     => { title: "Cart", text: "Your order, with enough text to read",
                     controls: [["Checkout", :link, "/checkout"]] },
    "/checkout" => { title: "Checkout", text: "Card details and a pay button",
                     controls: [["Back to cart", :link, "/cart"]] }
  }),
  steps: 10, seed: 42
)
```

A page with no controls is a dead end: the walk ends there cleanly, returning
an ok `Result` with fewer steps than you asked for. That is why `/checkout`
above has a way back.

Note `NoBlankPage` defaults to 20 characters of visible text — toy fixtures
shorter than that will trip it. It is configurable.

## Oracles — each its own class, keyword-configured

| Oracle | Catches |
| --- | --- |
| `NoServerError` | Rails 500 page text/title |
| `NoStaleSession` | 422/auth-expiry page (wording configurable) |
| `NoTurboFrameMiss` | console "did not contain the expected \<turbo-frame" |
| `NoJsError` | uncaught console errors minus ignore-list |
| `NoBlankPage` | visible text under N chars |

Plus app lambdas for domain invariants. Oracles answer `message or nil` —
they never raise, never fetch, never sleep.

## Steering — Jev picks the next click

One Jev call per page ranks the controls, so the step budget goes on the cart
rather than the footer. Jev answers a typed question about the page — no
prompt-and-parse, no free text to sanitise.

```ruby
steering = Slickrock::Steering::Jev.new
result = Slickrock.walk(..., steering: steering)
result.usage   # { calls:, input_tokens:, output_tokens:, request_bytes: }
```

**Every failure degrades to uniform random** — bad key, timeout, malformed
response, no network. A test that fails because a model was unreachable is
worse than no test.

**Programming rules** (SPEC §3 has the full version): keyed direct endpoint
first with keyless fallback; the state names exactly what the question judges;
instructions state what counts as *enough*, positively; below-threshold
confidence falls back, never decides.

### Getting a key

A key is optional — with none, steering falls back to the keyless
`classifier.dev` endpoint and works out of the box. It is unauthenticated and
carries no rate or availability guarantee, so treat it as best-effort — fine for
trying the gem, and for a walk that runs on every deploy use a real key from
[console.typesafe.ai/keys](https://console.typesafe.ai/keys).

Slickrock looks for one in three places, in order:

```ruby
Slickrock::Steering::Jev.new(api_key: ENV["MY_KEY"])   # 1. explicit
```
```bash
export TYPESAFE_API_KEY=...                             # 2. environment
jev auth set                                            # 3. the jev CLI's store
```

Option 3 reads `~/.config/jev-cli/credentials.json`, so if you already use the
`jev` CLI there is nothing else to configure. Never commit the key; a malformed
or unreadable credentials file is treated as "no key", never as an error.

Jev is billed on **input tokens only** ($0.042 / million; output is free).
`usage` counts real HTTP calls, not walker steps — a page signature is cached,
so revisiting the same controls is free. We do not have a local tokeniser;
these numbers come from the TypeSafe `usage` field on each response.

Measured on Ako Tacos (the first consumer), 2026-09-20: a 20-step cart walk
during a production deploy, local test server, real Chrome, real Jev API,
pay/logout on `avoid:`. Finished clean.

| | Ako Tacos, 20-step deploy walk |
| --- | --- |
| Calls | 17 |
| Input tokens | 9,438 |
| Output tokens | 1,997 (free) |
| Cost | ~$0.00040 |

About 555 input tokens per call. A thousand deploys like that is about $0.40.

**Steering biases the walk; it does not police it.** The winner gets full
weight and everything else a fraction, so an unwanted control still gets picked
eventually — on a nine-control page that is roughly 8% per step, which across a
twenty-step walk is close to certain. Anything that must *never* be clicked
belongs in `avoid:`, which is a plain regexp list: deterministic, no network,
and it cannot be talked out of it by a confident model.

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
