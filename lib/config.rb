# configuation - get where local bookmarks are


require 'yaml'


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


module BookerConfig
  def BookerConfig.configure
    # Configure through yaml file
    yaml_config = ENV['HOME'] + '/.booker.yml'

    # Configuration defaults (for osx, default chrome profile)
    config = { :bookmarks => ENV['HOME'] + "/Library/Application Support/Google/Chrome/Profile 1/bookmarks" }
    valid = config.keys

    begin
      config = YAML::load(IO.read(yaml_config))
    rescue Errno::ENOENT
      puts "Warning: ".yel + "YAML configuration file couldn't be found. Using defaults."
      puts "Suggest: ".grn + "web --findbookmarks"
    rescue Psych::SyntaxError
      puts "Warning: ".red + "YAML configuration file contains invalid syntax. Using defaults."
    end

    config.each do |k,v|
      config[k.to_sym] = v if valid.include? k.to_sym
    end

    config
  end

  def BookerConfig.bookmarks
    BookerConfig.configure[:bookmarks]
  end
end
