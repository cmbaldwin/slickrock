# frozen_string_literal: true

module Slickrock
  # Append-only record of a walk's steps. Exists so a Violation can render a
  # reproduction report and so a successful walk can still be inspected.
  class Journey
    include Enumerable

    Step = Struct.new(:url, :label, :kind, :action, keyword_init: true) do
      def to_s
        "#{action} #{kind}(#{label.inspect}) on #{url}"
      end
    end

    def initialize
      @steps = []
    end

    def record(url:, label:, kind:, action:)
      @steps << Step.new(url: url, label: label, kind: kind, action: action)
      self
    end

    def each(&block)
      @steps.each(&block)
    end

    def size
      @steps.size
    end

    # Numbered list, readable directly in a failure report.
    def to_s
      return "  (no steps taken)" if @steps.empty?

      @steps.each_with_index.map { |step, index| "  #{index + 1}. #{step}" }.join("\n")
    end
  end
end
