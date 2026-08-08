# frozen_string_literal: true

# Coverage must start before booker is loaded, or its lines go untracked.
# Opt-in via COVERAGE=1 so a plain `just spec` stays fast: `just cov`
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    # Coverage is platform dependent: some safari/plutil/open paths only run on
    # a mac, so linux reports a little under what a mac does. The floor has to
    # clear the lower of the two, since CI measures coverage on linux.
    minimum_coverage line: 95
  end
end

require_relative "../lib/booker"
require "rubygems"
require "rspec"
require "json"
require "tmpdir"
require "stringio"

# dont actually open links while testing, just ignore. keep the real
# implementation around under another name so the #browse specs can still
# exercise it - this override is permanent once the suite loads
module Booker::Browser
  alias_method :real_browse, :browse

  def browse
    "/bin/true "
  end
end

# fixtures live next to the specs; every spec that needs one goes through here
# so the paths stay in one place
def fixture_path(name)
  File.join(__dir__, "fixtures", name)
end

# Helper for capturing stdout
def capture_stdout
  old_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old_stdout
end

# diagnostics go to stderr, so that a warning raised while parsing can never
# land in the middle of the --complete-raw feed the shell scripts read
def capture_stderr
  old_stderr = $stderr
  $stderr = StringIO.new
  yield
  $stderr.string
ensure
  $stderr = old_stderr
end

RSpec.configure do |config|
  # no `should`, and no describe/it on every object in the process - example
  # groups say RSpec.describe instead
  config.disable_monkey_patching!

  # booker prints constantly and the suite drives its cli directly, so the
  # noise has to go somewhere. per example rather than per file: the redirect
  # is torn down before rspec reports, so a failure still prints its own
  # message, and `capture_stdout` / the `output` matcher nest inside this
  config.around(:each) do |example|
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = File.open(File::NULL, "w")
    $stderr = File.open(File::NULL, "w")
    begin
      example.run
    ensure
      $stdout.close
      $stderr.close
      $stdout = original_stdout
      $stderr = original_stderr
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
    "expected block not to call exit(#{code})"
  end
  description do
    "expect block to call exit(#{code})"
  end
end
