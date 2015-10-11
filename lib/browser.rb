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
  def browse
    if OS.windows?
      '/cygdrive/c/Program\ Files\ \(x86\)/Google/Chrome/Application/chrome.exe '
    elsif OS.mac?
      'open -a "Google Chrome" '
    elsif OS.linix?
      'xdg-open ' # completely guessing here
    end
  end

  def domain
    /.*(io|com|web|net|org|gov|edu)$/i
  end

  def search
    #"https://www.google.com/search?q="
    #"http://www.bing.com/search?q=" #lol
    "https://duckduckgo.com/?q="
  end

  # helper methods

  def prep(url)
    if /^http/.match(url)
      url
    else
      'http://' << url
    end
  end

  def wrap(url)
    "'" + url + "'"
  end
end
