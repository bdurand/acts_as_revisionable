require 'rubygems'
require 'rake'

desc 'Default: run unit tests.'
task :default => :test

begin
  require 'rspec'
  require 'rspec/core/rake_task'
  desc 'Run the unit tests'
  RSpec::Core::RakeTask.new(:test)
rescue LoadError
  task :test do
    STDERR.puts "You must have rspec 2.0 installed to run the tests"
  end
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "acts_as_revisionable"
    gem.summary = %Q{ActiveRecord extension that provides revision support so that history can be tracked and changes can be reverted.}
    gem.description = %Q(ActiveRecord extension that provides revision support so that history can be tracked and changes can be reverted. Emphasis for this plugin versus similar ones is including associations, saving on storage, and extensibility of the model.)
    gem.email = "brian@embellishedvisions.com"
    gem.homepage = "http://github.com/bdurand/acts_as_revisionable"
    gem.authors = ["Brian Durand"]
    gem.files = FileList["lib/**/*", "spec/**/*", "README.rdoc", "Rakefile", "MIT-LICENSE"].to_a
    gem.has_rdoc = true
    gem.extra_rdoc_files = ["README.rdoc", "MIT_LICENSE"]
    
    gem.add_dependency('activerecord', '>= 2.3.9')
    gem.add_development_dependency('composite_primary_keys')
    gem.add_development_dependency('sqlite3')
    gem.add_development_dependency('rspec', '>= 2.0.0')
    gem.add_development_dependency('jeweler')
  end

  Jeweler::GemcutterTasks.new
rescue LoadError
end
