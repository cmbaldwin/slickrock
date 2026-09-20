# frozen_string_literal: true

require "test_helper"

class Slickrock::OracleTest < Minitest::Test
  def test_defaults_returns_the_five_built_ins_in_callable_order
    oracles = Slickrock::Oracle.defaults

    assert_equal [
      Slickrock::Oracles::NoServerError,
      Slickrock::Oracles::NoStaleSession,
      Slickrock::Oracles::NoTurboFrameMiss,
      Slickrock::Oracles::NoJsError,
      Slickrock::Oracles::NoBlankPage
    ], oracles.map(&:class)

    assert(oracles.all? { |oracle| oracle.respond_to?(:call) })
  end
end
