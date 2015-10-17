# configuation - get where local bookmarks are


# thx danhassin
class String
  def colorize(color, mod)
    "\033[#{mod};#{color};49m#{self}\033[0;0m"
  end

  def reset() colorize(0,0) end
  def blu() colorize(34,0) end
  def yel() colorize(33,0) end
  def grn() colorize(32,0) end
  def red() colorize(31,0) end
end


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
    elsif OS.linux?
      'xdg-open ' # completely guessing here
    end
  end

  def domain
    /.*(io|com|web|net|org|gov|edu)$/i
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


# high level configuration
class BConfig
  def initialize
    # config defaults (for osx, default chrome profile)
    @config = {
      :searcher  => "https://duckduckgo.com/?q=",
      :bookmarks => ENV['HOME'] +
      "/Library/Application Support/Google/Chrome/Profile 1/Bookmarks",
    }

    # configure through users yaml config file
    yaml_config = ENV['HOME'] + '/.booker.yml'

    begin
      @config = YAML::load(IO.read(yaml_config))
    rescue Errno::ENOENT
      puts "Warning: ".yel +
        "YAML configuration file couldn't be found. Using defaults."
      puts "Suggest: ".grn +
        "web --install config"
    rescue Psych::SyntaxError
      puts "Warning: ".red +
        "YAML configuration file contains invalid syntax. Using defaults."
    end

    valid = @config.keys
    @config.each do |k,v|
      @config[k.to_sym] = v if valid.include? k.to_sym
    end
  end

  def bookmarks
    @config[:bookmarks]
  end

  def searcher
    @config[:searcher]
  end
end
