# justfile for booker

# Variables
gem_name := "booker"
version := `ruby -r./lib/booker.rb -e 'puts Booker.version'`

# List all available recipes
list:
    @just --list

# Run tests with RSpec
spec:
    bundle exec rspec --color --format documentation

# Format Ruby source with standardrb
format:
    bundle exec standardrb --fix

# Check formatting without changing files
lint:
    bundle exec standardrb

# Run tests with a coverage report
cov:
    @COVERAGE=1 bundle exec rspec --color --format progress

# Open the HTML coverage report
cov-html: cov
    open coverage/index.html

# Everything CI checks: tests with coverage, then lint
ci: cov lint

# Build and install the gem
build:
    gem build {{gem_name}}.gemspec
    gem install {{gem_name}}-{{version}}.gem

# Clean up gem files
clean:
    @echo "cleaning gems..."
    rm -fv *.gem

# Clean, build, and push gem to RubyGems
push: clean build
    gem push {{gem_name}}-{{version}}.gem
