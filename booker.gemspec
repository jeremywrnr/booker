require_relative "lib/booker"

Gem::Specification.new do |g|
  g.name = "booker"
  g.summary = "CLI bookmark manager for Chrome and Firefox"
  g.description = <<-EOF
    Search, browse, and open bookmarks from the command line. Supports Chrome,
    Chromium, and Firefox. Browse all bookmarks interactively, or search by
    keyword. ZSH users get tab completion through bookmark matches. Can also
    open websites directly or search with your preferred search engine.
  EOF

  g.version = Booker.version
  g.platform = Gem::Platform::RUBY

  g.author = "Jeremy Warner"
  g.email = "jeremywrnr@gmail.com"
  g.license = "MIT"
  g.executables = ["booker"]
  g.files = ["lib/booker.rb", "lib/bookmarks.rb", "lib/config.rb", "lib/consts.rb"]
  g.homepage = "http://github.com/jeremywrnr/booker"

  g.add_runtime_dependency "json", "~> 2.0"
  g.add_runtime_dependency "sqlite3", "~> 1.4"
  g.add_development_dependency "rspec", "~> 3.0"
  g.post_install_message = "To add zsh completion run: booker --install"
end
