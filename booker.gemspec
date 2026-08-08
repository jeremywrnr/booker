# frozen_string_literal: true

# version.rb holds nothing but the constant, so requiring it here does not drag
# the library in. that matters: bundler evaluates this file before the specs
# start SimpleCov, and anything loaded first would go untracked.
require_relative "lib/booker/version"

Gem::Specification.new do |g|
  g.name = "booker"
  g.summary = "CLI bookmark manager for Chrome, Firefox, and Safari"
  g.description = <<-EOF
    Search, browse, and open bookmarks from the command line. Supports Chrome,
    Chromium, Firefox, and Safari. With fzf installed, booker and booker
    <search> open a fuzzy picker over the matches - nothing to install and the
    same in every shell. Zsh, bash, and fish users can also add tab completion
    through bookmark matches. Can open websites directly or search with your
    preferred search engine.
  EOF

  g.version = Booker::VERSION
  g.platform = Gem::Platform::RUBY

  g.author = "Jeremy Warner"
  g.email = "jeremywrnr@gmail.com"
  g.license = "MIT"
  g.executables = ["booker"]
  # globbed rather than listed: the hand written list silently missed the
  # completion scripts once, and they are read at install time so they must ship
  g.files = Dir["lib/**/*.rb"] + Dir["completions/*"]
  g.homepage = "https://github.com/jeremywrnr/booker"

  # rubygems reads these to build the sidebar on the gem page. mfa_required is
  # the one that does real work: it refuses a push that is not multi factor
  # authenticated, so a leaked api key alone cannot publish a release
  # no homepage_uri here - g.homepage already supplies it, and rubygems warns
  # when two metadata keys carry the same url
  g.metadata = {
    "source_code_uri" => g.homepage,
    "bug_tracker_uri" => "#{g.homepage}/issues",
    "changelog_uri" => "#{g.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  g.required_ruby_version = ">= 3.2"

  # add_dependency, not add_runtime_dependency: the longer name is soft
  # deprecated. development dependencies live in the Gemfile - they are not part
  # of what an installing user agrees to
  g.add_dependency "json", "~> 2.21"
  g.add_dependency "sqlite3", "~> 2.9", ">= 2.9.5"
  g.add_dependency "rexml", "~> 3.4"

  # no post_install_message: `booker` and `booker <search>` open the fzf picker
  # on their own, so there is nothing a fresh install has to be told to run.
  # tab completion is an extra rather than the way in, and the readme covers it
end
