# frozen_string_literal: true

module Slickrock
  # Base class for everything this gem raises.
  class Error < StandardError; end

  # Raised by the walker when an oracle finds a violation mid-walk.
  #
  # #message is a full reproduction report, not just the oracle's one-line
  # complaint: someone reading a CI log should be able to replay the walk
  # without asking anyone, so the seed comes first and the whole journey is
  # printed. Replay is only as deterministic as the app's starting state --
  # that caveat is stated here rather than implied.
  class Violation < Error
    attr_reader :reason, :seed, :step_index, :journey, :screenshot_path

    def initialize(reason:, seed:, step_index:, journey:, screenshot_path: nil)
      @reason = reason
      @seed = seed
      @step_index = step_index
      @journey = journey
      @screenshot_path = screenshot_path
      super(build_message)
    end

    private

    def build_message
      lines = [
        "Slickrock violation — seed: #{seed.inspect}, step #{step_index}",
        "  #{reason}",
        "",
        "Reproduce with:",
        "  Slickrock.walk(..., seed: #{seed.inspect})",
        "",
        "Journey:",
        journey.to_s
      ]
      lines += [ "", "Screenshot: #{screenshot_path}" ] if screenshot_path
      lines += [ "", "Note: replay is only as deterministic as the app's starting state." ]
      lines.join("\n")
    end
  end
end
