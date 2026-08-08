# frozen_string_literal: true

# specs for Booker::Installer: completion, config and bookmark discovery
#
# required explicitly: the installer is reachable only through --install, so
# lib/booker leaves it for CLI#installer to load rather than paying for it on
# every search and every tab press
require_relative "../lib/booker/installer"

RSpec.describe "shell completion" do
  # Booker#initialize immediately parses argv, so build a bare instance to
  # exercise the install/read helpers on their own
  let(:booker) { Booker::Installer.new }

  describe "#completion_script" do
    it "ships a script for every supported shell" do
      expect(Booker::Installer::SHELLS).to contain_exactly("zsh", "bash", "fish")
    end

    it "reads the zsh script" do
      expect(booker.completion_script("_booker")).to include("#compdef booker")
    end

    it "reads the bash script" do
      expect(booker.completion_script("booker.bash")).to include("complete -F _booker booker")
    end

    it "reads the fish script" do
      expect(booker.completion_script("booker.fish")).to include("complete -c booker")
    end

    it "has every script call the raw feed rather than --complete" do
      Booker::Installer::SHELLS.zip(["_booker", "booker.bash", "booker.fish"]).each do |_shell, name|
        expect(booker.completion_script(name)).to include("booker --complete-raw")
      end
    end

    it "exits rather than raising when a script is missing" do
      expect { booker.completion_script("nope.sh") }.to raise_error(SystemExit)
    end
  end

  describe "installing into a clean home" do
    # the one place booker shells out here is `zsh -c 'echo $fpath'`, and it
    # treats a missing zsh as fatal - so an unstubbed call does not just fail an
    # example, it exits the process and takes the rest of the suite with it.
    # pinned for the whole block rather than per example: ubuntu ships no zsh at
    # all, and a developer whose $fpath happens to hold a writable dir would
    # otherwise skip the ~/.zsh/completion branch the specs below describe.
    # entries deliberately outside the temp HOME, so the install falls through
    # to creating ~/.zsh/completion - which zsh only reads once ~/.zshrc puts it
    # on $fpath, hence the rc file edits further down
    before do
      allow(Open3).to receive(:capture3)
        .with("zsh", "-c", "echo $fpath")
        .and_return(["/usr/share/zsh/site-functions\n", "", nil])
    end

    around do |example|
      Dir.mktmpdir do |tmp|
        saved = ENV.to_hash.slice("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME")
        ENV["HOME"] = tmp
        ENV.delete("XDG_DATA_HOME")
        ENV.delete("XDG_CONFIG_HOME")
        @home = tmp
        begin
          example.run
        ensure
          ENV.delete("XDG_DATA_HOME")
          ENV.delete("XDG_CONFIG_HOME")
          saved.each { |k, v| ENV[k] = v }
        end
      end
    end

    it "installs fish completion where fish autoloads it" do
      capture_stdout { booker.install_completion_fish }
      installed = File.join(@home, ".config/fish/completions/booker.fish")
      expect(File.exist?(installed)).to be true
      expect(File.read(installed)).to eq(booker.completion_script("booker.fish"))
    end

    it "installs bash completion into the XDG dir when bash-completion is present" do
      allow(booker).to receive(:bash_completion_present?).and_return(true)
      capture_stdout { booker.install_completion_bash }

      installed = File.join(@home, ".local/share/bash-completion/completions/booker")
      expect(File.exist?(installed)).to be true
      # bash-completion does the loading, so ~/.bashrc is left alone
      expect(File.exist?(File.join(@home, ".bashrc"))).to be false
    end

    it "falls back to sourcing from bashrc when bash-completion is absent" do
      allow(booker).to receive(:bash_completion_present?).and_return(false)
      capture_stdout { booker.install_completion_bash }

      expect(File.exist?(File.join(@home, ".bash_completion.d/booker"))).to be true
      expect(File.read(File.join(@home, ".bashrc"))).to include(".bash_completion.d/booker")
    end

    it "does not stack up duplicate bashrc lines when re-run" do
      allow(booker).to receive(:bash_completion_present?).and_return(false)
      3.times { capture_stdout { booker.install_completion_bash } }

      bashrc = File.read(File.join(@home, ".bashrc"))
      expect(bashrc.scan("# Booker completion").length).to eq(1)
    end

    it "installs zsh completion under a writable fpath dir" do
      capture_stdout { booker.install_completion_zsh }
      expect(File.exist?(File.join(@home, ".zsh/completion/_booker"))).to be true
    end

    describe "wiring ~/.zshrc up to the created completion dir" do
      it "adds the fpath lines when zshrc does not mention the dir yet" do
        zshrc = File.join(@home, ".zshrc")
        File.write(zshrc, "export EDITOR=vim\n")

        output = capture_stdout { booker.install_completion_zsh }

        expect(File.read(zshrc)).to include("fpath=(~/.zsh/completion $fpath)")
        expect(File.read(zshrc)).to include("autoload -Uz compinit && compinit")
        # the original contents survive the append
        expect(File.read(zshrc)).to include("export EDITOR=vim")
        expect(output).to match(/Added completion to ~\/.zshrc/)
      end

      it "leaves an already configured zshrc alone" do
        zshrc = File.join(@home, ".zshrc")
        File.write(zshrc, "fpath=(~/.zsh/completion $fpath)\n")

        output = capture_stdout { booker.install_completion_zsh }

        expect(File.read(zshrc).scan("fpath=(").length).to eq(1)
        expect(output).to match(/already configured/)
      end

      it "prints the line to add by hand when there is no zshrc" do
        output = capture_stdout { booker.install_completion_zsh }

        expect(File.exist?(File.join(@home, ".zshrc"))).to be false
        expect(output).to match(/Add this to your ~\/.zshrc/)
      end
    end

    it "exits when zsh is not installed to report an $fpath" do
      allow(Open3).to receive(:capture3)
        .with("zsh", "-c", "echo $fpath")
        .and_raise(Errno::ENOENT)

      expect { capture_stdout { booker.install_completion_zsh } }.to raise_error(SystemExit)
    end

    # nothing writable in $fpath and no home dir to fall back on: booker cannot
    # fix this itself, so it says what to run rather than failing silently
    it "explains the manual fix when no fpath dir can be written" do
      allow(Open3).to receive(:capture3)
        .with("zsh", "-c", "echo $fpath")
        .and_return(["/nonexistent/site-functions\n", "", nil])
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES)

      output = capture_stdout { booker.install_completion_zsh }

      expect(output).to match(/Could not install ZSH completion/)
      expect(output).to match(/mkdir -p ~\/.zsh\/completion && booker --install zsh/)
    end

    it "warns rather than raising when bash completion cannot be written" do
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, "read-only")

      output = capture_stdout { booker.install_completion_bash }

      expect(output).to match(/could not install bash completion/)
      expect(output).to include("read-only")
    end

    it "warns rather than raising when fish completion cannot be written" do
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, "read-only")

      output = capture_stdout { booker.install_completion_fish }

      expect(output).to match(/could not install fish completion/)
      expect(output).to include("read-only")
    end

    it "installs every detected shell at once" do
      allow(booker).to receive(:shell_present?).and_return(true)
      allow(booker).to receive(:bash_completion_present?).and_return(false)
      capture_stdout { booker.install_completion }

      expect(File.exist?(File.join(@home, ".zsh/completion/_booker"))).to be true
      expect(File.exist?(File.join(@home, ".bash_completion.d/booker"))).to be true
      expect(File.exist?(File.join(@home, ".config/fish/completions/booker.fish"))).to be true
    end

    it "skips shells that are not installed instead of failing" do
      allow(booker).to receive(:shell_present?) { |shell| shell == "fish" }
      output = capture_stdout { booker.install_completion }

      expect(File.exist?(File.join(@home, ".config/fish/completions/booker.fish"))).to be true
      expect(output).to match(/Skip.*zsh, bash/)
    end

    it "warns rather than failing when no supported shell exists" do
      allow(booker).to receive(:shell_present?).and_return(false)
      output = capture_stdout { booker.install_completion }
      expect(output).to match(/no supported shell found/)
    end

    %w[zsh bash fish].each do |shell|
      it "routes --install #{shell} to just that shell" do
        expect(booker).to receive(:"install_completion_#{shell}")
        booker.install([shell])
      end
    end
  end
