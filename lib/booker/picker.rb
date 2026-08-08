# frozen_string_literal: true

# an external fuzzy finder (fzf by default) as booker's selection ui. booker
# feeds it candidate lines on stdin and reads the chosen ones back on stdout;
# the finder opens /dev/tty itself for the interface, so the pipes on either
# side carry nothing but data.
#
# this knows nothing about bookmarks - it takes lines and returns the first
# tab separated field of whatever came back, which keeps it testable against
# `head` and `cat` rather than against a real finder.

require "shellwords"

module Booker
  class Picker
    # --delimiter/--with-nth hide the id column: booker needs it back, but it is
    # noise on screen, and hiding it also takes it out of the match, so typing
    # "2_" does not pull up every bookmark from the second source. --no-sort
    # keeps booker's own ordering.
    #
    # deliberately no --multi. picking a bookmark is a one-at-a-time thing, and
    # under --multi fzf reads tab as "mark this and move down" - the one key
    # booker's own completion trained everybody to press here. a couple of taps
    # to scroll would silently mark a handful of bookmarks and open all of them
    # on the next return.
    #
    # a plain array literal rather than %w[]: the delimiter is a real tab and
    # the prompt ends in a space, and neither survives %w[]
    DEFAULT = [
      "fzf",
      "--height=40%",
      "--reverse",
      "--no-sort",
      "--delimiter=\t",
      "--with-nth=2..",
      "--prompt=bookmark> "
    ].freeze

    class << self
      # nil means decide from the environment; true or false forces it, which is
      # what the specs do - their stdin and stdout are never terminals, so the
      # picker would stay off anyway, but saying so keeps that from being an
      # accident of how the suite redirects output
      attr_writer :enabled

      def enabled?
        return @enabled unless @enabled.nil?

        # tty? first: it is a pair of syscalls, where #command reads and parses
        # ~/.booker.yml. a completion subshell asks this on every keystroke
        tty? && !command.nil?
      end

      # both ends, not just stdout: `booker foo | less` still writes to a
      # terminal, but there is no keyboard on the other side of the pipe
      def tty? = $stdin.tty? && $stdout.tty?

      # the configured picker, or fzf when it is on PATH. nil when neither is
      # installed, which is the signal to stay on booker's pre-picker behavior.
      # memoized because #enabled? and #select both ask
      def command
        return @command if defined?(@command)

        configured = Config.new.picker

        # yaml reads a bare `:picker: false` as the boolean, and anyone writing
        # that means "leave the picker off" - without this it would look like
        # nothing was configured at all and quietly start fzf instead
        return @command = nil if configured == false

        # an empty or blank setting is the same request, and would otherwise
        # leave nothing for #which to look up
        argv = configured ? Shellwords.split(configured.to_s) : DEFAULT
        @command = (!argv.empty? && which(argv.first)) ? argv : nil
      end

      # specs stub #command and set #enabled, and both memoize across examples
      def reset!
        remove_instance_variable(:@command) if defined?(@command)
        @enabled = nil
      end

      # no subshell to `which`: this runs before every interactive invocation,
      # and the answer is a PATH scan booker can do itself. a name carrying a
      # separator is a path, exactly as execvp treats it
      def which(bin)
        return executable?(bin) ? bin : nil if bin.include?(File::SEPARATOR)

        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
          .map { |dir| File.join(dir, bin) }
          .find { |path| executable?(path) }
      end

      def executable?(path) = File.executable?(path) && !File.directory?(path)
    end

    # hand the finder its candidates and get back the ids of what was picked.
    #
    #   [ids] - the user chose these
    #   []    - the user cancelled, or nothing matched
    #   nil   - there is no usable finder, so fall back to the old behavior
    def select(lines)
      argv = self.class.command
      return nil if argv.nil?

      io = IO.popen(argv, "r+")
      feed(io, lines)
      chosen = io.read
      io.close

      # fzf: 0 selected, 1 no match, 2 error, 130 interrupted. a selection that
      # came back empty counts as a cancel too - that pairs with the finder
      # exiting 0 the moment it is closed, before it has read anything
      return [] unless Process.last_status&.exitstatus&.zero?

      # at most one, whatever came back. dropping --multi above stops fzf
      # offering multi select in the first place, but a picker named in
      # ~/.booker.yml can still be configured for it, and one return press
      # turning into six browser tabs is never what was meant
      chosen.lines.filter_map { |line|
        id = line.split("\t", 2).first.strip
        id unless id.empty?
      }.first(1)
    rescue Errno::ENOENT
      # the binary went away between the PATH check and the spawn
      nil
    rescue Interrupt
      []
    end

    private

    def feed(io, lines)
      lines.each { |line| io.puts(line) }
      io.close_write
    rescue Errno::EPIPE
      # expected, not exceptional: the finder exits the instant escape is
      # pressed, and with a few hundred bookmarks booker is usually still
      # writing. the exit status below is what says what happened
    end
  end
end
