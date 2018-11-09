Gem::Specification.new do |g|
  g.name        = 'booker'
  g.version     = '0.5.1'
  g.date        = '2016-07-18'
  g.summary     = 'CLI parser/selector for google chrome bookmarks'
  g.description = <<-EOF
    Select your bookmarks from the command line, by their bookmark id number.
    ZSH users will be able to tab complete through their matches, similar to
    how the autocompletion for `kill` works. If no bookmark is provided, booker
    will check if the argument is a website and visit it, or go to google
    (or your preferred search engine) with the string argument.
  EOF
  g.homepage    = 'http://github.com/jeremywrnr/booker'
  g.author      = 'Jeremy Warner'
  g.email       = 'jeremywrnr@gmail.com'
  g.license     = 'MIT'
  g.executables = ['booker']
  g.files       = ['lib/booker.rb', 'lib/bookmarks.rb',
                   'lib/config.rb', 'lib/consts.rb']
  g.add_runtime_dependency     'ruby-terminfo',  '~> 0.1', '>= 0.1.1'
  g.add_runtime_dependency     'json',           '~> 2.1', '>= 2.1.0'
  g.add_development_dependency 'rspec',          '~> 3.3', '>= 3.3.2'
  g.post_install_message = <<-EOF
    Thank you for installing booker!
    To find your bookmarks,  run `booker -i bookmarks`
    To add zsh completion,   run `booker -i completion`
    To see more help,        run `booker --help`
  EOF
end
