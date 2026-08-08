# frozen_string_literal: true

# specs for Booker::Picker: handing candidate lines to an external finder and
# reading back what was chosen.
#
# the finder is stubbed with coreutils rather than with a double, so these
# exercise the real IO.popen path - the pipe, the exit status, and the broken
# pipe when the child leaves early are the whole of what this class does, and a
# double would test none of them. fzf itself is never needed, here or on ci.

RSpec.describe Booker::Picker do
  # ids deliberately unlike the titles, so a selection can only be right by
  # having come out of the first tab separated field
  def rows(count = 3)
    (0...count).map { |i| "#{i}_abc\tfolder | title #{i}\thttps://example.com/#{i}" }
  end

  def with_finder(argv)
    allow(described_class).to receive(:command).and_return(argv)
    described_class
  end

  describe "#select" do
    it "returns the id of the chosen line" do
      expect(with_finder(["head", "-1"]).select(rows)).to eq("0_abc")
    end

    # `cat` hands every candidate back, standing in for a finder configured
    # with --multi. one return press must never become several browser tabs
    it "opens only one bookmark even if the finder returns several" do
      expect(with_finder(["cat"]).select(rows)).to eq("0_abc")
    end

    it "returns nothing when nothing matched" do
      expect(with_finder(["false"]).select(rows)).to be_nil
    end

    it "returns nothing when the finder was interrupted" do
      # 130 is what fzf exits with on escape or ctrl-c
      expect(with_finder(["sh", "-c", "exit 130"]).select(rows)).to be_nil
    end

    it "survives the finder exiting while booker is still writing" do
      # the escape-on-a-long-list case: `true` is gone before it reads a byte,
      # so the write end breaks partway through. enough rows to outrun the pipe
      # buffer, which is what makes EPIPE certain rather than likely
      expect(with_finder(["true"]).select(rows(20_000))).to be_nil
    end

    it "reports no finder when the binary is gone" do
      expect(with_finder(["booker-no-such-picker"]).select(rows)).to be_nil
    end

    it "reports no finder when none is configured or installed" do
      expect(with_finder(nil).select(rows)).to be_nil
    end

    it "returns nothing when interrupted before the finder starts" do
      picker = with_finder(["cat"])
      allow(IO).to receive(:popen).and_raise(Interrupt)
      expect(picker.select(rows)).to be_nil
    end
  end

  describe "DEFAULT" do
    # under --multi, fzf reads tab as "mark this one and move down" - and tab is
    # exactly what booker's own completion trained everyone to press here, so a
    # couple of taps used to mark several bookmarks and open all of them
    it "does not ask fzf for multi select" do
      expect(described_class::DEFAULT).not_to include("--multi")
    end

    it "keeps the id out of sight and out of the match" do
      expect(described_class::DEFAULT).to include("--with-nth=2..", "--delimiter=\t")
    end
  end

  describe ".command" do
    it "defaults to fzf when nothing is configured" do
      allow_any_instance_of(Booker::Config).to receive(:picker).and_return(nil)
      allow(described_class).to receive(:which).with("fzf").and_return("/usr/bin/fzf")

      expect(described_class.command).to eq(described_class::DEFAULT)
    end

    it "splits a configured picker into argv without a shell" do
      allow_any_instance_of(Booker::Config).to receive(:picker)
        .and_return("sk --height=40% --prompt 'pick one '")
      allow(described_class).to receive(:which).with("sk").and_return("/usr/bin/sk")

      expect(described_class.command)
        .to eq(["sk", "--height=40%", "--prompt", "pick one "])
    end

    # yaml turns a bare `:picker: false` into the boolean, which would otherwise
    # be indistinguishable from having configured nothing - and so would start
    # fzf, the exact opposite of what was asked for
    it "is nil when the config turns the picker off outright" do
      allow_any_instance_of(Booker::Config).to receive(:picker).and_return(false)
      expect(described_class).not_to receive(:which)

      expect(described_class.command).to be_nil
    end

    it "is nil when the configured picker is blank" do
      allow_any_instance_of(Booker::Config).to receive(:picker).and_return("   ")

      expect(described_class.command).to be_nil
    end

    it "is nil when the picker is not installed" do
      allow_any_instance_of(Booker::Config).to receive(:picker).and_return("nope")
      allow(described_class).to receive(:which).with("nope").and_return(nil)

      expect(described_class.command).to be_nil
    end
  end

  describe ".which" do
    it "finds an executable on PATH" do
      expect(described_class.which("sh")).to eq("/bin/sh").or eq("/usr/bin/sh")
    end

    it "is nil for a name that is on no PATH entry" do
      expect(described_class.which("booker-no-such-picker")).to be_nil
    end

    it "takes a name carrying a separator as a path, not a PATH lookup" do
      expect(described_class.which("/bin/sh")).to eq("/bin/sh")
      expect(described_class.which("/bin/definitely-not-here")).to be_nil
    end

    it "does not mistake a directory for an executable" do
      expect(described_class.which("/bin")).to be_nil
    end
  end

  describe ".enabled?" do
    # the suite forces the picker off for every example; these want the real
    # environment check back
    before { described_class.enabled = nil }
    after { described_class.enabled = false }

    it "is whatever it was forced to be" do
      described_class.enabled = true
      expect(described_class.enabled?).to be true

      described_class.enabled = false
      expect(described_class.enabled?).to be false
    end

    it "is false on a terminal with no finder installed" do
      allow(described_class).to receive(:tty?).and_return(true)
      allow(described_class).to receive(:command).and_return(nil)

      expect(described_class.enabled?).to be false
    end

    it "is true on a terminal with a finder installed" do
      allow(described_class).to receive(:tty?).and_return(true)
      allow(described_class).to receive(:command).and_return(["fzf"])

      expect(described_class.enabled?).to be true
    end

    it "needs both ends of the pipe, not just stdout" do
      # `booker foo | less` writes to a terminal, but has no keyboard on the
      # other side of the pipe
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdout).to receive(:tty?).and_return(false)
      expect(described_class.tty?).to be false

      allow($stdin).to receive(:tty?).and_return(false)
      allow($stdout).to receive(:tty?).and_return(true)
      expect(described_class.tty?).to be false

      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdout).to receive(:tty?).and_return(true)
      expect(described_class.tty?).to be true
    end
  end
end
