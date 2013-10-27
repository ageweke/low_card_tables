require File.join(File.dirname(__FILE__), 'exponential_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'fixed_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'unlimited_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'no_caching_expiration_policy')

module LowCardTables
  module LowCardTable
    module CacheExpiration
      module HasCacheExpiration
        extend ActiveSupport::Concern

        module ClassMethods
          def low_card_cache_expiration=(type_or_number, options = { })
            @_low_card_cache_expiration_policy_object = if type_or_number == 0
              @_low_card_cache_expiration_return_value = 0
              LowCardTables::LowCardTable::CacheExpiration::NoCachingExpirationPolicy.new
            elsif type_or_number.kind_of?(Numeric)
              @_low_card_cache_expiration_return_value = type_or_number
              LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy.new(type_or_number)
            elsif type_or_number == :unlimited
              @_low_card_cache_expiration_return_value = :unlimited
              LowCardTables::LowCardTable::CacheExpiration::UnlimitedCacheExpirationPolicy.new
            elsif type_or_number == :exponential
              @_low_card_cache_expiration_return_value = [ :exponential, :options ]
              LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy.new(options)
            else
              raise ArgumentError, "Invalid cache expiration time argumnet '#{type_or_number.inspect}'; you must pass a number, :unlimited, or :exponential."
            end
          end

          def low_card_cache_expiration
            @_low_card_cache_expiration_return_value
          end

          def low_card_cache_expiration_policy_object
            @_low_card_cache_expiration_policy_object
          end
        end
      end
    end
  end
end
