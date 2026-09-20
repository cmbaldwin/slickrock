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
    class Capybara
      # @param session [#visit #current_url #title ...] a Capybara::Session
      def initialize(session)
        @session = session
      end

      def visit(url)
        @session.visit(url)
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

      # Visible, enabled controls labelled best-effort. Label sources in
      # order: visible text, aria-label, value, placeholder, name. Unlabelled
      # controls are skipped — the walker cannot report them usefully.
      def controls
        @session.all("button, a[href], input[type=submit], select, input:not([type=hidden])",
                     visible: true).filter_map do |node|
          next unless enabled?(node)

          label = label_for(node)
          next if label.nil? || label.empty?

          kind = control_kind(node)
          Control.new(ref: node, label: label, kind: kind, enabled: true)
        end
      end

      def click(control)
        control.ref.click
      end

      def fill(control, value)
        control.ref.set(value)
      end

      # Browser console entries since the last call, or [] when the driver
      # cannot provide them (rack_test). Never raises: a missing log API is
      # a degraded oracle, not a walk failure.
      def console_messages
        browser = @session.driver.browser
        logs = browser.logs.get(:browser)
        Array(logs).map { |entry| { level: entry.level.to_s, text: entry.message.to_s } }
      rescue StandardError
        []
      end

      def screenshot(path)
        @session.save_screenshot(path)
      end

      private

      def enabled?(node)
        !node.disabled?
      rescue StandardError
        false
      end

      def label_for(node)
        text = node.text.to_s.strip
        return text unless text.empty?

        %w[aria-label value placeholder name title].each do |attr|
          value = node[attr].to_s.strip
          return value unless value.empty?
        end
        nil
      rescue StandardError
        nil
      end

      def control_kind(node)
        case node.tag_name
        when "a" then :link
        when "select" then :select
        when "input"
          case node[:type]
          when "checkbox" then :checkbox
          when "radio" then :radio
          else :field
          end
        when "button" then :button
        else :button
        end
      rescue StandardError
        :button
      end
    end
  end
end
