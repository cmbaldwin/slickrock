# frozen_string_literal: true

module Slickrock
  # A single interactive element found on a page: a button, link, field, etc.
  # `ref` is driver-private (a Capybara node, a Playwright selector, a Fake
  # destination) -- nothing outside the driver that produced it should
  # interpret it, which is why #to_s never prints it.
  Control = Struct.new(:ref, :label, :kind, :enabled, :meta, keyword_init: true) do
    def enabled?
      !!enabled
    end

    # Readable in a failure report.
    def to_s
      state = enabled? ? "" : " [disabled]"
      "#{kind}(#{label.inspect})#{state}"
    end
  end
end
