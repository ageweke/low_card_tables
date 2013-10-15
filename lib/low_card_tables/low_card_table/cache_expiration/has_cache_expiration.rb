require File.join(File.dirname(__FILE__), 'exponential_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'fixed_cache_expiration_policy')
require File.join(File.dirname(__FILE__), 'unlimited_cache_expiration_policy')

module LowCardTables
  module LowCardTable
    module CacheExpiration
      module HasCacheExpiration
        extend ActiveSupport::Concern

        module ClassMethods
          def cache_expiration=(type_or_number, options = { })
            @_cache_expiration_policy_object = if type_or_number.kind_of?(Numeric)
              LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy.new(type_or_number)
              @_cache_expiration_return_value = type_or_number
            elsif type_or_number == :unlimited
              LowCardTables::LowCardTable::CacheExpiration::UnlimitedCacheExpirationPolicy.new(type_or_number)
              @_cache_expiration_return_value = :unlimited
            elsif type_or_number == :exponential
              LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy.new(options)
              @_cache_expiration_return_value = [ :exponential, :options ]
            else
              raise ArgumentError, "Invalid cache expiration time argumnet '#{type_or_number.inspect}'; you must pass a number, :unlimited, or :exponential."
            end
          end

          def cache_expiration
            @_cache_expiration_return_value
          end

          private
          def cache_expiration_policy_object
            @_cache_expiration_policy_object
          end
        end
      end
    end
  end
end
