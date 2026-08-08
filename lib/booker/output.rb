# terminal width, colored strings, and exiting with a message: the presentation
# helpers the rest of booker leans on

module Booker
  # int number of columns on screen. memoized rather than computed at load time
  # because it shells out to tput (~8ms), and the paths that run on every tab
  # press - --complete-raw - never need a width at all
  module Term
    def self.width
      @width ||= begin
        guess = `tput cols`.to_i
        (guess == 0) ? 100 : guess
      end
    end
  end

  # compl. color codes space
  CODEWIDTH = 16

  # print a message and stop. shared by the cli and the installer, both of which
  # report a failure and exit in the same breath
  module Output
    def pexit(msg, sig)
      puts msg
      exit sig
    end
  end
end

# Colors and windowing land on String itself rather than inside Booker: every
# format string in the gem reads as "Success: ".grn, and threading a helper
# object through for that would cost more than the global names save.
class String
  def window(width)
    if length >= width
      self[0..width - 1]
    else
      ljust(width)
    end
  end

  def colorize(color, mod)
    "\033[#{mod};#{color};49m#{self}\033[0;0m"
  end

  def reset
    colorize(0, 0)
  end

  def blu
    colorize(34, 0)
  end

  def cyan
    colorize(36, 0)
  end

  def yel
    colorize(33, 0)
  end

  def grn
    colorize(32, 0)
  end

  def red
    colorize(31, 0)
  end
end
