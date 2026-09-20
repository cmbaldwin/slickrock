# frozen_string_literal: true

module Slickrock
  # One frozen moment of the page: what every oracle is handed, and the unit
  # the walker prints when narrating a step.
  Snapshot = Struct.new(:url, :title, :text, :controls, :console_messages, keyword_init: true)
end
