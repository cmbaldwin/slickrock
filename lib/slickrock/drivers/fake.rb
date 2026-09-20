# frozen_string_literal: true

module Slickrock
  module Drivers
    # A scripted page graph with no browser, so the walker, oracles, steering
    # and journey can be tested deterministically and fast (SPEC.md, "Testing
    # the tester").
    #
    # `pages` maps a url to a hash of title:, text:, controls:, console:,
    # status:. `controls` is an array of [label, kind, destination] tuples,
    # optionally followed by an options hash: [label, kind, destination,
    # { enabled: false }]. `click` follows the tuple's destination; a
    # destination with no matching page serves a built-in 404 page.
    class Fake
      NOT_FOUND = {
        title: "Not Found",
        text: "404 Not Found",
        controls: [],
        console: [],
        status: 404
      }.freeze

      attr_reader :visited_urls

      def initialize(pages:)
        @pages = pages
        @visited_urls = []
        @pending_console = []
        @current_url = nil
        @current_page = NOT_FOUND
      end

      def visit(url)
        @current_url = url
        @current_page = @pages[url] || NOT_FOUND
        @visited_urls << url
        @pending_console.concat(@current_page[:console] || [])
        nil
      end

      def current_url
        @current_url
      end

      def title
        @current_page[:title]
      end

      def text
        @current_page[:text]
      end

      # Not part of the driver interface proper, but the fixture format
      # carries it and it's handy for asserting on the built-in 404 page.
      def status
        @current_page[:status] || 200
      end

      def controls
        (@current_page[:controls] || []).map { |tuple| build_control(tuple) }
      end

      def click(control)
        raise Error, "cannot click a disabled control: #{control}" unless control.enabled?

        visit(control.ref) if control.ref
      end

      def fill(control, _value)
        raise Error, "cannot fill a disabled control: #{control}" unless control.enabled?

        nil
      end

      # Draining read: only messages queued (by visit) since the last call.
      def console_messages
        @pending_console.tap { @pending_console = [] }
      end

      def screenshot(path)
        File.write(path, "fake screenshot of #{current_url}")
        path
      end

      private

      def build_control(tuple)
        label, kind, destination, opts = tuple
        opts ||= {}
        Control.new(
          ref: destination,
          label: label,
          kind: kind,
          enabled: opts.fetch(:enabled, true),
          meta: opts.fetch(:meta, {}),
        )
      end
    end
  end
end
