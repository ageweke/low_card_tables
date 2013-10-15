module LowCardTables
  module LowCardTable
    module CacheExpiration
      class UnlimitedCacheExpirationPolicy
        def stale?(cache_time, current_time)
          false
        end
      end
    end
  end
end
