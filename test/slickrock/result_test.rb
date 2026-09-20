# frozen_string_literal: true

require "test_helper"

class ResultTest < Minitest::Test
  def test_ok_when_no_violation
    result = Slickrock::Result.new(seed: 1, steps_taken: 5, journey: Slickrock::Journey.new, violation: nil)

    assert_predicate result, :ok?
  end

  def test_not_ok_when_violation_present
    violation = Slickrock::Violation.new(reason: "boom", seed: 1, step_index: 2, journey: Slickrock::Journey.new)
    result = Slickrock::Result.new(seed: 1, steps_taken: 2, journey: Slickrock::Journey.new, violation: violation)

    refute_predicate result, :ok?
  end
end
