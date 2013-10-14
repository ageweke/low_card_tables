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
  s.add_development_dependency "rspec", "~> 2.1.4"

  rails_version = ENV['LOW_CARD_TABLES_RAILS_TEST_VERSION']
  rails_version = rails_version.strip if rails_version

  version_spec = case rails_version
  when nil then [ ">= 3.0", "<= 4.99.99" ]
  when 'master' then nil# { :git => 'git://github.com/rails/rails.git' }
  else [ "=#{rails_version}" ]
  end

  if version_spec
    spec.add_dependency("rails", *version_spec)
  end
end
