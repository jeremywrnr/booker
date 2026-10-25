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
    @echo "new shells are ready. zsh keeps _booker for the life of a session,"
    @echo "so to pick it up in THIS one:  unfunction _booker && autoload -U _booker"

alias install := build

# Clean up gem files
clean:
    @echo "cleaning gems..."
    rm -fv *.gem

# The CHANGELOG section for this version, as the GitHub release body
release-notes:
    @awk -v head="## [{{version}}]" ' \
      /^## \[/ { p = index($0, head) == 1; next } \
      !p { next } \
      NF { if (seen) while (blank-- > 0) print ""; blank = 0; seen = 1; print; next } \
      { blank++ }' CHANGELOG.md

# Everything that has to be true before anything is published: a gem pushed
# with no matching release, or a release on a commit that is not on main, is
# the half-done state this exists to rule out
# Check main is clean, pushed and has notes for this version
release-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fail() { echo "release-check: $*" >&2; exit 1; }
    [ "$(git branch --show-current)" = main ] || fail "not on main"
    git diff --quiet HEAD || fail "uncommitted changes"
    [ "$(git rev-parse HEAD)" = "$(gh api 'repos/{owner}/{repo}/commits/main' --jq .sha)" ] \
      || fail "HEAD is not origin/main - pull or push first"
    [ -n "$({{just_executable()}} -f {{justfile()}} release-notes)" ] || fail "CHANGELOG.md has no [{{version}}] section"
    ! gh release view v{{version}} >/dev/null 2>&1 || fail "v{{version}} is already released"

# Clean, build, push gem to RubyGems, and tag a GitHub release
push: release-check clean build
    gem push {{gem_name}}-{{version}}.gem
    printf '%s\n\n---\nPublished to RubyGems on %s: https://rubygems.org/gems/{{gem_name}}/versions/{{version}}\n' \
      "$({{just_executable()}} -f {{justfile()}} release-notes)" "$(date +%F)" \
      | gh release create v{{version}} --target "$(git rev-parse HEAD)" --title v{{version}} --notes-file -
