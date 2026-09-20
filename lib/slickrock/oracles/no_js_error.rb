# frozen_string_literal: true

module Slickrock
  module Oracles
    # Catches uncaught JS exceptions and other severe console noise. The
    # default ignore list is app-specific tuning, not a universal truth: it
    # skips a missing favicon and the third-party payment-wallet scripts
    # (Google Pay, Stripe.js) that log their own console noise unrelated to
    # the app under test. Pass `ignore:` to replace it entirely.
    class NoJsError
      DEFAULT_LEVELS = %w[severe error].freeze
      DEFAULT_IGNORE = [
        /favicon\.ico/,
        %r{pay\.google\.com},
        %r{js\.stripe\.com}
      ].freeze

      def initialize(levels: DEFAULT_LEVELS, ignore: DEFAULT_IGNORE)
        @levels = levels.map { |level| level.to_s.downcase }
        @ignore = ignore
      end

      def call(snapshot)
        hit = snapshot.console_messages.find { |message| relevant?(message) }
        return nil unless hit

        "console #{hit[:level]}: #{hit[:text]}"
      end

      private

      def relevant?(message)
        return false unless @levels.include?(message[:level].to_s.downcase)

        @ignore.none? { |pattern| pattern.match?(message[:text].to_s) }
      end
    end
  end
end
