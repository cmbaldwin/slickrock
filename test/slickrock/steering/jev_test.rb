# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

module Slickrock
  class SteeringJevTest < Minitest::Test
    LABELS = %w[Checkout Cart Logout].freeze

    def controls
      LABELS.map { |label| Control.new(ref: label, label: label, kind: :link, enabled: true) }
    end

    def direct_ok(choice, prob)
      lambda do |_url, _headers, _body|
        [ 200, JSON.generate({ answers: { next: { type: "choice", choice: choice,
                                                 probabilities: { choice => prob } } } }) ]
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
