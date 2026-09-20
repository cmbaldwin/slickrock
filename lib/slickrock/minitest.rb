# frozen_string_literal: true

require_relative "drivers/capybara"

module Slickrock
  # Named to match SPEC.md. The cost is that inside `module Slickrock` a
  # bare `Minitest` constant resolves here rather than to the gem — gem
  # tests that nest under this module use `::Minitest::Test`.
  #
  # Mixin for Minitest/Rails system tests, so the common case from SPEC.md
  # "Public API" is one line:
  #
  #   class CartFuzzTest < ApplicationSystemTestCase
  #     include Slickrock::Minitest
  #
  #     test "the cart survives a random walk" do
  #       slickrock_walk cart_path, steps: 40
  #     end
  #   end
  #
  # Slickrock.walk deliberately returns a Result rather than raising (see
  # docs/SPEC.md "4. Journey") so the deploy runner (Phase 4) can treat a
  # violation as data. A Minitest test that silently returns on a violation
  # is a test that can never fail, so turning a non-ok Result into a failure
  # is this mixin's job alone.
  module Minitest
    # @param start [String] path or url, forwarded to Slickrock.walk
    # @param oracle [Array] defaults to the five built-ins
    # @param seed [Integer] printed before the walk runs (pass or fail) so a
    #   CI log always shows how to replay it
    # @param driver [#visit,...] override for the gem's own tests, so they can
    #   inject a Drivers::Fake instead of wrapping a real Capybara `page`
    # @return [Slickrock::Result] the completed, ok Result -- on a violation
    #   this raises instead and never returns
    def slickrock_walk(start, oracle: Oracle.defaults, seed: Random.new_seed, driver: nil, **opts)
      puts "Slickrock seed: #{seed.inspect}"

      driver ||= Drivers::Capybara.new(page)
      result = Slickrock.walk(start: start, driver: driver, oracle: oracle, seed: seed, **opts)

      # Violation#message is already a complete reproduction report (seed
      # first) -- pass it through verbatim rather than wrapping it.
      assert(result.ok?, result.violation&.message)
      result
    end
  end
end
