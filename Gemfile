# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# development dependencies belong here rather than in the gemspec: they are not
# part of the contract an installing user accepts, and nothing resolves them at
# install time
group :development, :test do
  gem "rspec", "~> 3.13"
  gem "simplecov", "~> 0.22"
  gem "standard", "~> 1.56"
end
