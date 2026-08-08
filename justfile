# justfile for booker

# Variables
gem_name := "booker"
version := `ruby -r./lib/booker/version.rb -e 'puts Booker::VERSION'`

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

# Build the github pages site into site/ (readme + the coverage report)
docs: cov
    bundle exec ruby docs/build.rb

# Open the built site
docs-open: docs
    open site/index.html

# Everything CI checks: tests with coverage, then lint
ci: cov lint

# The completion scripts are copied into $fpath at install time, so a fresh gem
# on its own leaves the old ones sitting on disk. 'completion' rather than a
# bare --install: the latter also regenerates the config and prompts for a
# bookmarks source, neither of which belongs in a build.
#
# just takes the last comment line as the recipe's description, so the summary
# goes here rather than above the rationale
# Build and install the gem, refreshing shell completions with it
build:
    gem build {{gem_name}}.gemspec
    gem install {{gem_name}}-{{version}}.gem
    booker --install completion
    @echo ""
    @echo "zsh caches _booker for the session. to pick it up in this shell:"
    @echo "  unfunction _booker && autoload -U _booker"

# Clean up gem files
clean:
    @echo "cleaning gems..."
    rm -fv *.gem

# Clean, build, and push gem to RubyGems
push: clean build
    gem push {{gem_name}}-{{version}}.gem
