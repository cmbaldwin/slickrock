# frozen_string_literal: true

module Slickrock
  # What Slickrock.walk returns: either a clean run to its step budget, or the
  # violation that stopped it early.
  Result = Struct.new(:seed, :steps_taken, :journey, :violation, keyword_init: true) do
    def ok?
      violation.nil?
    end
  end
end
