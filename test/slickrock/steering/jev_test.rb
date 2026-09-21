# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

module Slickrock
  # ::Minitest::Test, not Minitest::Test -- inside `module Slickrock`, a bare
  # `Minitest` constant now resolves to Slickrock::Minitest (the 2.3 mixin)
  # before it reaches the top-level minitest gem.
  class SteeringJevTest < ::Minitest::Test
    LABELS = %w[Checkout Cart Logout].freeze

    def controls
      LABELS.map { |label| Control.new(ref: label, label: label, kind: :link, enabled: true) }
    end

    def direct_ok(choice, prob, enough: 0.95)
      lambda do |_url, _headers, _body|
        [ 200, JSON.generate({ answers: {
          enough: { type: "noul", noul: enough },
          next: { type: "choice", choice: choice, probabilities: { choice => prob } }
        } }) ]
      end
    end

    def test_direct_winner_gets_full_weight
      steering = Steering::Jev.new(api_key: "test-key", transport: direct_ok("Checkout", 0.9))
      weights = steering.weights(controls, page_signature: "/cart|Checkout,Cart,Logout")
      assert_equal 1.0, weights["Checkout"]
      assert_equal 0.25, weights["Cart"]
    end

    def test_low_confidence_falls_back_to_default_weights
      steering = Steering::Jev.new(api_key: "test-key", transport: direct_ok("Checkout", 0.4))
      weights = steering.weights(controls, page_signature: "/cart")
      assert_equal({ "Checkout" => 0.25, "Cart" => 0.25, "Logout" => 0.25 }, weights)
    end

    def test_not_enough_context_falls_back_even_when_choice_is_confident
      steering = Steering::Jev.new(api_key: "test-key",
                                   transport: direct_ok("Checkout", 0.99, enough: 0.2))
      weights = steering.weights(controls, page_signature: "/cart")
      assert_equal({ "Checkout" => 0.25, "Cart" => 0.25, "Logout" => 0.25 }, weights)
    end

    def test_direct_request_asks_enough_noul_before_choice
      seen = {}
      fake = lambda do |_url, _headers, body|
        seen[:body] = JSON.parse(body)
        [ 200, JSON.generate({ answers: {
          enough: { type: "noul", noul: 0.9 },
          next: { type: "choice", choice: "Cart", probabilities: { "Cart" => 0.9 } }
        } }) ]
      end
      Steering::Jev.new(api_key: "test-key", transport: fake)
                   .weights(controls, page_signature: "/cart")
      questions = seen[:body]["questions"]
      assert_equal "noul", questions["enough"]["type"]
      assert_equal "choice", questions["next"]["type"]
      assert_equal %w[controls goal page], seen[:body]["state"].keys.sort
    end

    def test_network_failure_falls_back_to_uniform_without_raising
      boom = lambda { |*_args| raise Errno::ECONNREFUSED }
      steering = Steering::Jev.new(api_key: "test-key", transport: boom)
      weights = steering.weights(controls, page_signature: "/cart")
      assert_equal({ "Checkout" => 1.0, "Cart" => 1.0, "Logout" => 1.0 }, weights)
    end

    def test_malformed_response_falls_back_to_uniform
      bad = lambda { |*_args| [ 200, "not json" ] }
      steering = Steering::Jev.new(api_key: "test-key", transport: bad)
      assert_equal 1.0, steering.weights(controls, page_signature: "/cart")["Cart"]
    end

    def test_keyless_path_uses_classifier_shape
      seen = {}
      fake = lambda do |url, _headers, body|
        seen[:url] = url
        seen[:body] = JSON.parse(body)
        [ 200, JSON.generate({ label: "Cart", confidence: 0.8, scores: {} }) ]
      end
      steering = Steering::Jev.new(api_key: nil, transport: fake)
      weights = steering.weights(controls, page_signature: "/cart")
      assert_equal "https://classifier.dev", seen[:url]
      assert_equal 1.0, weights["Cart"]
    end

    def test_records_usage_from_the_api_response
      fake = lambda do |*_args|
        [ 200, JSON.generate({
          answers: { next: { type: "choice", choice: "Cart",
                             probabilities: { "Cart" => 0.9 } } },
          usage: { input_tokens: 400, output_tokens: 20 }
        }) ]
      end
      steering = Steering::Jev.new(api_key: "test-key", transport: fake)
      steering.weights(controls, page_signature: "/cart")

      assert_equal 1, steering.usage[:calls]
      assert_equal 400, steering.usage[:input_tokens]
      assert_equal 20, steering.usage[:output_tokens]
      assert_operator steering.usage[:request_bytes], :>, 0
    end

    def test_cached_page_does_not_count_as_another_call_in_usage
      calls = 0
      fake = lambda do |*_args|
        calls += 1
        [ 200, JSON.generate({
          answers: { next: { type: "choice", choice: "Cart",
                             probabilities: { "Cart" => 0.9 } } },
          usage: { input_tokens: 100, output_tokens: 5 }
        }) ]
      end
      steering = Steering::Jev.new(api_key: "test-key", transport: fake)
      2.times { steering.weights(controls, page_signature: "/same") }

      assert_equal 1, calls
      assert_equal 1, steering.usage[:calls]
      assert_equal 100, steering.usage[:input_tokens]
    end

    def test_keyless_path_counts_the_call_even_without_a_usage_field
      fake = lambda do |*_args|
        [ 200, JSON.generate({ label: "Cart", confidence: 0.8 }) ]
      end
      steering = Steering::Jev.new(api_key: nil, transport: fake)
      steering.weights(controls, page_signature: "/cart")

      assert_equal 1, steering.usage[:calls]
      assert_equal 0, steering.usage[:input_tokens]
    end

    def test_results_cached_by_page_signature
      calls = 0
      counting = lambda do |*_args|
        calls += 1
        [ 200, JSON.generate({ answers: { next: { type: "choice", choice: "Cart",
                                                 probabilities: { "Cart" => 0.9 } } } }) ]
      end
      steering = Steering::Jev.new(api_key: "test-key", transport: counting)
      2.times { steering.weights(controls, page_signature: "/same") }
      assert_equal 1, calls
    end

    def test_weights_for_keys_by_control_for_the_walker
      steering = Steering::Jev.new(api_key: "test-key", transport: direct_ok("Cart", 0.9))
      snapshot = Snapshot.new(url: "/cart", title: "Cart", text: "2 items",
                              controls: controls, console_messages: [])
      weights = steering.weights_for(controls, snapshot)
      assert_equal 0.25, weights[controls.first]
      assert_equal 1.0, weights[controls[1]]
    end

    def test_live_direct_call
      skip "set SLICKROCK_LIVE=1 to hit the real API" unless ENV["SLICKROCK_LIVE"] == "1" && ENV["TYPESAFE_API_KEY"]
      steering = Steering::Jev.new
      weights = steering.weights(controls, page_signature: "live smoke page")
      assert_equal %w[Cart Checkout Logout].sort, weights.keys.sort
    end

    # Someone who ran `jev auth set` expects the gem to work without also
    # exporting TYPESAFE_API_KEY. The silent alternative is using the keyless
    # endpoint while believing the official one is in play.
    def test_discover_key_prefers_the_env_var
      with_env("TYPESAFE_API_KEY", "from-env") do
        assert_equal "from-env", Slickrock::Steering::Jev.discover_key
      end
    end
    def test_discover_key_falls_back_to_the_cli_credential_store
      with_env("TYPESAFE_API_KEY", nil) do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "credentials.json")
          File.write(path, JSON.generate({ providers: { official: "from-store" } }))
          with_credentials_path(path) do
            assert_equal "from-store", Slickrock::Steering::Jev.discover_key
          end
        end
      end
    end
    def test_a_malformed_credential_store_means_no_key_not_a_crash
      with_env("TYPESAFE_API_KEY", nil) do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "credentials.json")
          File.write(path, "{ this is not json")
          with_credentials_path(path) do
            assert_nil Slickrock::Steering::Jev.discover_key
          end
        end
      end
    end
    def test_a_missing_credential_store_means_no_key
      with_env("TYPESAFE_API_KEY", nil) do
        with_credentials_path("/nope/does/not/exist.json") do
          assert_nil Slickrock::Steering::Jev.discover_key
        end
      end
    end
    private
    def with_credentials_path(path)
      klass = Slickrock::Steering::Jev
      previous = klass::CLI_CREDENTIALS
      klass.send(:remove_const, :CLI_CREDENTIALS)
      klass.const_set(:CLI_CREDENTIALS, path)
      yield
    ensure
      klass.send(:remove_const, :CLI_CREDENTIALS)
      klass.const_set(:CLI_CREDENTIALS, previous)
    end
    def with_env(name, value)
      had = ENV.key?(name)
      previous = ENV[name]
      value.nil? ? ENV.delete(name) : ENV[name] = value
      yield
    ensure
      had ? ENV[name] = previous : ENV.delete(name)
    end
  end
end
