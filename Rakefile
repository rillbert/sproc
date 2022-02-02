require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

require 'rdoc/task'

RDoc::Task.new :rdoc do |rdoc|
  rdoc.main = "README.adoc"
  rdoc.rdoc_files.include("README.adoc", "lib/sproc/*.rb")
  rdoc.options << "--public"
end

task default: :test
