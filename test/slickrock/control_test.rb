# frozen_string_literal: true

require "test_helper"

class ControlTest < Minitest::Test
  def test_enabled_predicate
    on = Slickrock::Control.new(ref: "/x", label: "Pay", kind: :button, enabled: true, meta: {})
    off = Slickrock::Control.new(ref: "/x", label: "Pay", kind: :button, enabled: false, meta: {})

    assert_predicate on, :enabled?
    refute_predicate off, :enabled?
  end

  def test_to_s_is_readable_and_never_shows_the_raw_ref
    control = Slickrock::Control.new(
      ref: :some_capybara_node_object,
      label: "Pay with Stripe",
      kind: :button,
      enabled: true,
      meta: {},
    )

    assert_equal 'button("Pay with Stripe")', control.to_s
    refute_includes control.to_s, "some_capybara_node_object"
  end

  def test_to_s_flags_disabled_controls
    control = Slickrock::Control.new(ref: "/x", label: "Void", kind: :button, enabled: false, meta: {})

    assert_equal 'button("Void") [disabled]', control.to_s
  end
end
