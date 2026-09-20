# frozen_string_literal: true

require "test_helper"

class Slickrock::Oracles::NoTurboFrameMissTest < Minitest::Test
  def snapshot(console_messages:)
    Slickrock::Snapshot.new(url: "/cart", title: "Cart", text: "Your cart", controls: [],
                             console_messages: console_messages)
  end

  def test_fires_on_the_turbo_frame_miss_console_message
    oracle = Slickrock::Oracles::NoTurboFrameMiss.new
    page = snapshot(console_messages: [
      { level: "error",
        text: 'Response has no matching <turbo-frame id="cart_item_1"> element, but the response ' \
              "did not contain the expected <turbo-frame> tag" }
    ])

    violation = oracle.call(page)

    assert_match(/turbo-frame miss/, violation)
  end

  def test_is_silent_without_the_marker
    oracle = Slickrock::Oracles::NoTurboFrameMiss.new
    page = snapshot(console_messages: [ { level: "error", text: "unrelated console noise" } ])

    assert_nil oracle.call(page)
  end

  def test_marker_keyword_overrides_the_default_string
    oracle = Slickrock::Oracles::NoTurboFrameMiss.new(marker: "custom frame marker")
    default_marker = snapshot(console_messages: [ { level: "error", text: "did not contain the expected <turbo-frame" } ])
    custom_marker = snapshot(console_messages: [ { level: "error", text: "custom frame marker" } ])

    assert_nil oracle.call(default_marker)
    refute_nil oracle.call(custom_marker)
  end
end
