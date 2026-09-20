# frozen_string_literal: true

require "test_helper"
require "capybara"
require "rack"

module Slickrock
  class DriversCapybaraTest < Minitest::Test
    APP = Rack::Builder.new do
      map "/" do
        run lambda { |_env|
          [ 200, { "content-type" => "text/html" },
           [ "<html><head><title>Home</title></head><body>" \
            "<h1>Shop</h1>" \
            "<a href=\"/cart\">Cart</a>" \
            "<form action=\"/search\" method=\"get\">" \
            "<input type=\"text\" name=\"q\" placeholder=\"Search\">" \
            "<input type=\"submit\" value=\"Go\"></form>" \
            "<button disabled>Off</button>" \
            "</body></html>" ] ]
        }
      end
      map "/cart" do
        run lambda { |_env|
          [ 200, { "content-type" => "text/html" },
           [ "<html><head><title>Cart</title></head><body>2 items</body></html>" ] ]
        }
      end
    end.to_app

    def session
      Capybara::Session.new(:rack_test, APP)
    end

    def test_finds_labelled_controls_and_skips_disabled
      driver = Drivers::Capybara.new(session)
      driver.visit("/")
      labels = driver.controls.map(&:label)
      assert_includes labels, "Cart"
      assert_includes labels, "Search"
      assert_includes labels, "Go"
      assert_equal "Home", driver.title
    end

    def test_click_navigates
      driver = Drivers::Capybara.new(session)
      driver.visit("/")
      cart = driver.controls.find { |control| control.label == "Cart" }
      driver.click(cart)
      assert_equal "/cart", URI.parse(driver.current_url).path
      assert_match(/2 items/, driver.text)
    end

    def test_console_messages_degrade_to_empty_without_log_support
      driver = Drivers::Capybara.new(session)
      driver.visit("/")
      assert_equal [], driver.console_messages
    end

    def test_console_entries_surface_when_driver_has_logs
      message = Struct.new(:level, :message).new(:severe, "boom")
      logs = Struct.new(:entries) do
        def get(_type) = entries
      end.new([ message ])
      browser = Struct.new(:logs).new(logs)
      sess = Struct.new(:driver).new(Struct.new(:browser).new(browser))
      driver = Drivers::Capybara.new(sess)
      assert_equal [ { level: "severe", text: "boom" } ], driver.console_messages
    end
  end
end
