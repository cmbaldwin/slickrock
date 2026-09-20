# Changelog

## 0.1.0 (unreleased)

- Value objects: `Control`, `Snapshot`, `Journey`, `Result`, `Violation`
- `Drivers::Fake` scripted page graph (no browser)
- Five oracles: `NoServerError`, `NoStaleSession`, `NoTurboFrameMiss`, `NoJsError`, `NoBlankPage`
- `Walker` loop: seed, budget, `avoid:`, check before each action and after the last
- `Steering::Jev` — optional, degrades to uniform random on any error
- `Drivers::Capybara` — duck-typed session, never raises for missing console/screenshot support
- `Slickrock::Minitest` mixin — prints the seed, turns a violation into a test failure
