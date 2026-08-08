# version.rb holds nothing but the constant, so requiring it here does not drag
# the library in. that matters: bundler evaluates this file before the specs
# start SimpleCov, and anything loaded first would go untracked.
require_relative "lib/booker/version"

Gem::Specification.new do |g|
  g.name = "booker"
  g.summary = "CLI bookmark manager for Chrome, Firefox, and Safari"
  g.description = <<-EOF
    Search, browse, and open bookmarks from the command line. Supports Chrome,
    Chromium, Firefox, and Safari. Browse all bookmarks interactively, or
    search by keyword. Zsh, bash, and fish users get tab completion through
    bookmark matches. Can also open websites directly or search with your
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
  g.homepage = "http://github.com/jeremywrnr/booker"

  g.required_ruby_version = ">= 3.2"
  g.add_runtime_dependency "json", "~> 2.21"
  g.add_runtime_dependency "sqlite3", "~> 2.9", ">= 2.9.5"
  g.add_runtime_dependency "rexml", "~> 3.4"
  g.add_development_dependency "rspec", "~> 3.13"
  g.add_development_dependency "simplecov", "~> 0.22"
  g.add_development_dependency "standard", "~> 1.56"
  g.post_install_message = "To add zsh, bash, or fish completion run: booker --install"
end
