# frozen_string_literal: true

# specs for the string and terminal helpers in Booker::Output
#
# the helpers are a refinement now, so this file has to opt in the same way the
# library files do - without this line String has no #grn at all

using Booker::Colors

RSpec.describe "String extensions" do
  # $stdout is /dev/null under the suite, so auto-detection would switch color
  # off for every example here. force it on, and let the specs below cover the
  # off switches explicitly
  before { Booker::Colors.enabled = true }
  after { Booker::Colors.enabled = nil }
  describe "#window" do
    it "should truncate strings longer than width" do
      str = "a" * 100
      result = str.window(10)
      expect(result.length).to eq(10)
    end

    it "should pad strings shorter than width" do
      str = "hello"
      result = str.window(10)
      expect(result.length).to eq(10)
      expect(result).to match(/hello\s+/)
    end

    it "should handle exact width" do
      str = "hello"
      result = str.window(5)
      expect(result).to eq("hello")
    end
  end

  describe "color methods" do
    it "should add color codes" do
      str = "test"
      expect(str.red).to include("\033[")
      expect(str.grn).to include("\033[")
      expect(str.blu).to include("\033[")
      expect(str.yel).to include("\033[")
      expect(str.cyan).to include("\033[")
    end

    it "should reset color codes" do
      str = "test"
      expect(str.reset).to include("\033[0;0m")
    end

    it "should work on empty strings" do
      expect("".red).to be_a(String)
    end
  end

  # a gem that writes escape codes into a pipe makes `booker > out.txt` and
  # `booker | less` unreadable, so the codes are conditional
  describe "when color is switched off" do
    it "returns the string untouched rather than wrapping it" do
      Booker::Colors.enabled = false
      expect("test".red).to eq("test")
      expect("test".grn).to eq("test")
      expect("test".reset).to eq("test")
    end

    it "still windows and pads normally, so table layout is unaffected" do
      Booker::Colors.enabled = false
      expect("hello".window(10).length).to eq(10)
    end
  end

  describe "Booker::Colors.enabled?" do
    before { Booker::Colors.enabled = nil } # back to auto-detection

    it "is off when stdout is not a terminal" do
      allow($stdout).to receive(:tty?).and_return(false)
      expect(Booker::Colors.enabled?).to be false
    end

    it "is on for a terminal with no NO_COLOR set" do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(ENV).to receive(:[]).with("NO_COLOR").and_return(nil)
      expect(Booker::Colors.enabled?).to be true
    end

    it "is off when NO_COLOR is set, even on a terminal" do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(ENV).to receive(:[]).with("NO_COLOR").and_return("1")
      expect(Booker::Colors.enabled?).to be false
    end
  end
end
