# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Slickrock::Drivers::FakeTest < Minitest::Test
  def pages
    {
      "/cart" => {
        title: "Cart",
        text: "Your cart has 2 items",
        controls: [
          [ "Edit", :link, "/cart/edit" ],
          [ "Pay with Stripe", :button, "/checkout" ],
          [ "Void", :button, "/void", { enabled: false } ]
        ],
        console: [ { level: "error", text: "boom" } ],
        status: 200
      },
      "/checkout" => {
        title: "Checkout",
        text: "Thanks!",
        controls: [],
        console: [],
        status: 200
      }
    }
  end

  def test_visit_and_reads
    driver = Slickrock::Drivers::Fake.new(pages: pages)

    driver.visit("/cart")

    assert_equal "/cart", driver.current_url
    assert_equal "Cart", driver.title
    assert_equal "Your cart has 2 items", driver.text
    assert_equal [ "/cart" ], driver.visited_urls
  end

  def test_click_follows_the_mapped_destination
    driver = Slickrock::Drivers::Fake.new(pages: pages)
    driver.visit("/cart")
    pay = driver.controls.find { |c| c.label == "Pay with Stripe" }

    driver.click(pay)

    assert_equal "/checkout", driver.current_url
    assert_equal "Thanks!", driver.text
    assert_equal [ "/cart", "/checkout" ], driver.visited_urls
  end

  def test_click_on_unmapped_destination_serves_a_404_page
    driver = Slickrock::Drivers::Fake.new(pages: pages)
    driver.visit("/cart")
    edit = driver.controls.find { |c| c.label == "Edit" }

    driver.click(edit)

    assert_equal 404, driver.status
    assert_equal "Not Found", driver.title
  end

  def test_console_messages_drain_since_last_call
    driver = Slickrock::Drivers::Fake.new(pages: pages)

    driver.visit("/cart")

    assert_equal [ { level: "error", text: "boom" } ], driver.console_messages
    assert_equal [], driver.console_messages
  end

  def test_console_messages_accumulate_across_navigation
    driver = Slickrock::Drivers::Fake.new(pages: pages)
    driver.visit("/cart")
    driver.console_messages
    pay = driver.controls.find { |c| c.label == "Pay with Stripe" }

    driver.click(pay)

    assert_equal [], driver.console_messages
  end

  def test_disabled_controls_are_reported_but_refuse_interaction
    driver = Slickrock::Drivers::Fake.new(pages: pages)
    driver.visit("/cart")
    void = driver.controls.find { |c| c.label == "Void" }

    refute_predicate void, :enabled?
    assert_raises(Slickrock::Error) { driver.click(void) }
    assert_raises(Slickrock::Error) { driver.fill(void, "x") }
  end

  def test_screenshot_writes_a_file
    driver = Slickrock::Drivers::Fake.new(pages: pages)
    driver.visit("/cart")
    path = File.join(Dir.mktmpdir, "shot.png")

    driver.screenshot(path)

    assert_path_exists path
  end
end
