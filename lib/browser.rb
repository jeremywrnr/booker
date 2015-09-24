# detect operating system

module OS
  def OS.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
  end

  def OS.mac?
    (/darwin/ =~ RUBY_PLATFORM) != nil
  end

  def OS.linux?
    not (OS.windows? or OS.mac?)
  end
end


# return browser (chrome) opening command

module Browser
  extend OS
  def get
    if OS.windows?
      '/cygdrive/c/Program\ Files\ \(x86\)/Google/Chrome/Application/chrome.exe '
    elsif OS.mac?
      'open -a "Google Chrome" '
    elsif OS.nix?
      'xdg-open ' # completely guessing here
    end
  end
end
