# justfile for booker

# Variables
gem_name := "booker"
version := `ruby -r./lib/booker.rb -e 'puts Booker.version'`

# Run tests with RSpec
spec:
    bundle exec rspec --color --format documentation

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

# Find Chrome bookmarks JSON files
find:
    @echo "searching for chrome bookmarks json..."
    @find ~ -iname "*bookmarks" | grep -i chrom

# List all available recipes
help:
    @just --list
