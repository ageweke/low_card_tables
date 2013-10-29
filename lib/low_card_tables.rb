require 'active_record'
require 'active_support'
require "low_card_tables/version"
require 'low_card_tables/active_record/base'
require 'low_card_tables/active_record/migrations'
require 'low_card_tables/low_card_table/cache_expiration/has_cache_expiration'

module LowCardTables
  include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

  low_card_cache_expiration :exponential
end

class ActiveRecord::Base
  include LowCardTables::ActiveRecord::Base
end

module ActiveRecord::ConnectionAdapters::SchemaStatements
  include LowCardTables::ActiveRecord::Migrations
end
