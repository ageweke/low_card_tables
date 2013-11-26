module LowCardTables
  module LowCardTable
    module CacheExpiration
      # This is a very simple cache-expiration policy that disables caching entirely -- it makes the cache always
      # stale, which means we will reload it from the database every single time.
      class NoCachingExpirationPolicy
        def stale?(cache_time, current_time)
          true
        end
      end
    end
  end
end
