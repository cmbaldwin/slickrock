# frozen_string_literal: true

module Slickrock
  module Oracles
    # Catches Rails' generic 500 page. The default wording is Rails' own
    # `public/500.html` ("We're sorry, but something went wrong") plus the
    # classic "Internal Server Error" status text and the marker Rails prints
    # on its own unstyled exception page -- an app with a custom error page
    # should pass its own `matching:` list.
    class NoServerError
      DEFAULT_MATCHING = [
        /We're sorry, but something went wrong/i,
        /Internal Server Error/i,
        /ActionController::RoutingError/
      ].freeze

      def initialize(matching: DEFAULT_MATCHING)
        @matching = matching
      end

      def call(snapshot)
        haystack = "#{snapshot.title}\n#{snapshot.text}"
        return nil unless @matching.any? { |pattern| pattern.match?(haystack) }

        "server error page (title: #{snapshot.title.inspect}) at #{snapshot.url}"
      end
    end
  end
end
