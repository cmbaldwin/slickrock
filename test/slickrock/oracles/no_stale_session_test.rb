# frozen_string_literal: true

require "test_helper"

class Slickrock::Oracles::NoStaleSessionTest < Minitest::Test
  def snapshot(title:, text:)
    Slickrock::Snapshot.new(url: "/checkout/cash", title: title, text: text, controls: [], console_messages: [])
  end

  def test_fires_on_the_real_422_page_wording
    oracle = Slickrock::Oracles::NoStaleSession.new
    page = snapshot(
      title: "Session Expired",
      text: "Your order got a little stale.\nThe page expired while you were deciding.",
    )

    violation = oracle.call(page)

    assert_match(/stale-session \(422\) page/, violation)
    assert_includes violation, "Session Expired"
  end

  def test_is_silent_on_a_normal_page
    oracle = Slickrock::Oracles::NoStaleSession.new
    page = snapshot(title: "Checkout", text: "Pay with cash at the counter")

    assert_nil oracle.call(page)
  end

  def test_matching_keyword_overrides_the_default_wording
    oracle = Slickrock::Oracles::NoStaleSession.new(matching: [ /Votre session a expire/i ])
    default_wording = snapshot(title: "Session Expired", text: "Your order got a little stale.")
    custom_wording = snapshot(title: "Erreur", text: "Votre session a expire")

    assert_nil oracle.call(default_wording)
    refute_nil oracle.call(custom_wording)
  end
end
