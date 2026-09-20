# frozen_string_literal: true

module Slickrock
  # The five built-ins from SPEC.md "2. Oracle", each written against a real
  # production failure. `Slickrock.walk` defaults to this list; pass your own
  # array (append app-specific lambdas, drop one, or reconfigure one of these)
  # to replace it.
  module Oracle
    def self.defaults
      [
        Oracles::NoServerError.new,
        Oracles::NoStaleSession.new,
        Oracles::NoTurboFrameMiss.new,
        Oracles::NoJsError.new,
        Oracles::NoBlankPage.new
      ]
    end
  end
end
