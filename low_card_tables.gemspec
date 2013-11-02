# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "low_card_tables/version"

Gem::Specification.new do |s|
  s.name        = "low_card_tables"
  s.version     = LowCardTables::VERSION
  s.authors     = ["Andrew Geweke"]
  s.email       = ["andrew@geweke.org"]
  s.homepage    = "https://github.com/ageweke/low_card_tables"
  s.summary     = %q{Instead of storing multiple columns with low cardinality (few distinct values) directly in a table, which results in performance and maintainability problems, break them out into a separate table with almost zero overhead. Trivially add new columns without migrating a main, enormous table. Query on combinations of values very efficiently.}
  s.description = %q{Store low-cardinality columns in a separate table for vastly more flexibility and better performance.}
  s.license     = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "bundler"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", "~> 2.14"

  if RUBY_VERSION =~ /^1\.9\./ || RUBY_VERSION =~ /^2\.0\./
    s.add_development_dependency "pry"
    s.add_development_dependency "pry-debugger"
    s.add_development_dependency "pry-stack_explorer"
  end

  ar_version = ENV['LOW_CARD_TABLES_AR_TEST_VERSION']
  ar_version = ar_version.strip if ar_version

  version_spec = case ar_version
  when nil then [ ">= 3.0", "<= 4.99.99" ]
  when 'master' then nil
  else [ "=#{ar_version}" ]
  end

  if version_spec
    s.add_dependency("activerecord", *version_spec)
  end

  s.add_dependency "activesupport", ">= 3.0", "<= 4.99.99"

  ar_import_version = case ar_version
  when nil then nil
  when 'master', /^4\.0\./ then '~> 0.4.1'
  when /^3\.0\./ then '~> 0.2.11'
  when /^3\.1\./ then '~> 0.3.1'
  else raise "Don't know what activerecord-import version to require for activerecord version #{ar_version.inspect}!"
  end

  if ar_import_version
    s.add_dependency("activerecord-import", ar_import_version)
  else
    s.add_dependency("activerecord-import")
  end

  require File.expand_path(File.join(File.dirname(__FILE__), 'spec', 'low_card_tables', 'helpers', 'database_helper'))
  database_gem_name = LowCardTables::Helpers::DatabaseHelper.maybe_database_gem_name
  database_gem_version_spec = LowCardTables::Helpers::DatabaseHelper.maybe_database_gem_version_spec

  if database_gem_name
    if database_gem_version_spec
      s.add_development_dependency(database_gem_name, database_gem_version_spec)
    else
      s.add_development_dependency(database_gem_name)
    end
  end
end
