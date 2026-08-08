# Coverage must start before booker is loaded, or its lines go untracked.
# Opt-in via COVERAGE=1 so a plain `just spec` stays fast: `just cov`
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    # floor sits just under the current 72%, to catch regressions without
    # tripping on ordinary refactors -- raise it as coverage improves
    minimum_coverage line: 70
  end
end

require_relative "../lib/booker"
require "rubygems"
require "rspec"
require "json"
require "tmpdir"

# Redirect stderr and stdout while testing
SILENT = true
if SILENT
  RSpec.configure do |config|
    original_stderr = $stderr
    original_stdout = $stdout
    config.before(:all) do
      $stderr = File.open(File::NULL, "w")
      $stdout = File.open(File::NULL, "w")
    end

    config.after(:all) do
      $stderr = original_stderr
      $stdout = original_stdout
    end

    # allow old and new RSPEC syntax
    config.expect_with(:rspec) do |c|
      c.syntax = [:should, :expect]
    end
  end
end

# Check exit codes with rspec
RSpec::Matchers.define :exit_with_code do |code|
  def supports_block_expectations?
    true
  end
  actual = nil
  match do |block|
    begin
      block.call
    rescue SystemExit => e
      actual = e.status
    end
    actual && actual == code
  end
  failure_message do |block|
    "expected block to call exit(#{code}) but exit" +
      (actual.nil? ? " not called" : "(#{actual}) was called")
  end
  failure_message_when_negated do |block|
    "expected block not to call exit(#{exp_code})"
  end
  description do
    "expect block to call exit(#{exp_code})"
  end
end
