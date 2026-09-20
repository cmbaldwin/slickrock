# frozen_string_literal: true

require "test_helper"

class Slickrock::Oracles::NoBlankPageTest < Minitest::Test
  def snapshot(text:)
    Slickrock::Snapshot.new(url: "/cart", title: "Cart", text: text, controls: [], console_messages: [])
  end

  def test_fires_on_a_page_shorter_than_the_minimum
    oracle = Slickrock::Oracles::NoBlankPage.new
    page = snapshot(text: "  ")

    violation = oracle.call(page)

    assert_match(/blank page/, violation)
    assert_includes violation, "/cart"
  end

  def test_is_silent_on_a_page_with_enough_text
    oracle = Slickrock::Oracles::NoBlankPage.new
    page = snapshot(text: "This page has plenty of visible text on it.")

    assert_nil oracle.call(page)
  end

  def test_min_chars_keyword_overrides_the_default
    oracle = Slickrock::Oracles::NoBlankPage.new(min_chars: 3)
    page = snapshot(text: "hi!")

    assert_nil oracle.call(page)
  end
end
