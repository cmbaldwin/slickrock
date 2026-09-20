# frozen_string_literal: true

require "test_helper"
require "capybara"
require "tmpdir"
require "uri"

# A tiny static Rack app so this test never boots a browser -- Capybara's
# rack_test driver is enough to exercise control-collection, labelling and
# navigation exactly as SPEC.md's "Testing the tester" asks for.
#
# Compact `Slickrock::Drivers::CapybaraTest` keeps lexical scope at
# top-level, so `Minitest` here is the gem, not the mixin.
class Slickrock::Drivers::CapybaraTest < ::Minitest::Test
  HOME = <<~HTML
    <html><head><title>Home</title></head><body>
      <h1>Home</h1>
      <a href="/next">Continue</a>
      <button aria-label="Aria Button"></button>
      <button type="submit" value="Submit Value"></button>
      <button disabled>Do not click</button>
      <button></button>
      <input type="text" name="q" placeholder="search">
      <input type="text" name="onlyname">
      <input type="checkbox" name="agree" value="I agree">
      <input type="radio" name="choice" value="a">
      <input type="hidden" name="secret" value="x">
      <select name="color"><option>Red</option><option>Blue</option></select>
    </body></html>
  HTML

  NEXT_PAGE = "<html><head><title>Next</title></head><body><h1>Next page</h1></body></html>"

  APP = lambda do |env|
    case env["PATH_INFO"]
    when "/" then [ 200, { "content-type" => "text/html" }, [ HOME ] ]
    when "/next" then [ 200, { "content-type" => "text/html" }, [ NEXT_PAGE ] ]
    else [ 404, { "content-type" => "text/html" }, [ "not found" ] ]
    end
  end

  def build_session
    ::Capybara::Session.new(:rack_test, APP)
  end

  def build_driver
    Slickrock::Drivers::Capybara.new(build_session)
  end

  def test_controls_are_found_filtered_to_visible_and_enabled
    driver = build_driver
    driver.visit("/")

    labels = driver.controls.map(&:label)

    assert_includes labels, "Continue"
    assert_includes labels, "Aria Button"
    refute_includes labels, "Do not click", "the disabled button must not be collected at all"
    assert(driver.controls.all?(&:enabled?), "everything controls returns is already enabled")
    assert_equal "Home", driver.title
  end

  def test_label_resolution_order
    driver = build_driver
    driver.visit("/")
    by_label = {}
    driver.controls.each { |c| by_label[c.label] = c }

    assert_equal :link, by_label.fetch("Continue").kind
    assert_equal :button, by_label.fetch("Aria Button").kind, "falls back to aria-label when there is no visible text"
    assert_equal :button, by_label.fetch("Submit Value").kind, "falls back to value when there is no text or aria-label"
    assert_equal :field, by_label.fetch("search").kind, "placeholder wins over name"
    assert_equal :field, by_label.fetch("onlyname").kind, "name is the last resort"
    assert_equal :checkbox, by_label.fetch("I agree").kind, "value wins over name for the checkbox too"
    assert_equal :radio, by_label.fetch("a").kind, "value wins over name for the radio"
    refute_includes by_label.keys, "secret", "input[type=hidden] must never be collected"
  end

  def test_a_control_with_no_usable_attribute_falls_back_to_a_short_description
    driver = build_driver
    driver.visit("/")

    fallback = driver.controls.find { |c| c.kind == :button && c.label.start_with?("button#") }

    refute_nil fallback, "expected the attribute-less <button></button> to get a non-blank fallback label"
    assert_equal "button#?", fallback.label
  end

  def test_select_is_collected_with_the_select_kind
    driver = build_driver
    driver.visit("/")

    assert(driver.controls.any? { |c| c.kind == :select })
  end

  def test_fill_sets_the_field_value
    driver = build_driver
    driver.visit("/")
    field = driver.controls.find { |c| c.label == "search" }

    driver.fill(field, "tacos")

    assert_equal "tacos", field.ref.value
  end

  def test_clicking_a_link_navigates
    driver = build_driver
    driver.visit("/")
    link = driver.controls.find { |c| c.kind == :link }

    driver.click(link)

    assert_equal "/next", URI.parse(driver.current_url).path
    assert_includes driver.text, "Next page"
  end

  def test_console_messages_returns_empty_array_when_the_driver_has_no_log_support
    driver = build_driver
    driver.visit("/") # rack_test's browser has no #logs -- the common case, not an edge case

    assert_equal [], driver.console_messages
  end

  def test_screenshot_returns_nil_when_unsupported_instead_of_raising
    driver = build_driver
    driver.visit("/")

    assert_nil driver.screenshot(File.join(Dir.mktmpdir, "shot.png"))
  end

  # --- console_messages, positive path, stubbed (SPEC.md: "exercised by a
  # STUB, not by booting Chrome") ---

  LogEntry = Struct.new(:level, :message)

  class StubBrowserWithLogs
    def initialize(entries)
      @entries = entries
    end

    def logs
      self
    end

    def get(_kind)
      @entries
    end
  end

  class StubDriverWithLogs
    attr_reader :browser

    def initialize(entries)
      @browser = StubBrowserWithLogs.new(entries)
    end
  end

  class StubSessionWithLogs
    attr_reader :driver

    def initialize(entries)
      @driver = StubDriverWithLogs.new(entries)
    end
  end

  def test_console_messages_maps_entries_when_the_driver_supports_logs
    entries = [ LogEntry.new(:severe, "boom"), LogEntry.new(:info, "ok") ]
    driver = Slickrock::Drivers::Capybara.new(StubSessionWithLogs.new(entries))

    assert_equal(
      [ { level: "severe", text: "boom" }, { level: "info", text: "ok" } ],
      driver.console_messages,
    )
  end
end
