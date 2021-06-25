require 'rake'
require 'rspec/core/rake_task'
require_relative "lib/booker.rb"

task :default => :spec

task :dev do
  system "filewatcher '**/*.rb' 'clear && rake'"
end

task :clean do
  system "rm -v *.gem"
end

task :build do
  system "gem build booker.gemspec"
  system "gem install booker-#{Booker.version}.gem"
end

task :push => [:clean, :build] do
  system "gem push booker-#{Booker.version}.gem"
end

task :find do
  system 'echo "seaching for chrome bookmarks json..."'
  system 'find ~ -iname "*bookmarks" | grep -i chrom'
end

RSpec::Core::RakeTask.new(:spec) do |rt|
  rt.rspec_opts = '--color --format documentation'
  rt.verbose = true
end
