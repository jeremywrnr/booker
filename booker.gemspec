require_relative "lib/booker"

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

  g.version = Booker.version
  g.platform = Gem::Platform::RUBY

  g.author = "Jeremy Warner"
  g.email = "jeremywrnr@gmail.com"
  g.license = "MIT"
  g.executables = ["booker"]
  # the completion scripts are read at install time, so they have to ship
  g.files = ["lib/booker.rb", "lib/bookmarks.rb", "lib/config.rb", "lib/consts.rb",
    "completions/_booker", "completions/booker.bash", "completions/booker.fish"]
  g.homepage = "http://github.com/jeremywrnr/booker"

  g.required_ruby_version = ">= 3.1"
  g.add_runtime_dependency "json", "~> 2.21"
  g.add_runtime_dependency "sqlite3", "~> 2.9", ">= 2.9.5"
  g.add_runtime_dependency "rexml", "~> 3.4"
  g.add_development_dependency "rspec", "~> 3.13"
  g.add_development_dependency "standard", "~> 1.56"
  g.post_install_message = "To add zsh, bash, or fish completion run: booker --install"
end
