require 'active_record'
require 'active_support'
require "low_card_tables/version"
require 'low_card_tables/active_record/base'
require 'low_card_tables/low_card_table/cache_expiration/has_cache_expiration'

module LowCardTables
  class << self
    include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

    self.cache_expiration = :exponential
  end
end

class ActiveRecord::Base
  include LowCardTables::ActiveRecord::Base
end
