# frozen_string_literal: true

require "test_helper"

class Slickrock::Oracles::NoServerErrorTest < Minitest::Test
  def snapshot(title:, text:)
    Slickrock::Snapshot.new(url: "/checkout", title: title, text: text, controls: [], console_messages: [])
  end

  def test_fires_on_rails_default_500_page
    oracle = Slickrock::Oracles::NoServerError.new
    page = snapshot(title: "We're sorry, but something went wrong.", text: "We're sorry, but something went wrong.")

    violation = oracle.call(page)

    assert_match(/server error page/, violation)
    assert_includes violation, "/checkout"
  end

  def test_is_silent_on_a_normal_page
    oracle = Slickrock::Oracles::NoServerError.new
    page = snapshot(title: "Cart", text: "Your cart has 2 items")

    assert_nil oracle.call(page)
  end

  def test_matching_keyword_overrides_the_default_wording
    oracle = Slickrock::Oracles::NoServerError.new(matching: [ /custom kaboom/i ])
    default_wording = snapshot(title: "We're sorry, but something went wrong.", text: "500")
    custom_wording = snapshot(title: "Oops", text: "custom kaboom happened")

    assert_nil oracle.call(default_wording)
    refute_nil oracle.call(custom_wording)
  end
end
