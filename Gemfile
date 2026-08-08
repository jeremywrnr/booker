# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# development dependencies belong here rather than in the gemspec: they are not
# part of the contract an installing user accepts, and nothing resolves them at
# install time
group :development, :test do
  # only `just docs` uses these - they render readme.md into the github pages
  # landing page, so the readme stays the single source of documentation. the
  # gfm parser is separate from kramdown itself, and without it fenced code
  # blocks and tables would render as literal text rather than failing loudly
  gem "kramdown", "~> 2.5"
  gem "kramdown-parser-gfm", "~> 1.1"
  gem "rspec", "~> 3.13"
  gem "simplecov", "~> 1.0", ">= 1.0.3"
  gem "standard", "~> 1.56"
end
