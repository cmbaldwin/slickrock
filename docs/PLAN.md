# Slickrock — implementation plan

Design: [SPEC.md](SPEC.md). Tasks are grouped so independent ones can run in
parallel. Each states what it owns, what it must not touch, and how it is
verified.

**House rules for every task**

- Ruby 3.2+, zero runtime dependencies. Capybara and the test framework are
  development dependencies only — a consumer brings their own.
- `# frozen_string_literal: true` everywhere.
- Minitest, `bundle exec rake test`. Rubocop via `rubocop-rails-omakase`.
- No `sleep` in library code, ever.
- Public methods get a comment saying *why*, not *what*.

## Phase 0 — skeleton (must land before anything else)

**0.1 Gem scaffold**
`slickrock.gemspec`, `Gemfile`, `Rakefile`, `lib/slickrock.rb`,
`lib/slickrock/version.rb`, `.rubocop.yml`, `.gitignore`, `test/test_helper.rb`.
Gemspec: MIT, summary from SPEC's first paragraph, homepage
`https://github.com/cmbaldwin/slickrock`, `required_ruby_version >= 3.2`.
Dev deps: `minitest`, `rake`, `rubocop-rails-omakase`, `capybara`, `rack`.
Verify: `bundle install && bundle exec rake test` runs zero tests, green.

## Phase 1 — core (parallel after 0.1)

**1.1 `Control` + `Snapshot` + `Journey` + `Result` + errors**
Plain value objects, no behaviour beyond predicates.
- `Control = Struct.new(:ref, :label, :kind, :enabled, :meta, keyword_init: true)`
  with `#enabled?` and a `#to_s` that is readable in a failure report.
- `Snapshot`: `url, title, text, controls, console_messages`.
- `Journey`: append-only list of steps; `#to_s` renders a numbered list.
- `Result`: `seed, steps_taken, journey, violation` + `#ok?`.
- `Slickrock::Error`, `Slickrock::Violation < Error` carrying
  `seed, step_index, journey, screenshot_path, message`. Its `#message` must be
  a complete reproduction report — seed first.
Verify: unit tests for `#to_s` output and `Violation#message` shape.

**1.2 `Drivers::Fake`**
A scripted page graph for testing the gem without a browser:
```ruby
Drivers::Fake.new(pages: {
  "/cart" => { title: "Cart", text: "…", controls: [["Edit", :link, "/edit"]],
               console: [], status: 200 },
})
```
Implements the full driver interface from SPEC §1. `click` follows the mapped
destination; unknown destination → a `404` page. Records visited urls.
Verify: unit tests covering navigation, console surfacing, disabled controls.

**1.3 Oracles**
`Oracle.defaults` returning the five built-ins from SPEC §2, each its own class
in `lib/slickrock/oracles/`. Each is `#call(snapshot) -> String | nil`.
- `NoServerError`: matches Rails' 500 page text and `<title>` forms.
- `NoStaleSession`: matches the 422 page — title/heading wording AND a url
  ending `/checkout/cash`-style POST target. Document that the wording is
  app-specific and configurable via `matching:`.
- `NoTurboFrameMiss`: console text includes
  `did not contain the expected <turbo-frame`.
- `NoJsError`: console level `severe`/`error`, excluding a configurable
  ignore-list (favicon 404s, third-party wallet noise).
- `NoBlankPage`: visible text shorter than N chars (default 20).
Each takes keyword config so an app can retune without subclassing.
Verify: one test per oracle, both the firing and the silent case.

**1.4 `Walker`**
The loop from SPEC. Owns: seeding, step budget, oracle evaluation order
(**check before acting, and once more after the final action**), `avoid:`
filtering, `on_step` callback, stopping at the first violation, and screenshot
capture on failure.
Depends on 1.1 + 1.2 to test.
Verify: with `Drivers::Fake` — a clean graph walks its full budget; a graph
with a poisoned page fails at the right step with the right message; the same
seed produces the identical journey; `avoid:` is never clicked; a dead end (no
controls) ends the walk cleanly rather than raising.

## Phase 2 — integrations (parallel after Phase 1)

