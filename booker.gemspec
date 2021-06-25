require_relative "lib/booker.rb"

Gem::Specification.new do |g|
  g.name        = 'booker'
  g.summary     = 'CLI parser/selector for google chrome bookmarks'
  g.description = <<-EOF
    Select your bookmarks from the command line, by their bookmark id number.
    ZSH users will be able to tab complete through their matches, similar to
    how the autocompletion for `kill` works. If no bookmark is provided, booker
    will check if the argument is a website and visit it, or go to google
    (or your preferred search engine) with the string argument.
  EOF

  g.version     = Booker.version
  g.platform    = Gem::Platform::RUBY
  g.date        = Time.now.strftime("%Y-%m-%d")

  g.author      = 'Jeremy Warner'
  g.email       = 'jeremywrnr@gmail.com'
  g.license     = 'MIT'
  g.executables = ['booker']
  g.files       = ['lib/booker.rb', 'lib/bookmarks.rb', 'lib/config.rb', 'lib/consts.rb']
  g.homepage    = 'http://github.com/jeremywrnr/booker'

  g.add_runtime_dependency     'json'
  g.add_development_dependency 'rspec'
  g.post_install_message = "To add zsh completion run: booker --install bookmarks"
end
