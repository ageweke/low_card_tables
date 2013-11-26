module LowCardTables
  module LowCardTable
    module CacheExpiration
      # This is a very simple cache-expiration policy that makes the cache last forever -- it will never be reloaded
      # from disk, unless you explicitly flush it.
      class UnlimitedCacheExpirationPolicy
        def stale?(cache_time, current_time)
          false
        end
      end
    end
  end
end
