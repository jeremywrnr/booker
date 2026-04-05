# justfile for booker

# Variables
gem_name := "booker"
version := `ruby -r./lib/booker.rb -e 'puts Booker.version'`

# Default: list available recipes
default: list

# List all available recipes
list:
    @just --list

# Run tests with RSpec
spec:
    bundle exec rspec --color --format documentation

# Format Ruby source with standardrb
format:
    bundle exec standardrb --fix

# Development mode with file watching
dev:
    fw -f '**/*.rb' -c 'just spec'

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
