# frozen_string_literal: true

module Slickrock
  module Oracles
    # Catches navigating somewhere with no content -- a frame that rendered
    # empty, a redirect to nowhere. `min_chars` is a heuristic, not a parser:
    # retune it for pages that are legitimately terse.
    class NoBlankPage
      DEFAULT_MIN_CHARS = 20

      def initialize(min_chars: DEFAULT_MIN_CHARS)
        @min_chars = min_chars
      end

      def call(snapshot)
        length = snapshot.text.to_s.strip.length
        return nil if length >= @min_chars

        "blank page: only #{length} character#{'s' unless length == 1} of visible text at #{snapshot.url}"
      end
    end
  end
end
