require 'rake'
require 'rspec/core/rake_task'

v="0.5.2"

task :default => :spec

task :dev do
  system "filewatcher '**/*.rb' 'clear && rake'"
end

task :clean do
  system "rm -v *.gem"
end

task :build do
  system "gem build booker.gemspec"
  system "gem install booker-#{v}.gem"
end

task :push => [:clean, :build] do
  system "gem push booker-#{v}.gem"
end

task :find do
  system 'echo "seaching for chrome bookmarks json..."'
  system 'find ~ -iname "*bookmarks" | grep -i chrom'
end

RSpec::Core::RakeTask.new(:spec) do |rt|
  rt.rspec_opts = '--format documentation'
  rt.verbose = true
end
