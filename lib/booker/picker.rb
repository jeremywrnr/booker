# frozen_string_literal: true

# an external fuzzy finder (fzf by default) as booker's selection ui. booker
# feeds it candidate lines on stdin and reads the chosen one back on stdout;
# the finder opens /dev/tty itself for the interface, so the pipes on either
# side carry nothing but data.
#
# this knows nothing about bookmarks - it takes lines and returns the first
# tab separated field of whatever came back, which keeps it testable against
# `head` and `cat` rather than against a real finder.

require "shellwords"

module Booker
  module Picker
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
      # nil means decide from the environment; true or false forces it. the
      # specs set this, and so does --list - same shape as Colors.enabled=
      attr_writer :enabled

      def enabled?
        return @enabled unless @enabled.nil?

        # tty? first: it is a pair of syscalls, where #command reads and parses
        # ~/.booker.yml, and a run that is not interactive never needs to know
        # whether a finder is installed
        tty? && !command.nil?
      end

      # both ends, not just stdout: `booker foo | less` still writes to a
      # terminal, but there is no keyboard on the other side of the pipe
      def tty? = $stdin.tty? && $stdout.tty?

      # the configured picker, or fzf when it is on PATH. nil when neither is
      # installed, which is the signal to stay on booker's pre-picker behavior
      def command
        configured = Config.new.picker

        # yaml reads a bare `:picker: false` as the boolean, and anyone writing
        # that means "leave the picker off" - without this it would look like
        # nothing was configured at all and quietly start fzf instead. a blank
        # setting is the same request, and would leave nothing to look up
        return nil if configured == false

        argv = configured ? Shellwords.split(configured.to_s) : DEFAULT
        (!argv.empty? && which(argv.first)) ? argv : nil
      end

      # no subshell to `which`: this runs before every interactive invocation,
      # and the answer is a PATH scan booker can do itself. a name carrying a
      # separator is a path, exactly as execvp treats it
      def which(bin)
        return executable?(bin) ? bin : nil if bin.include?(File::SEPARATOR)

        # lazy: the answer is usually in the first few entries, and eagerly
        # joining all forty PATH directories to throw them away is the one
        # thing a hand written which is here to avoid
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).lazy
          .map { |dir| File.join(dir, bin) }
          .find { |path| executable?(path) }
      end

      def executable?(path) = File.executable?(path) && !File.directory?(path)

      # hand the finder its candidates and get back the id of what was picked,
      # or nil for every other outcome - cancelled, nothing matched, or no
      # usable finder. one id and not a list: picking a bookmark is a
      # one-at-a-time thing, and dropping --multi above only covers the default
      # finder, not one named in ~/.booker.yml
      def select(lines)
        argv = command
        return nil if argv.nil?

        io = IO.popen(argv, "r+")
        feed(io, lines)
        chosen = io.read
        io.close

        # fzf: 0 selected, 1 no match, 2 error, 130 interrupted. a selection
        # that came back empty counts as a cancel too - that pairs with the
        # finder exiting 0 the moment it is closed, before it has read anything
        return nil unless Process.last_status&.exitstatus&.zero?

        id = chosen.lines.first.to_s.split("\t", 2).first.to_s.strip
        id unless id.empty?
      rescue Errno::ENOENT, Interrupt
        # the binary went away between the PATH check and the spawn, or the
        # user interrupted booker itself rather than the finder
        nil
      end

      private

      # one write, not one per bookmark. IO.popen hands back a synced IO, so
      # `puts` per line is an unbuffered syscall each - measured 10x slower
      # than a single write at a few thousand bookmarks
      def feed(io, lines)
        io.write(lines.join("\n") + "\n") unless lines.empty?
        io.close_write
      rescue Errno::EPIPE
        # expected, not exceptional: the finder exits the instant escape is
        # pressed, and with a few hundred bookmarks booker is usually still
        # writing. the exit status above is what says what happened
      end
    end
  end
end
