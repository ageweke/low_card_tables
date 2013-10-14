source "http://rubygems.org"

# Specify your gem's dependencies in low_card_tables.gemspec
gemspec

rails_version = ENV['LOW_CARD_TABLES_RAILS_TEST_VERSION']
rails_version = rails_version.strip if rails_version

version_spec = case rails_version
when nil then nil
when 'master' then { :git => 'git://github.com/rails/rails.git' }
else "=#{rails_version}"
end

if version_spec
  gem("rails", version_spec)
end
