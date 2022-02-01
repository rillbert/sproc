require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

Rake::TestTask.new(:rdoc) do |t|
  `rdoc --main README.adoc -x 'test' -x 'Gemfile*' -x 'Rakefile' -x 'bin/'`
end

task default: :test
