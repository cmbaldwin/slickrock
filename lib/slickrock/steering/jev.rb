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
    # Key discovery, in order: `api_key:`, then `TYPESAFE_API_KEY`, then the
    # `jev` CLI's own credential store. With no key at all it uses the keyless
    # classifier.dev endpoint, so steering works out of the box.
    #
    # Every network error degrades to uniform weights — steering must never
    # break a walk. A test that fails because a model was unreachable is worse
    # than no test.
    #
    # NOTE: this biases the walk, it does not police it. The winner gets 1.0
    # and everything else DEFAULT_WEIGHT, so on a page of N controls any single
    # non-winner still has roughly `DEFAULT_WEIGHT / (1 + DEFAULT_WEIGHT*(N-1))`
    # chance per step — over a long walk that is close to certain. If a control
    # must never be clicked (checkout, log out, delete), put it in the walker's
    # `avoid:` regexp list. That is deterministic and needs no network.
    class Jev
      SYSTEM_ONE_URL = "https://api.typesafe.ai/v1/systemone"
      CLASSIFIER_URL = "https://classifier.dev"
      USER_AGENT = "slickrock/0.1.0 (+https://github.com/cmbaldwin/slickrock)"
      DEFAULT_MODEL = "jev-latest"
      DEFAULT_THRESHOLD = 0.6
      DEFAULT_WEIGHT = 0.25
      TIMEOUT = 5

      # Where the `jev` CLI keeps its key. Read as a FALLBACK after the env var,
      # because someone who ran `jev auth set` reasonably expects the gem to
      # work without also exporting TYPESAFE_API_KEY — and the silent
      # alternative is falling back to the keyless endpoint while believing the
      # official one is in use.
      CLI_CREDENTIALS = File.join(Dir.home, ".config", "jev-cli", "credentials.json")

      # Env var first, then the CLI's credential store, then nil (keyless).
      # Any read error means "no key", never a raise: a missing or malformed
      # credentials file must not stop a walk.
      def self.discover_key
        ENV.fetch("TYPESAFE_API_KEY", nil) || stored_key
      end

      def self.stored_key
        return nil unless File.readable?(CLI_CREDENTIALS)

        JSON.parse(File.read(CLI_CREDENTIALS)).dig("providers", "official")
      rescue StandardError
        nil
      end

      # @param api_key [String, nil] TypeSafe key; nil falls back to classifier.dev
      # @param threshold [Float] confidence below this means "use default weight"
      # @param transport [Proc, nil] (url, headers, body) -> [status, body];
      #   the default uses net/http. Inject a fake in tests.
      def initialize(api_key: Jev.discover_key,
                     model: DEFAULT_MODEL, threshold: DEFAULT_THRESHOLD,
                     transport: nil, goal: "find anything broken")
        @api_key = api_key
        @model = model
        @threshold = threshold
        @transport = transport || method(:post)
        @goal = goal
        @cache = {}
        # Real POSTs, not walker steps. Cached pages do not increment this.
        @usage = { calls: 0, input_tokens: 0, output_tokens: 0, request_bytes: 0 }
      end

      attr_reader :usage

      # Weight per control label for this page. Cached by page_signature.
      #
      # @param controls [Array<Control>] candidates to choose between
      # @param page_signature [String] url + control labels; same page, same answer
      # @param goal [String] what the walk is trying to reach, in plain words
      # @return [Hash{String => Float}] label => weight (uniform on any failure)
      def weights(controls, page_signature:, goal: @goal)
        labels = controls.map(&:label).uniq.first(100)
        return uniform(labels) if labels.empty?

        @cache[page_signature] ||= judge(labels, page_signature, goal)
      end

      # Walker-facing entry point: weights keyed by control object, with the
      # uniform default of 1 for anything left out.
      #
      # @param goal [String] what the walk is trying to reach
      def weights_for(candidates, snapshot, goal: @goal)
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
        state = { goal: goal, page: signature, controls: labels }
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
        body = JSON.generate({
          model: @model,
          state: state,
          questions: {
            # Jev is only sound if the first question is whether the state is
            # enough to answer the real one. Both run in one request; code
            # consumes `next` only when `enough` clears the threshold.
            enough: {
              type: "noul",
              instructions: "Is `controls` together with `page` enough context to pick which control best pursues `goal`?",
              criteria: {
                true: "A specific control is clearly worth clicking toward the goal",
                false: "The labels and page are too thin or ambiguous to prefer one control"
              }
            },
            next: {
              type: "choice",
              instructions: "Which control in `controls` should the test walk click next to best pursue `goal`?",
              criteria: labels.to_h { |label| [ label, label ] }
            }
          }
        })
        status, raw = call_transport(SYSTEM_ONE_URL,
                                      { "authorization" => "Bearer #{@api_key}",
                                        "content-type" => "application/json",
                                        "user-agent" => USER_AGENT }, body)
        raise "Jev HTTP #{status}" unless status.between?(200, 299)

        answers = JSON.parse(raw).fetch("answers")
        enough = answers.dig("enough", "noul")
        return [ nil, 0 ] if enough && Float(enough) < @threshold

        answer = answers.fetch("next")
        choice = answer["choice"]
        conf = answer["probabilities"]&.fetch(choice, 0) || 0
        [ choice, Float(conf) ]
      end

      def ask_keyless(state, labels)
        body = JSON.generate({ inputs: [ "#{state[:goal]} on #{state[:page]}" ],
                               labels: labels,
                               instructions: "Which page control should an automated test walk click next?" })
        status, raw = call_transport(CLASSIFIER_URL,
                                      { "content-type" => "application/json",
                                        "user-agent" => USER_AGENT }, body)
        raise "classifier HTTP #{status}" unless status.between?(200, 299)

        parsed = JSON.parse(raw)
        res = parsed["results"] ? parsed["results"].first : parsed
        [ res["label"], Float(res["confidence"] || 0) ]
      end

      def call_transport(url, headers, body)
        @usage[:calls] += 1
        @usage[:request_bytes] += body.to_s.bytesize
        status, raw = @transport.call(url, headers, body)
        record_token_usage(raw)
        [ status, raw ]
      end

      # TypeSafe returns { usage: { input_tokens:, output_tokens: } }.
      # classifier.dev does not — then we keep calls/bytes and leave tokens at 0.
      def record_token_usage(raw)
        parsed = JSON.parse(raw)
        tokens = parsed["usage"]
        return unless tokens.is_a?(Hash)

        @usage[:input_tokens] += tokens["input_tokens"].to_i
        @usage[:output_tokens] += tokens["output_tokens"].to_i
      rescue JSON::ParserError, TypeError
        nil
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
