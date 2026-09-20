# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Slickrock
  module Steering
    # Chooses where the walker goes next using Jev, TypeSafe's decision model.
    #
    # Why this exists: uniform-random walking wastes its step budget on
    # chrome (nav, footer, logout). One Jev call per page steers the walk
    # toward the controls that look useful, while the oracles — not the model —
    # decide what counts as broken.
    #
    # Key comes from `TYPESAFE_API_KEY` (or `api_key:`). With no key it uses
    # the keyless classifier.dev endpoint instead, so steering works out of
    # the box. Every network error degrades to uniform weights — steering
    # must never break a walk.
    class Jev
      SYSTEM_ONE_URL = "https://api.typesafe.ai/v1/systemone"
      CLASSIFIER_URL = "https://classifier.dev"
      USER_AGENT = "slickrock/0.1.0 (+https://github.com/cmbaldwin/slickrock)"
      DEFAULT_MODEL = "jev-latest"
      DEFAULT_THRESHOLD = 0.6
      DEFAULT_WEIGHT = 0.25
      TIMEOUT = 5

      # @param api_key [String, nil] TypeSafe key; nil falls back to classifier.dev
      # @param threshold [Float] confidence below this means "use default weight"
      # @param transport [Proc, nil] (url, headers, body) -> [status, body];
      #   the default uses net/http. Inject a fake in tests.
      def initialize(api_key: ENV.fetch("TYPESAFE_API_KEY", nil),
                     model: DEFAULT_MODEL, threshold: DEFAULT_THRESHOLD,
                     transport: nil)
        @api_key = api_key
        @model = model
        @threshold = threshold
        @transport = transport || method(:post)
        @cache = {}
      end

      # Weight per control label for this page. Cached by page_signature.
      #
      # @param controls [Array<Control>] candidates to choose between
      # @param page_signature [String] url + control labels; same page, same answer
      # @param goal [String] what the walk is trying to reach, in plain words
      # @return [Hash{String => Float}] label => weight (uniform on any failure)
      def weights(controls, page_signature:, goal: "find anything broken")
        labels = controls.map(&:label).uniq.first(100)
        return uniform(labels) if labels.empty?

        @cache[page_signature] ||= judge(labels, page_signature, goal)
      end

      # Walker-facing entry point: weights keyed by control object, with the
      # uniform default of 1 for anything left out.
      #
      # @param goal [String] what the walk is trying to reach
      def weights_for(candidates, snapshot, goal: "find anything broken")
        url = snapshot.respond_to?(:url) ? snapshot.url.to_s : snapshot.to_s
        sig = "#{url}|#{candidates.map(&:label).join(",")}"
        by_label = weights(candidates, page_signature: sig, goal: goal)
        candidates.to_h { |control| [ control, by_label.fetch(control.label, 1.0) ] }
      end

      private

      def uniform(labels)
        labels.to_h { |label| [ label, 1.0 ] }
      end

      def defaulted(labels)
        labels.to_h { |label| [ label, DEFAULT_WEIGHT ] }
      end

      def judge(labels, signature, goal)
        state = { page: signature, goal: goal }
        winner, confidence = @api_key ? ask_direct(state, labels) : ask_keyless(state, labels)
        return defaulted(labels) unless winner && labels.include?(winner)
        return defaulted(labels) unless confidence >= @threshold

        out = defaulted(labels)
        out[winner] = 1.0
        out
      rescue StandardError
        uniform(labels)
      end

      def ask_direct(state, labels)
        body = JSON.generate({ model: @model, state: state,
                               questions: { next: {
                                 type: "choice",
                                 instructions: "Which control should the test walk click next to best pursue this goal?",
                                 criteria: labels.to_h { |label| [ label, label ] } } } })
        status, raw = @transport.call(SYSTEM_ONE_URL,
                                      { "authorization" => "Bearer #{@api_key}",
                                        "content-type" => "application/json",
                                        "user-agent" => USER_AGENT }, body)
        raise "Jev HTTP #{status}" unless status.between?(200, 299)

        answer = JSON.parse(raw).fetch("answers").fetch("next")
        choice = answer["choice"]
        conf = answer["probabilities"]&.fetch(choice, 0) || 0
        [ choice, Float(conf) ]
      end

      def ask_keyless(state, labels)
        body = JSON.generate({ inputs: [ "#{state[:goal]} on #{state[:page]}" ],
                               labels: labels,
                               instructions: "Which page control should an automated test walk click next?" })
        status, raw = @transport.call(CLASSIFIER_URL,
                                      { "content-type" => "application/json",
                                        "user-agent" => USER_AGENT }, body)
        raise "classifier HTTP #{status}" unless status.between?(200, 299)

        parsed = JSON.parse(raw)
        res = parsed["results"] ? parsed["results"].first : parsed
        [ res["label"], Float(res["confidence"] || 0) ]
      end

      def post(url, headers, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
        response = http.post(uri.request_uri, body, headers)
        [ response.code.to_i, response.body.to_s ]
      end
    end
  end
end
