# frozen_string_literal: true

require "test_helper"

class ViolationTest < Minitest::Test
  def test_message_puts_the_seed_first_and_is_a_full_reproduction_report
    journey = Slickrock::Journey.new
    journey.record(url: "/cart", label: "Add", kind: :button, action: :click)
    journey.record(url: "/checkout/cash", label: "Pay at counter", kind: :button, action: :click)

    violation = Slickrock::Violation.new(
      reason: 'HTTP 422 page after clicking "Pay at counter"',
      seed: 42,
      step_index: 2,
      journey: journey,
      screenshot_path: "/tmp/slickrock/42-2.png",
    )

    message = violation.message

    assert_match(/\ASlickrock violation.*seed: 42/, message.lines.first)
    assert_includes message, "step 2"
    assert_includes message, journey.to_s
    assert_includes message, "/tmp/slickrock/42-2.png"
    assert_includes message, 'HTTP 422 page after clicking "Pay at counter"'
    assert_includes message, "seed: 42"
  end

  def test_message_works_without_a_screenshot
    violation = Slickrock::Violation.new(
      reason: "blank page",
      seed: 7,
      step_index: 0,
      journey: Slickrock::Journey.new,
    )

    refute_includes violation.message, "Screenshot:"
  end

  def test_exposes_reproduction_fields
    journey = Slickrock::Journey.new
    violation = Slickrock::Violation.new(reason: "boom", seed: 99, step_index: 3, journey: journey)

    assert_equal "boom", violation.reason
    assert_equal 99, violation.seed
    assert_equal 3, violation.step_index
    assert_same journey, violation.journey
    assert_nil violation.screenshot_path
  end

  def test_is_a_slickrock_error
    violation = Slickrock::Violation.new(reason: "boom", seed: 1, step_index: 0, journey: Slickrock::Journey.new)

    assert_kind_of Slickrock::Error, violation
  end
end
