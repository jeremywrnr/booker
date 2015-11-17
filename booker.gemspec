Gem::Specification.new do |g|
  g.name        = 'booker'
  g.version     = '0.3.1'
  g.date        = '2015-11-17'
  g.summary     = 'CLI parser/selector for google chrome bookmarks'
  g.description = <<-EOF
    Select your bookmarks from the command line, by their bookmark id number.
    ZSH users will be able to tab complete through their matches, similar to
    how the autocompletion for `kill` works. If no bookmark is provided, web
    will check if the argument is a website and visit it, or search duckduckgo
    for the string argument.
  EOF
  g.homepage    = 'http://github.com/jeremywrnr/booker'
  g.author      = 'Jeremy Warner'
  g.email       = 'jeremywrnr@gmail.com'
  g.license     = 'MIT'
  g.executables = ['web']
  g.files       = ['lib/booker.rb', 'lib/bookmarks.rb',
                   'lib/config.rb', 'lib/consts.rb']
  g.add_runtime_dependency     'ruby-terminfo',  '~> 0.1', '>= 0.1.1'
  g.add_runtime_dependency     'json',           '~> 1.8', '>= 1.8.1'
  g.add_development_dependency 'rspec',          '~> 3.3', '>= 3.3.2'
  g.post_install_message = <<-EOF
    Thank you for installing booker!
    To find your bookmarks,  run `web -i bookmarks`
    To add zsh completion,   run `web -i completion`
    To see more help,        run `web --help`
  EOF
end
