# frozen_string_literal: true

module Slickrock
  module Oracles
    # Catches Turbo's silent frame-miss -- incident #2 from SPEC.md, where a
    # frame navigation targets a page with no matching turbo-frame and Turbo
    # just discards the response. Turbo logs this to the console rather than
    # rendering anything, so it is invisible to a text- or status-based check.
    class NoTurboFrameMiss
      DEFAULT_MARKER = "did not contain the expected <turbo-frame"

      def initialize(marker: DEFAULT_MARKER)
        @marker = marker
      end

      def call(snapshot)
        hit = snapshot.console_messages.find { |message| message[:text].to_s.include?(@marker) }
        return nil unless hit

        "turbo-frame miss: #{hit[:text]}"
      end
    end
  end
end
