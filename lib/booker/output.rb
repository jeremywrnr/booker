# frozen_string_literal: true

# terminal width, colored strings, and exiting with a message: the presentation
# helpers the rest of booker leans on

require "io/console"

module Booker
  # int number of columns on screen. io/console answers from this process, so
  # there is no `tput cols` subshell to pay for on every run. it reads /dev/tty
  # rather than stdout, so a width still comes back through a pipe, and it
  # returns nil when there is no terminal at all - a completion subshell, or ci
  module Term
    def self.width
      @width ||= IO.console&.winsize&.last&.nonzero? ||
        ENV["COLUMNS"]&.to_i&.nonzero? ||
        100
    end
  end

  # compl. color codes space
  CODEWIDTH = 16

  # print a message and stop. shared by the cli and the installer, both of which
  # report a failure and exit in the same breath. the message goes to stderr:
  # every caller is reporting a failure, and stdout is a data channel for the
  # completion scripts
  module Output
    def pexit(msg, sig = 1)
      warn msg
      exit sig
    end
  end

  # Colors and windowing still read as "Success: ".grn at every call site, but
  # as a refinement rather than an open class: a gem that claims String#red for
  # the whole process is taking a name it does not own. Files that want these
  # say `using Booker::Colors` at the top, and nothing outside booker sees them.
  module Colors
    CODES = {red: 31, grn: 32, yel: 33, blu: 34, cyan: 36}.freeze

    class << self
      # nil means decide per call from the environment; true or false forces it,
      # which is what the specs do since their $stdout is never a terminal
      attr_writer :enabled

      # honor NO_COLOR (no-color.org), and skip the escapes when stdout is not a
      # terminal - otherwise `booker > out.txt` and `booker | less` fill up with
      # raw \033[ sequences
      def enabled?
        return @enabled unless @enabled.nil?

        ENV["NO_COLOR"].to_s.empty? && $stdout.tty?
      end

      # color by name, reachable without the refinement. a caller holding the
      # color as data - the browser table's :yel, say - cannot go through the
      # refined methods, because refinements are invisible to send
      def paint(str, name)
        return str unless enabled?

        "\033[0;#{CODES.fetch(name)};49m#{str}\033[0;0m"
      end
    end

    refine String do
      def window(width)
        if length >= width
          self[0..width - 1]
        else
          ljust(width)
        end
      end

      def blu = Colors.paint(self, :blu)

      def cyan = Colors.paint(self, :cyan)

      def yel = Colors.paint(self, :yel)

      def grn = Colors.paint(self, :grn)

      def red = Colors.paint(self, :red)
    end
  end
end