end

RSpec.describe "#bookmark_type_label" do
  let(:booker) { Booker::Installer.new }

  it "labels each known browser" do
    expect(booker.bookmark_type_label(:chrome)).to eq("[Chrome]")
    expect(booker.bookmark_type_label(:firefox)).to eq("[Firefox]")
    expect(booker.bookmark_type_label(:safari)).to eq("[Safari]")
  end

  it "falls back to a placeholder for anything unrecognized" do
    expect(booker.bookmark_type_label(:opera)).to eq("[?]")
  end

  it "colors the label only when asked to" do
    # color: true asks for the escape codes; whether they are actually emitted
    # is then up to Colors.enabled?, and the suite's $stdout is not a terminal
    Booker::Colors.enabled = true

    %i[chrome firefox safari opera].each do |type|
      plain = booker.bookmark_type_label(type)
      expect(booker.bookmark_type_label(type, color: true)).to include(plain)
    end

    expect(booker.bookmark_type_label(:chrome, color: true)).not_to eq("[Chrome]")
  ensure
    Booker::Colors.enabled = nil
  end

  it "stays plain even when asked for color, if color is switched off" do
    Booker::Colors.enabled = false
    expect(booker.bookmark_type_label(:chrome, color: true)).to eq("[Chrome]")
  ensure
    Booker::Colors.enabled = nil
  end
