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

        def _low_card_row_manager
          @_low_card_row_manager ||= LowCardTables::LowCardTable::RowManager.new(self)
        end

        delegate :ids_matching, :find_ids_for, :find_or_create_ids_for, :to => :_low_card_row_manager
      end
    end
  end
end
