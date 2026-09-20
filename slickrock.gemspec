# frozen_string_literal: true

require_relative "lib/slickrock/version"

Gem::Specification.new do |spec|
  spec.name = "slickrock"
  spec.version = Slickrock::VERSION
  spec.authors = [ "cmbaldwin" ]
  spec.email = [ "cody@moab.jp" ]

  spec.summary = "A Ruby gem that random-walks a web UI in a real browser and shouts when the app breaks underneath it."
  spec.description = "Slickrock drives a real browser through random clicks and checks every page against a set " \
                      "of oracles, catching the invisible-to-assertions bugs that a scripted test suite walks " \
                      "right past."
  spec.homepage = "https://github.com/cmbaldwin/slickrock"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.glob("lib/**/*.rb") + %w[slickrock.gemspec Gemfile Rakefile .rubocop.yml]
  spec.require_paths = [ "lib" ]

  spec.add_development_dependency "capybara"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rack"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rubocop-rails-omakase"
end
