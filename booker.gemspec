Gem::Specification.new do |g|
  g.name        = 'booker'
  g.version     = '0.1'
  g.date        = '2015-10-12'
  g.summary     = 'CLI parser for google chrome bookmarks'
  g.description = 'Select your bookmarks from the command line.'
  g.homepage    = 'http://rubygems.org/gems/booker'
  g.license     = 'MIT'

  g.authors     = ['Jeremy Warner']
  g.email       = ['jeremywrnr@gmail.com']

  g.executables = ['web']
  g.add_development_dependency    "rspec", [">= 0"]
  g.files       = ['lib/booker.rb', 'lib/bookmarks.rb',
                   'lib/browser.rb', 'lib/folder.rb']
end
