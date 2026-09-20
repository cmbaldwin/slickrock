# frozen_string_literal: true

require "test_helper"

class JourneyTest < Minitest::Test
  def test_to_s_with_no_steps
    assert_equal "  (no steps taken)", Slickrock::Journey.new.to_s
  end

  def test_to_s_renders_a_numbered_list
    journey = Slickrock::Journey.new
    journey.record(url: "/cart", label: "Add", kind: :button, action: :click)
    journey.record(url: "/cart", label: "Checkout", kind: :link, action: :click)

    expected = [
      '  1. click button("Add") on /cart',
      '  2. click link("Checkout") on /cart'
    ].join("\n")

    assert_equal expected, journey.to_s
  end

  def test_record_returns_self_for_chaining
    journey = Slickrock::Journey.new

    assert_same journey, journey.record(url: "/cart", label: "Add", kind: :button, action: :click)
  end

  def test_size_and_enumerable
    journey = Slickrock::Journey.new
    journey.record(url: "/cart", label: "Add", kind: :button, action: :click)

    assert_equal 1, journey.size
    assert_equal [ "/cart" ], journey.map(&:url)
  end
end