end

RSpec.describe "#install_bookmarks" do
  let(:booker) { Booker::Installer.new }

  around do |example|
    Dir.mktmpdir do |tmp|
      saved = ENV["HOME"]
      ENV["HOME"] = tmp
      @home = tmp
      begin
        example.run
      ensure
        ENV["HOME"] = saved
      end
    end
  end

  before do
    # discovery reads the constant, which was frozen from ENV at load time, so
    # the temp home above has to be said twice
    stub_const("Booker::Config::HOME", @home)

    # record config writes rather than letting them reach a real ~/.booker.yml
    @written = []
    allow_any_instance_of(Booker::Config).to receive(:write) { |_instance, k, v| @written << [k, v] }
  end

  def add_chrome
    dir = File.join(@home, ".config/google-chrome/Default")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "Bookmarks"), "{}")
    File.join(dir, "Bookmarks")
  end

  def add_firefox
    base = File.join(@home, ".mozilla/firefox")
    FileUtils.mkdir_p(File.join(base, "abc.default"))
    FileUtils.touch(File.join(base, "abc.default", "places.sqlite"))
    File.write(File.join(base, "profiles.ini"), "[Profile0]\nPath=abc.default\n")
    File.join(base, "abc.default", "places.sqlite")
  end

  it "exits when no browser bookmarks can be found" do
    expect { capture_stdout { booker.install_bookmarks } }.to raise_error(SystemExit)
  end

  it "auto selects the only source it finds" do
    chrome = add_chrome
    output = capture_stdout { booker.install_bookmarks }

    expect(@written).to eq([[:bookmarks, chrome]])
    expect(output).to include("[Chrome]")
  end

  it "offers every source when more than one exists" do
    add_chrome
    add_firefox
    allow(booker).to receive(:gets).and_return("0\n")

    output = capture_stdout { booker.install_bookmarks }

    expect(output).to include("ALL SOURCES")
    expect(output).to include("[Firefox]")
  end

  it "saves all sources when 0 is picked" do
    chrome = add_chrome
    firefox = add_firefox
    allow(booker).to receive(:gets).and_return("0\n")

    capture_stdout { booker.install_bookmarks }

    key, paths = @written.first
    expect(key).to eq(:bookmarks)
    expect(paths).to contain_exactly(chrome, firefox)
  end

  it "saves just the numbered source when one is picked" do
    chrome = add_chrome
    add_firefox
    allow(booker).to receive(:gets).and_return("1\n")

    capture_stdout { booker.install_bookmarks }

    expect(@written).to eq([[:bookmarks, chrome]])
  end

  it "exits when the prompt gets no answer" do
    add_chrome
    add_firefox
    allow(booker).to receive(:gets).and_return(nil)

    expect { capture_stdout { booker.install_bookmarks } }.to raise_error(SystemExit)
  end
end

RSpec.describe "#install_config" do
  let(:booker) { Booker::Installer.new }

  it "reports where the example config landed" do
    allow_any_instance_of(Booker::Config).to receive(:write)
    output = capture_stdout { booker.install_config }
    expect(output).to include("example config file written")
  end

  it "exits when the config file cannot be written" do
    allow_any_instance_of(Booker::Config).to receive(:write).and_raise(Errno::EACCES)
    expect { capture_stdout { booker.install_config } }.to raise_error(SystemExit)
  end
end

RSpec.describe "#install routing" do
  let(:booker) { Booker::Installer.new }

  before do
    %i[install_completion install_bookmarks install_config install_safari].each do |installer|
      allow(booker).to receive(installer)
    end
  end

  it "expands all into every installer, safari included" do
    %i[install_completion install_config install_bookmarks install_safari].each do |installer|
      expect(booker).to receive(installer)
    end

    booker.install(["all"])
  end

  {
    "completion" => :install_completion,
    "bookmarks" => :install_bookmarks,
    "config" => :install_config,
    "safari" => :install_safari
  }.each do |target, installer|
    it "routes #{target} to #{installer}" do
      expect(booker).to receive(installer)
      booker.install([target])
    end
  end

  it "exits on an install target it does not recognize" do
    expect { capture_stdout { booker.install(["banana"]) } }.to raise_error(SystemExit)
  end
end

