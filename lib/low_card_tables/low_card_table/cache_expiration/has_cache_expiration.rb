require File.join(File.dirname(__FILE__), 'exponential_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'fixed_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'unlimited_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'no_caching_expiration_policy')

module LowCardTables
  module LowCardTable
    module CacheExpiration
      # This is a module that gets mixed in to LowCardTables::LowCardTable::Base. It provides the class it gets mixed
      # into with a #low_card_cache_expiration method that can be called with various values (a number, zero, +:unlimited+,
      # or +:exponential+ with options) to set the cache-expiration policy, or called with no arguments to return the
      # cache-expiration policy as one of those same values.
      #
      # The value is stored on a class-by-class basis, and is inherited. This provides the behavior we want: if you set
      # a policy on LowCardTables::LowCardTable::Base, it will be applied to all low-card tables; if you set a policy
      # on an individual table, it will apply to only that table and will override any policy applied to the base.
      module HasCacheExpiration
        extend ActiveSupport::Concern

        module ClassMethods
          # Sets the cache-expiration policy of this class. You can pass:
          #
          # * A positive number -- sets the cache-expiration policy to be that many seconds.
          # * Zero -- turns off caching entirely.
          # * +:unlimited+ -- makes the cache last forever.
          # * :+exponential+, optionally with an options hash as the second argument -- sets the cache-expiration policy
          #   to be exponential; see ExponentialCacheExpirationPolicy for more details.
          #
          # If you pass no arguments at all, you're returned the current cache-expiration policy.
          #
          # If you do not call this method at all, the cache-expiration policy will be undefined. You should always either
          # call this method, or set up an inheritance chain using #low_card_cache_policy_inherits_from, to a class
          # that does have it defined.
          def low_card_cache_expiration(type_or_number = nil, options = { })
            if type_or_number.nil?
              @_low_card_cache_expiration_return_value || low_card_cache_expiration_inherited
            else
              if type_or_number == 0
                @_low_card_cache_expiration_policy_object = LowCardTables::LowCardTable::CacheExpiration::NoCachingExpirationPolicy.new
                @_low_card_cache_expiration_return_value = 0
              elsif type_or_number.kind_of?(Numeric)
                @_low_card_cache_expiration_policy_object = LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy.new(type_or_number)
                @_low_card_cache_expiration_return_value = type_or_number
              elsif type_or_number == :unlimited
                @_low_card_cache_expiration_policy_object = LowCardTables::LowCardTable::CacheExpiration::UnlimitedCacheExpirationPolicy.new
                @_low_card_cache_expiration_return_value = :unlimited
              elsif type_or_number == :exponential
                @_low_card_cache_expiration_policy_object = LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy.new(options.merge(:start_time => low_card_current_time))
                if options.size > 0
                  @_low_card_cache_expiration_return_value = [ :exponential, options ]
                else
                  @_low_card_cache_expiration_return_value = :exponential
                end
              else
                raise ArgumentError, "Invalid cache expiration time argumnet '#{type_or_number.inspect}'; you must pass a number, :unlimited, or :exponential."
              end
            end
          end

          # For +low_card_tables+ internal use only. Returns the current cache-expiration policy object -- e.g., an
          # instance of LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy.
          def low_card_cache_expiration_policy_object
            @_low_card_cache_expiration_policy_object || low_card_cache_expiration_policy_object_inherited
          end

          # Declares that this class should inherit its cache-expiration policy from the specified other class, which
          # must be a class that has had this module included in it (directly or indirectly) too. In other words, if
          # you don't set a policy on this class, but have specified that it inherits its policy from the given other
          # class, then it will use whatever policy the other class has set.
          #
          # We use this because low-card tables' classes all inherit directly from ::ActiveRecord::Base; they don't
          # inherit from some parent "it's a low-card table" class. (This is because inheritance in ActiveRecord is
          # used to denote data in common via STI, not what we're trying to do here.) So we use this to set up the
          # default policy directly on the ::LowCardTables root module, and 'inherit' it into individual low-card tables
          # (via the +included+ block on LowCardTables::LowCardTable::Base) this way.
          def low_card_cache_policy_inherits_from(other_class)
            @_low_card_cache_policy_inherits_from = other_class
          end

          private
          # We break this into a separate method simply for ease of testing -- some of our specs override it.
          def low_card_current_time
            Time.now
          end

          # Returns the proper return value for #low_card_cache_expiration from the 'inherited' class, if there is one.
          def low_card_cache_expiration_inherited
            @_low_card_cache_policy_inherits_from.low_card_cache_expiration if @_low_card_cache_policy_inherits_from
          end

          # Returns the proper return value for #low_card_cache_expiration_policy_object from the 'inherited' class,
          # if there is one.
          def low_card_cache_expiration_policy_object_inherited
            @_low_card_cache_policy_inherits_from.low_card_cache_expiration_policy_object if @_low_card_cache_policy_inherits_from
          end
        end
      end
    end
  end
end
