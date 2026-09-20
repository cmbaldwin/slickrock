# frozen_string_literal: true

require "test_helper"

class Slickrock::Oracles::NoJsErrorTest < Minitest::Test
  def snapshot(console_messages:)
    Slickrock::Snapshot.new(url: "/cart", title: "Cart", text: "Your cart", controls: [],
                             console_messages: console_messages)
  end

  def test_fires_on_a_severe_console_message
    oracle = Slickrock::Oracles::NoJsError.new
    page = snapshot(console_messages: [ { level: "severe", text: "Uncaught TypeError: x is not a function" } ])

    violation = oracle.call(page)

    assert_match(/console severe/, violation)
    assert_includes violation, "TypeError"
  end

  def test_is_silent_on_default_ignored_noise
    oracle = Slickrock::Oracles::NoJsError.new
    page = snapshot(console_messages: [
      { level: "error", text: "Failed to load resource: favicon.ico 404" },
      { level: "error", text: "https://js.stripe.com/v3/ blocked by client" },
      { level: "info", text: "just some info" }
    ])

    assert_nil oracle.call(page)
  end

  def test_ignore_keyword_overrides_the_default_list
    oracle = Slickrock::Oracles::NoJsError.new(ignore: [ /my-noisy-widget\.js/ ])
    still_ignored_by_default_but_not_now = snapshot(console_messages: [ { level: "error", text: "favicon.ico 404" } ])
    newly_ignored = snapshot(console_messages: [ { level: "error", text: "loaded my-noisy-widget.js twice" } ])

    refute_nil oracle.call(still_ignored_by_default_but_not_now)
    assert_nil oracle.call(newly_ignored)
  end
end
