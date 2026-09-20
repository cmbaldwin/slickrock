# frozen_string_literal: true

module Slickrock
  module Drivers
    # Drives a Capybara session: rack_test for structure, a real browser
    # (Cuprite/Selenium) when console oracles matter.
    #
    # Why Capybara first: the target Rails apps already test through it, so a
    # walk reuses their session setup. rack_test finds controls and navigates
    # but ignores frames and disables forgery protection — the exact blind
    # spots behind the two production bugs in docs/SPEC.md — so console
    # oracles only bite under a JS driver. Both modes share this interface.
    #
    # Capybara is never required here. The session is duck-typed, so the gem
    # still loads when a consumer hasn't installed Capybara at all.
    class Capybara
      CONTROL_SELECTOR = "button, a[href], input[type=submit], select, input:not([type=hidden])"

      def initialize(session)
        @session = session
      end

      def visit(url)
        @session.visit(url)
        nil
      end

      def current_url
        @session.current_url.to_s
      end

      def title
        @session.title.to_s
      end

      def text
        @session.text.to_s
      end

      # Re-queried every call, never cached — see SPEC.md "Controls are
      # re-read every step." Visible + enabled only. Label order from
      # SPEC.md 2.1: visible text -> aria-label -> value -> placeholder ->
      # name. Never blank — an unlabelled control still needs a string a
      # human can read in a failure report.
      def controls
        @session.all(:css, CONTROL_SELECTOR, visible: true).filter_map { |node| build_control(node) }
      end

      def click(control)
        control.ref.click
      end

      def fill(control, value)
        control.ref.set(value)
      end

      # Selenium exposes `browser.logs`; rack_test has no such thing. A
      # missing log API is a degraded oracle, not a walk failure.
      def console_messages
        @session.driver.browser.logs.get(:browser).map do |entry|
          { level: entry.level.to_s.downcase, text: entry.message.to_s }
        end
      rescue StandardError
        []
      end

      # Selenium can save a PNG; rack_test cannot render anything. Same
      # rule as console_messages: absence of the feature is not an error.
      def screenshot(path)
        @session.save_screenshot(path)
        path
      rescue StandardError
        nil
      end

      private

      def build_control(node)
        return nil if node.disabled?

        Control.new(
          ref: node,
          label: label_for(node),
          kind: kind_for(node),
          enabled: true,
          meta: {},
        )
      rescue StandardError
        nil
      end

      def label_for(node)
        [ node.text, node[:"aria-label"], node[:value], node[:placeholder], node[:name], node[:title] ]
          .map { |candidate| candidate.to_s.strip }
          .find { |candidate| !candidate.empty? } || fallback_label(node)
      end

      def fallback_label(node)
        "#{node.tag_name}##{node[:id] || node[:type] || "?"}"
      end

      def kind_for(node)
        case node.tag_name
        when "a" then :link
        when "select" then :select
        when "button" then :button
        when "input" then kind_for_input(node)
        else :field
        end
      end

      def kind_for_input(node)
        case node[:type].to_s.downcase
        when "submit" then :button
        when "checkbox" then :checkbox
        when "radio" then :radio
        else :field
        end
      end
    end
  end
end
