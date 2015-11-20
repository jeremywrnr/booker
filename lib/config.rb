# configuation - get where bookmarks are


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
      # alternatively, start seems to work - probably check if powershell v cygwin?
      '/cygdrive/c/Program\ Files\ \(x86\)/Google/Chrome/Application/chrome.exe '
    elsif OS.mac?
      'open -a "Google Chrome" '
    elsif OS.linux?
      'xdg-open ' # completely guessing here
    end
  end

  def domain
    /.*(io|com|web|net|org|gov|edu)(\/.*)?$/i
  end

  # helper methods
  def prep(url)
    if /^http/.match(url)
      url
    else
      'http://' + url
    end
  end

  def wrap(url)
    "'" + url + "'"
  end
end


# configuration
class BConfig
  VALID = [:searcher, :bookmarks, :browser]
  HOME = ENV['HOME'].nil?? '/usr/local/' : ENV['HOME']
  YAMLCONF = HOME + '/.booker.yml'

  def initialize
    # config defaults (for osx, default chrome profile)
    readyaml = read(YAMLCONF)
    default_config = {
      :browser  => 'open ',
      :searcher  => "https://duckduckgo.com/?q=",
      :bookmarks => HOME +
      "/Library/Application Support/Google/Chrome/Profile 1/Bookmarks",
    }

    # configure w/ yaml config file, if it exists
    @config = readyaml ? readyaml : default_config

    # prune bad config keys
    @config.each do |k, v|
      if !VALID.include? k.to_sym
        puts "Failure:".red + " Bad key found in config file: #{k}"
        exit 1
      end
    end
  end

  def read(file)
    begin
      config = YAML::load(IO.read(file))
    rescue Errno::ENOENT
      puts "Warning: ".yel +
        "YAML configuration file couldn't be found. Using defaults."
      puts "Suggest: ".grn + "web --install config"
      return false
    rescue Psych::SyntaxError
      puts "Warning: ".red +
        "YAML configuration file contains invalid syntax. Using defaults."
      return false
    end
    config
  end

  # used for creating and updating the default configuration
  def write(k=nil, v=nil)
    if k.nil? && v.nil?
      File.open(YAMLCONF, 'w') {|f| f.write(@config.to_yaml) }
    else
      @config[k] = v # update users yaml config file
      File.open(YAMLCONF, 'w+') {|f| f.write(@config.to_yaml) }
    end
  end

  def bookmarks
    @config[:bookmarks]
  end

  def searcher
    @config[:searcher]
  end
end
