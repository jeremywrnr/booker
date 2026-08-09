# frozen_string_literal: true

# an external fuzzy finder (fzf by default) as booker's selection ui: candidate
# lines in on stdin, the chosen one back on stdout, with the finder opening
# /dev/tty itself for the interface. it knows nothing about bookmarks - lines
# in, first tab separated field out - which keeps it testable against `head`
# and `cat` rather than against a real finder.

require "shellwords"

module Booker
  module Picker
    # --delimiter/--with-nth hide the id column: it is noise on screen, and
    # hiding it also takes it out of the match, so typing "2_" does not pull up
    # every bookmark from the second source. --no-sort keeps booker's ordering.
    #
    # deliberately no --multi: under it fzf reads tab as "mark this and move
    # down" - the one key booker's own completion trained everybody to press -
    # so a couple of taps to scroll would mark bookmarks silently and open them
    # all on the next return.
    #
    # a plain array literal, not %w[]: neither the real tab in the delimiter nor
    # the prompt's trailing space survives %w[]
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

      # #enabled? and #select both ask for the command, so an interactive run
      # worked it out twice; both memos outlive an example, so the suite drops
      # them between them
      def reset!
        @enabled = nil
        @command = nil
        @command_known = false
      end

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
        return @command if @command_known

        @command_known = true
        @command = resolve_command
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

      # candidates in, the id of what was picked out - or nil for every other
      # outcome: cancelled, nothing matched, no usable finder. one id and not a
      # list, since dropping --multi above only covers the default finder and
      # not one named in ~/.booker.yml
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

      def resolve_command
        configured = Config.default.picker

        # yaml reads a bare `:picker: false` as the boolean, and that means
        # "leave the picker off" - otherwise it looks like nothing was
        # configured and quietly starts fzf instead. blank says the same thing
        return nil if configured == false

        argv = configured ? Shellwords.split(configured.to_s) : DEFAULT
        (!argv.empty? && which(argv.first)) ? argv : nil
      end

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
