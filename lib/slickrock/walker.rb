# frozen_string_literal: true

require "tmpdir"

module Slickrock
  # The loop from SPEC.md: snapshot -> check oracles -> choose an action ->
  # perform it -> repeat. Owns seeding, the step budget, oracle evaluation
  # order, avoid-listing, the on_step callback, and screenshot capture on
  # failure. See Slickrock.walk for the public entry point.
  class Walker
    def initialize(driver:, steps: 40, seed: Random.new_seed, oracle: Oracle.defaults,
                    steering: nil, avoid: [], on_step: nil)
      @driver = driver
      @steps = steps
      @seed = seed
      @rng = Random.new(seed)
      @oracles = Array(oracle)
      @steering = steering
      @avoid = avoid
      @on_step = on_step
    end

    def walk(start)
      @driver.visit(start)
      journey = Journey.new
      actions_taken = 0
      acted_last = false

      @steps.times do
        snapshot = take_snapshot
        violation = detect_violation(snapshot)
        return violated(actions_taken, journey, violation) if violation

        control = choose(snapshot)
        acted_last = false
        break unless control # dead end -- no clickable controls left

        perform(control, snapshot, journey)
        actions_taken += 1
        acted_last = true
      end

      # A bug caused by the last click must not be missed: check once more
      # after the final action, not just before it. Skipped on a dead end --
      # nothing happened since the last pre-action check, so there is
      # nothing new to find.
      if acted_last
        violation = detect_violation(take_snapshot)
        return violated(actions_taken, journey, violation) if violation
      end

      build_result(actions_taken, journey, nil)
    end

    private

    def take_snapshot
      Snapshot.new(
        url: @driver.current_url,
        title: @driver.title,
        text: @driver.text,
        controls: @driver.controls,
        console_messages: @driver.console_messages,
      )
    end

    def detect_violation(snapshot)
      @oracles.each do |oracle|
        reason = oracle.call(snapshot)
        return reason if reason
      end
      nil
    end

    def choose(snapshot)
      candidates = snapshot.controls.select(&:enabled?).reject { |control| avoided?(control) }
      return nil if candidates.empty?

      @steering ? weighted_pick(candidates, snapshot) : candidates.sample(random: @rng)
    end

    def avoided?(control)
      @avoid.any? { |pattern| pattern.match?(control.label.to_s) }
    end

    # A weight of 0 means never choose -- filtered out before the draw, not
    # just deprioritized. A control the steering object left out of its
    # answer keeps the uniform default weight of 1.
    def weighted_pick(candidates, snapshot)
      weights = @steering.weights_for(candidates, snapshot) || {}
      pool = candidates.map { |control| [ control, weights.fetch(control, 1).to_f ] }
                        .select { |(_control, weight)| weight.positive? }
      return nil if pool.empty?

      draw = @rng.rand * pool.sum { |(_control, weight)| weight }
      pool.each do |(control, weight)|
        draw -= weight
        return control if draw < 0
      end
      pool.last.first
    end

    # A control that dies between snapshot and click (Turbo re-render,
    # JS replacement) is harness staleness, not an app violation: record the
    # skip and walk on. The step budget still decrements, so a page that
    # churns every control ends the walk instead of looping forever.
    def perform(control, snapshot, journey)
      action = control.kind == :field ? :fill : :click
      action == :fill ? @driver.fill(control, random_value) : @driver.click(control)
    rescue StandardError
      action = :"#{action}_skipped"
    ensure
      journey.record(url: snapshot.url, label: control.label, kind: control.kind, action: action)
      @on_step&.call(journey.to_a.last)
    end

    # Simple short strings/digits from the seeded Random -- richer value
    # generation is explicitly out of scope for v0.1 (SPEC.md).
    def random_value
      chars = ("a".."z").to_a + ("0".."9").to_a
      Array.new(6) { chars[@rng.rand(chars.size)] }.join
    end

    def violated(actions_taken, journey, reason)
      violation = Violation.new(
        reason: reason,
        seed: @seed,
        step_index: actions_taken,
        journey: journey,
        screenshot_path: capture_screenshot,
      )
      build_result(actions_taken, journey, violation)
    end

    def build_result(actions_taken, journey, violation)
      Result.new(
        seed: @seed,
        steps_taken: actions_taken,
        journey: journey,
        violation: violation,
        usage: steering_usage,
      )
    end

    def steering_usage
      return nil unless @steering.respond_to?(:usage)

      usage = @steering.usage
      usage.respond_to?(:dup) ? usage.dup : usage
    end

    # Tolerates a driver that cannot screenshot at all (SPEC's driver
    # interface lists #screenshot, but rack_test-style fakes may not
    # implement it) -- carry on with a nil path rather than losing the
    # violation report over it.
    def capture_screenshot
      path = File.join(Dir.tmpdir, "slickrock-#{@seed}-#{Time.now.to_f}-#{@rng.rand(9999)}.png")
      saved = @driver.screenshot(path)
      return saved if saved
      File.exist?(path) ? path : nil
    rescue StandardError
      nil
    end
  end

  # See docs/SPEC.md "Public API".
  def self.walk(start:, driver:, steps: 40, seed: Random.new_seed, oracle: Oracle.defaults,
                 steering: nil, avoid: [], on_step: nil)
    Walker.new(
      driver: driver,
      steps: steps,
      seed: seed,
      oracle: oracle,
      steering: steering,
      avoid: avoid,
      on_step: on_step,
    ).walk(start)
  end
end
