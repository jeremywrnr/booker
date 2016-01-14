require 'rake'
require 'rspec/core/rake_task'

task :default => :spec
RSpec::Core::RakeTask.new(:spec) do |rt|
  #rt.rspec_opts = '--format documentation'
  rt.verbose = true
end

task :dev do
  system "filewatcher '**/*.rb' 'clear && rake'"
end