**2.1 `Drivers::Capybara`**
Wraps a Capybara session. `controls` collects `button, a[href], input[type=submit],
select, input:not([type=hidden])`, filtered to visible+enabled, labelled by
visible text → `aria-label` → `value` → `placeholder` → `name`. `console_messages`
reads `page.driver.browser.logs.get(:browser)` when the driver supports it and
returns `[]` otherwise — **never raise because a driver lacks log support**
(rack_test does not).
Verify: integration test against a tiny static Rack app served by Capybara with
`rack_test`, asserting controls are found and clicking navigates. Console
support is exercised by a stub, not by booting Chrome.

**2.2 `Steering::Jev`**
One POST to `https://classifier.dev` with `labels`, `inputs`, `instructions`.
Must: set a real `User-Agent` (Python-style default UAs are 403'd at the edge —
note applies to any client), cache by page signature, treat confidence below a
threshold (default 0.6) as "use the default weight", and **rescue every network
error into uniform-random fallback**. Timeout 5s.
Verify: stubbed HTTP for the happy path, low-confidence path, and the failure
path (assert it falls back and does not raise). One live test tagged so it is
skipped unless `SLICKROCK_LIVE=1`.

**2.3 `Slickrock::Minitest` mixin**
`slickrock_walk(start, **opts)` building a `Drivers::Capybara` from the
including test's `page`, defaulting the oracle, and printing the seed to stdout
on every run so a failure in CI output is reproducible.
Verify: a test that includes the mixin against `Drivers::Fake` via injection.

## Phase 3 — polish

**3.1 README**
What it is, the 6-line quickstart, the oracle table, steering (and that it needs
no key), reproducing a failure from a seed, and an honest "what this will not
find" section.

**3.2 CI + release prep**
GitHub Actions running `rake test` and `rubocop` on push and PR, Ruby 3.2/3.3/3.4.
`CHANGELOG.md`. MIT `LICENSE`.

## Phase 4 — ride the deploy (in akotacos, after v0.1 tags)

`gem "slickrock", github: "cmbaldwin/slickrock", group: :test`, plus one
`test/system/cart_fuzz_test.rb` that is **not** part of `bin/pre-deploy` — the
browser suite already fails 1 run in 3, and a randomised test must never gate a
deploy.

Beyond running it by hand, it rides the deploy: a deploy already spends 60-250
seconds building, pushing and swapping containers, and a walk fits inside that
for free.

```
pre-build   gate passes → spawn a DETACHED walk → write pid + log + result.json
   ↓                                    (deploy carries on immediately)
build / push / swap                     ← walk runs in parallel
   ↓
post-deploy fetch the result → print it → deploy exits 0 either way
```

**4.1 `bin/slickrock-async`** — `start` spawns a detached walk and returns at
once; `report` collects it. Artefacts under `tmp/slickrock/<git-sha>/`:
`walk.log`, `result.json` (seed, steps, violation, screenshot), `pid`.

**4.2 Hook wiring** — `pre-build` calls `start` *after* the gate passes, so a
failed gate never leaves an orphan. `post-deploy` calls `report`.

**4.3 The report** — prints seed, steps taken, pages visited, and the violation
with its reproduction line. Written to be read by a human *and* pasted to an
agent summarising the deploy, so it must be self-contained: an agent seeing only
that block should be able to act on it.

### Rules this phase must not break

- **It runs against a locally booted test server on the test database. Never
  production.** A random walker in production creates real orders and moves real
  money. The classifier is not a safety boundary — measured on the real cart,
  "Pay with cash at counter" classified as *completes a purchase* at only 0.77
  confidence. Good enough to steer a walk; nowhere near good enough to protect
  production. `bin/slickrock-async` must refuse to target any host that is not
  localhost.
- **It never fails a deploy.** `start` and `report` exit 0 on every internal
  error. A violation is reported loudly and changes no exit code. The deploy's
  correctness gate is `bin/pre-deploy`; this is intelligence, not a gate.
- **No orphans.** `report` kills a walk that outlived the deploy; `start`
  reaps a stale pid from a previous run before spawning.
- **Silent when absent.** If the gem is missing or the walk cannot start, print
  one line and carry on.
