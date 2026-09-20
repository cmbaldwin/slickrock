# frozen_string_literal: true

require "test_helper"

class Slickrock::WalkerTest < Minitest::Test
  # A small branching graph with no poison anywhere -- every page has
  # somewhere to go, so a walk never dead-ends before its budget runs out.
  def clean_pages
    {
      "/a" => { title: "A", text: "Page A has plenty of visible text on it.",
                controls: [ [ "To B", :link, "/b" ], [ "To C", :link, "/c" ] ], console: [] },
      "/b" => { title: "B", text: "Page B has plenty of visible text on it.",
                controls: [ [ "To A", :link, "/a" ], [ "To C", :link, "/c" ] ], console: [] },
      "/c" => { title: "C", text: "Page C has plenty of visible text on it.",
                controls: [ [ "To A", :link, "/a" ], [ "To B", :link, "/b" ] ], console: [] }
    }
  end

  def test_1_clean_graph_walks_its_full_step_budget
    driver = Slickrock::Drivers::Fake.new(pages: clean_pages)

    result = Slickrock.walk(start: "/a", driver: driver, steps: 40, seed: 1)

    assert_predicate result, :ok?
    assert_equal 40, result.steps_taken
    assert_equal 40, result.journey.size
  end

  def test_2_poisoned_page_fails_at_the_right_step_with_the_right_message
    pages = clean_pages.merge(
      "/b" => { title: "Internal Server Error", text: "We're sorry, but something went wrong.",
                controls: [], console: [] },
    )
    driver = Slickrock::Drivers::Fake.new(pages: pages)

    result = Slickrock.walk(start: "/a", driver: driver, steps: 40, seed: 2)

    refute_predicate result, :ok?
    # Poisoned as soon as the walk reaches /b, whichever step that happens to
    # be for this seed -- confirm it against the journey itself rather than
    # hardcoding a step number tied to the RNG sequence. Every "To B" control
    # in this graph leads to /b, regardless of which page it was clicked from.
    landed_on_b_at = result.journey.to_a.index { |step| step.label == "To B" }
    refute_nil landed_on_b_at, "expected this seed to have clicked To B at some point"
    assert_equal landed_on_b_at + 1, result.violation.step_index
    assert_match(/server error page/, result.violation.reason)
    assert_match(/step #{landed_on_b_at + 1}/, result.violation.message)
  end

  def test_3_same_seed_produces_an_identical_journey
    result_a = Slickrock.walk(start: "/a", driver: Slickrock::Drivers::Fake.new(pages: clean_pages), steps: 25, seed: 777)
    result_b = Slickrock.walk(start: "/a", driver: Slickrock::Drivers::Fake.new(pages: clean_pages), steps: 25, seed: 777)

    assert_equal result_a.journey.to_a, result_b.journey.to_a
  end

  def test_4_avoid_labels_are_never_clicked
    pages = clean_pages.merge(
      "/a" => clean_pages["/a"].merge(
        controls: clean_pages["/a"][:controls] + [ [ "Log Out", :link, "/logged-out" ] ],
      ),
    )
    driver = Slickrock::Drivers::Fake.new(pages: pages)

    result = Slickrock.walk(start: "/a", driver: driver, steps: 60, seed: 3, avoid: [ /log ?out/i ])

    assert_predicate result, :ok?
    refute_includes driver.visited_urls, "/logged-out"
    refute(result.journey.any? { |step| step.label == "Log Out" })
  end

  def test_5_dead_end_ends_cleanly_without_raising
    pages = { "/dead" => { title: "Dead end", text: "Nothing more to click here at all.", controls: [], console: [] } }
    driver = Slickrock::Drivers::Fake.new(pages: pages)

    result = Slickrock.walk(start: "/dead", driver: driver, steps: 10, seed: 4)

    assert_predicate result, :ok?
    assert_equal 0, result.steps_taken
  end

  def test_6_oracles_are_checked_after_the_final_action
    # Budget of exactly 1: the pre-action check only ever sees the clean
    # start page. If the walker didn't check once more after the click that
    # lands on /b, this would report ok? even though /b is broken -- so this
    # test only passes if that final check actually runs.
    pages = clean_pages.merge(
      "/a" => { title: "A", text: "Page A has plenty of visible text on it.",
                controls: [ [ "To B", :link, "/b" ] ], console: [] },
      "/b" => { title: "Internal Server Error", text: "We're sorry, but something went wrong.",
                controls: [], console: [] },
    )
    driver = Slickrock::Drivers::Fake.new(pages: pages)

    result = Slickrock.walk(start: "/a", driver: driver, steps: 1, seed: 5)

    refute_predicate result, :ok?
    assert_equal 1, result.steps_taken
    assert_equal 1, result.violation.step_index
    assert_match(/server error page/, result.violation.reason)
  end

  def test_7_steering_weight_of_zero_is_never_chosen
    steering = Object.new
    def steering.weights_for(controls, _snapshot)
      controls.to_h { |control| [ control, control.label == "To B" ? 0 : 1 ] }
    end

    (1..20).each do |seed|
      driver = Slickrock::Drivers::Fake.new(pages: clean_pages)
      result = Slickrock.walk(start: "/a", driver: driver, steps: 15, seed: seed, steering: steering)

      refute(result.journey.any? { |step| step.label == "To B" }, "seed #{seed} clicked a weight-0 control")
    end
  end

  def test_8_stale_control_is_skipped_not_failed
    driver = Slickrock::Drivers::Fake.new(pages: clean_pages)
    def driver.click(_control)
      raise Capybara::Cuprite::ObsoleteNode if defined?(Capybara::Cuprite::ObsoleteNode)

      raise StandardError, "stale test control"
    end

    result = Slickrock.walk(start: "/a", driver: driver, steps: 5, seed: 9)

    assert_predicate result, :ok?
    assert_equal 5, result.steps_taken
    assert(result.journey.all? { |step| step.action == :click_skipped })
  end
end
