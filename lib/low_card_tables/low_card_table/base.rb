require 'active_support/concern'
require 'low_card_tables/low_card_table/cache_expiration/has_cache_expiration'

module LowCardTables
  module LowCardTable
    module Base
      extend ActiveSupport::Concern
      include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

      def to_low_card_value_set
        LowCardTables::LowCardTable::ValueSet.new(self)
      end

      module ClassMethods
        def is_low_card_table?
          true
        end

        def low_card_options
          @_low_card_options ||= { }
        end

        def low_card_options=(options)
          @_low_card_options = options
        end
      end
    end
  end
end
