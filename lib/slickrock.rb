# frozen_string_literal: true

require_relative "slickrock/version"
require_relative "slickrock/error"
require_relative "slickrock/control"
require_relative "slickrock/snapshot"
require_relative "slickrock/journey"
require_relative "slickrock/result"
require_relative "slickrock/drivers/fake"
require_relative "slickrock/drivers/capybara"
require_relative "slickrock/oracles/no_server_error"
require_relative "slickrock/oracles/no_stale_session"
require_relative "slickrock/oracles/no_turbo_frame_miss"
require_relative "slickrock/oracles/no_js_error"
require_relative "slickrock/oracles/no_blank_page"
require_relative "slickrock/oracle"
require_relative "slickrock/walker"
require_relative "slickrock/steering/jev"

# A gem that random-walks a web UI in a real browser and shouts when the app
# breaks underneath it. See docs/SPEC.md for the design.
module Slickrock
end

# The mixin does not require the minitest gem (it uses `assert` from the
# including test class). Guarded so a missing file cannot take the whole
# gem down for a consumer who never includes it.
begin
  require_relative "slickrock/minitest"
rescue LoadError
  nil
end
