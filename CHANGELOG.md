# Changelog

## 0.1.0 (unreleased)

- Value objects: `Control`, `Snapshot`, `Journey`, `Result`, `Violation`
- `Drivers::Fake` scripted page graph (no browser)
- Five oracles: `NoServerError`, `NoStaleSession`, `NoTurboFrameMiss`, `NoJsError`, `NoBlankPage`
- `Walker` loop: seed, budget, `avoid:`, check before each action and after the last
- `Steering::Jev` — optional, degrades to uniform random on any error; `#usage` records calls and TypeSafe input/output tokens
- Keyed Jev path asks a Noul (`enough` context?) alongside the Choice; the Choice is consumed only when `enough` clears the threshold. State names `goal`, `page`, and `controls`.
- `Result#usage` copies that tally off the steering object so a deploy report can serialise it
- `Drivers::Capybara` — duck-typed session, never raises for missing console/screenshot support
- `Slickrock::Minitest` mixin — prints the seed, turns a violation into a test failure
