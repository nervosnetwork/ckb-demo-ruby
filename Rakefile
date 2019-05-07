require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

task :console do
  require "pry"
  require_relative "lib/ckb/wallet"
  Pry.start
end

task c: :console
