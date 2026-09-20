# frozen_string_literal: true

module Slickrock
  module Oracles
    # Catches Rails' 422 unprocessable_entity page -- the CSRF-token-mismatch
    # bug from SPEC.md's incident #1. The default wording is copied verbatim
    # from the target app's real 422 page (title "Session Expired", heading
    # "Your order got a little stale.", body "The page expired while you were
    # deciding."). Every other app's 422 page says something else entirely --
    # pass `matching:` to retune.
    #
    # Snapshot deliberately carries no HTTP status (Selenium cannot expose
    # one), so this only ever matches page text -- never key on status.
    class NoStaleSession
      DEFAULT_MATCHING = [
        /Session Expired/,
        /Your order got a little stale\./,
        /The page expired while you were deciding\./
      ].freeze

      def initialize(matching: DEFAULT_MATCHING)
        @matching = matching
      end

      def call(snapshot)
        haystack = "#{snapshot.title}\n#{snapshot.text}"
        return nil unless @matching.any? { |pattern| pattern.match?(haystack) }

        "stale-session (422) page (title: #{snapshot.title.inspect}) at #{snapshot.url}"
      end
    end
  end
end
