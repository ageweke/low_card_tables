module LowCardTables
  module LowCardTable
    module CacheExpiration
      class NoCachingExpirationPolicy
        def stale?(cache_time, current_time)
          true
        end
      end
    end
  end
end
