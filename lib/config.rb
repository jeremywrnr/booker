require 'yaml'
require 'logger'

module Config
  # Configure through yaml file
  def Config.configure

    # Configuration defaults
    config = {
      :bookmarks => "/Library/Application Support/Google/Chrome/Profile 1/bookmarks"
    }

    valid = config.keys
    yaml_config = ENV['HOME'] + '/.booker.yml'

    begin
      log =Logger.new(STDOUT)
      config = YAML::load(IO.read(yaml_config))
    rescue Errno::ENOENT
      log.warn("YAML configuration file couldn't be found. Using defaults.")
    rescue Psych::SyntaxError
      log.warn("YAML configuration file contains invalid syntax. Using defaults.")
    end

    config.each do |k,v|
      config[k.to_sym] = v if valid.include? k.to_sym
    end

    p config
    config
  end

  def Config.bookmarks
    Config.configure[:bookmarks]
  end
end
