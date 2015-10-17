Gem::Specification.new do |g|
  g.name        = 'booker'
  g.version     = '0.2'
  g.date        = '2015-10-17'
  g.summary     = 'CLI parser/selector for google chrome bookmarks'
  g.description = <<-EOF
    Select your bookmarks from the command line, by their bookmark id number.
    ZSH users will be able to tab complete through their matches, similar to
    how the autocompletion for `kill` works. If no bookmark is provided, web
    will check if the argument is a website and visit it, or search duckduckgo
    for the string argument.
  EOF
  g.homepage    = 'http://github.com/jeremywrnr/booker'
  g.license     = 'MIT'
  g.author      = 'Jeremy Warner'
  g.email       = 'jeremywrnr@gmail.com'
  g.executables = ['web']
  g.files       = ['lib/booker.rb', 'lib/bookmarks.rb',
                   'lib/browser.rb', 'lib/config.rb',
                   'lib/consts.rb']
  g.add_runtime_dependency     'yaml',  '>= 1.0.0'
  g.add_runtime_dependency     'json',  '>= 1.8.1'
  g.add_development_dependency 'rspec', '>= 3.3.2'
  g.post_install_message = <<-EOF
    Thank you for installing booker!
    To add zsh completion, run `web --install`
    To set bookmarks location, run `web --install`
  EOF
end