RSpec.describe "#install_safari" do
  let(:booker) { Booker::Installer.new }
  let(:plist) { File.join(ENV["HOME"], "Library/Safari/Bookmarks.plist") }

  before do
    # pretend to be a mac holding a bookmarks file, and never really shell out
    stub_const("RUBY_PLATFORM", "x86_64-darwin25")
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(plist).and_return(true)
    allow(booker).to receive(:system).and_return(true)
    allow(booker).to receive(:safari_readable?).and_return(false)
  end

  it "skips the whole flow when not on a mac" do
    stub_const("RUBY_PLATFORM", "x86_64-linux")
    expect(capture_stdout { booker.install_safari }).to include("macOS-only")
  end

  it "asks the user to launch safari when there is no bookmarks file" do
    allow(File).to receive(:exist?).with(plist).and_return(false)
    expect(capture_stdout { booker.install_safari }).to include("Safari bookmarks not found")
  end

  it "stops early when the file is already readable" do
    allow(booker).to receive(:safari_readable?).and_return(true)
    expect(capture_stdout { booker.install_safari }).to include("already readable")
  end

  it "opens the full disk access pane" do
    allow($stdin).to receive(:gets).and_return("A\n")
    expect(booker).to receive(:system).with("open", /Privacy_AllFiles/)

    capture_stdout { booker.install_safari }
  end

  it "walks through granting access to the terminal" do
    allow($stdin).to receive(:gets).and_return("A\n")
    expect(capture_stdout { booker.install_safari }).to include("add your terminal app")
  end

  it "treats an empty answer as the terminal option" do
    allow($stdin).to receive(:gets).and_return("\n")
    expect(capture_stdout { booker.install_safari }).to include("add your terminal app")
  end

  it "confirms success after the narrower plutil grant" do
    allow(booker).to receive(:safari_readable?).and_return(false, true)
    allow($stdin).to receive(:gets).and_return("B\n", "\n")

    output = capture_stdout { booker.install_safari }

    expect(output).to include("/usr/bin/plutil")
    expect(output).to include("now readable")
  end

  it "reports a failure when plutil still cannot read the file" do
    allow($stdin).to receive(:gets).and_return("B\n", "\n")
    expect(capture_stdout { booker.install_safari }).to include("still can't read")
  end

  it "exits on a choice that is neither A nor B" do
    allow($stdin).to receive(:gets).and_return("Q\n")
    expect { capture_stdout { booker.install_safari } }.to raise_error(SystemExit)
  end
end

RSpec.describe "environment probes" do
  let(:booker) { Booker::Installer.new }

  it "detects a shell that exists, and one that does not" do
    expect(booker.shell_present?("sh")).to be true
    expect(booker.shell_present?("definitely-not-a-real-shell")).to be false
  end

  it "answers whether bash-completion is installed either way" do
    expect([true, false]).to include(booker.bash_completion_present?)
  end

  it "reports safari bookmarks as unreadable when the file is not there" do
    expect(booker.safari_readable?("/nonexistent/Bookmarks.plist")).to be_falsey
  end
end

RSpec.describe "Booker::Installer clearing the zsh completion cache" do
  # a new completion file is invisible to a shell whose compinit dump still
  # describes the old one, so installing has to drop the dump
  let(:installer) { Booker::Installer.new }

  it "removes every compinit dump it finds" do
    Dir.mktmpdir do |tmp|
      stub_const("ENV", ENV.to_hash.merge("ZDOTDIR" => tmp))
      dumps = [".zcompdump", ".zcompdump-HOST-5.9", ".zcompdump-HOST-5.9.zwc"]
      dumps.each { |d| File.write(File.join(tmp, d), "stale") }

      expect(capture_stdout { installer.clear_zsh_compdump }).to include("Refreshed")
      expect(Dir.glob(File.join(tmp, ".zcompdump*"))).to be_empty
    end
  end

  it "says nothing when there is no dump to clear" do
    Dir.mktmpdir do |tmp|
      stub_const("ENV", ENV.to_hash.merge("ZDOTDIR" => tmp))
      expect(capture_stdout { installer.clear_zsh_compdump }).to eq("")
    end
  end

  it "does not fail the install over a dump it cannot remove" do
    Dir.mktmpdir do |tmp|
      stub_const("ENV", ENV.to_hash.merge("ZDOTDIR" => tmp))
      File.write(File.join(tmp, ".zcompdump"), "stale")
      allow(File).to receive(:delete).and_raise(Errno::EACCES)

      expect { capture_stdout { installer.clear_zsh_compdump } }.not_to raise_error
    end
  end

  it "falls back to home when ZDOTDIR is unset" do
    Dir.mktmpdir do |tmp|
      stub_const("ENV", ENV.to_hash.except("ZDOTDIR"))
      allow(installer).to receive(:home).and_return(tmp)
      File.write(File.join(tmp, ".zcompdump"), "stale")

      capture_stdout { installer.clear_zsh_compdump }
      expect(Dir.glob(File.join(tmp, ".zcompdump*"))).to be_empty
    end
  end
end
