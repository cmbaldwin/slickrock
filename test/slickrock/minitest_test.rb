# frozen_string_literal: true

require "test_helper"

# Compact `Slickrock::MinitestTest` keeps this file's lexical scope at
# top-level, so `Minitest` here is the gem. Inside `module Slickrock` it
# would resolve to the mixin — see test/slickrock/steering/jev_test.rb.
class Slickrock::MinitestTest < ::Minitest::Test
  include Slickrock::Minitest

  def clean_pages
    {
      "/a" => { title: "A", text: "Page A has plenty of visible text on it.",
                controls: [ [ "To A", :link, "/a" ] ], console: [] }
    }
  end

  def poisoned_pages
    {
      "/a" => { title: "Internal Server Error", text: "We're sorry, but something went wrong.",
                controls: [], console: [] }
    }
  end

  def test_an_ok_walk_returns_the_result
    driver = Slickrock::Drivers::Fake.new(pages: clean_pages)

    result = slickrock_walk("/a", driver: driver, steps: 5, seed: 1)

    assert_predicate result, :ok?
    assert_equal 5, result.steps_taken
  end

  def test_a_violation_fails_the_test_with_the_violations_message_verbatim
    driver = Slickrock::Drivers::Fake.new(pages: poisoned_pages)

    error = assert_raises(::Minitest::Assertion) do
      slickrock_walk("/a", driver: driver, steps: 5, seed: 1)
    end

    # Slickrock.walk deliberately RETURNS a Result rather than raising -- this
    # proves the mixin is the thing turning it into a Minitest failure, and
    # that the failure carries the Violation's own reproduction report
    # (seed first) verbatim rather than a generic assertion message.
    assert_match(/\ASlickrock violation — seed: 1, step 0/, error.message)
    assert_match(/server error page/, error.message)
    assert_match(/Reproduce with:/, error.message)
    assert_match(/Journey:/, error.message)
  end

  def test_prints_the_seed_on_a_passing_run
    driver = Slickrock::Drivers::Fake.new(pages: clean_pages)

    out, = capture_io { slickrock_walk("/a", driver: driver, steps: 1, seed: 42) }

    assert_match(/Slickrock seed: 42/, out)
  end

  def test_prints_the_seed_on_a_failing_run
    driver = Slickrock::Drivers::Fake.new(pages: poisoned_pages)

    out, = capture_io do
      assert_raises(::Minitest::Assertion) { slickrock_walk("/a", driver: driver, steps: 1, seed: 99) }
    end

    assert_match(/Slickrock seed: 99/, out)
  end
end
