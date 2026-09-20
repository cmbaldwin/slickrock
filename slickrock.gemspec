# frozen_string_literal: true

require_relative "lib/slickrock/version"

Gem::Specification.new do |spec|
  spec.name = "slickrock"
  spec.version = Slickrock::VERSION
  spec.authors = [ "cmbaldwin" ]
  spec.email = [ "cody@moab.jp" ]

  spec.summary = "Jev-steered random walks of a web UI in a real browser, with oracles that shout when the app breaks."
  spec.description = "Slickrock walks a real browser through your app and checks every page against a set of " \
                      "oracles, catching the invisible-to-assertions bugs a scripted suite walks right past. " \
                      "Jev, TypeSafe's decision model, ranks the controls on each page so the step budget goes " \
                      "on the cart instead of the footer — one call per page, billed on input tokens only, and " \
                      "degrading to uniform random on any failure. Steering is optional; the oracles are not."
  spec.homepage = "https://github.com/cmbaldwin/slickrock"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.glob("lib/**/*.rb") + %w[slickrock.gemspec Gemfile Rakefile .rubocop.yml README.md LICENSE CHANGELOG.md]
  spec.require_paths = [ "lib" ]

  spec.add_development_dependency "capybara"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rack"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rubocop-rails-omakase"
end
