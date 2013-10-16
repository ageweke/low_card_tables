require 'active_support/concern'
require 'low_card_tables/low_card_table/cache_expiration/has_cache_expiration'

module LowCardTables
  module LowCardTable
    module Base
      extend ActiveSupport::Concern
      include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

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

        def _low_card_row_matches_any_hash?(hashes)
          hashes.detect { |hash| _low_card_row_matches_hash?(hash) }
        end

        def _low_card_row_matches_hash?(hash)
          hash.keys.all? { |key| _low_card_column_matches?(key, hash[key]) }
        end

        def _low_card_column_matches?(key, value)
          self[key.to_s] == value
        end

        def _low_card_row_matches_block?(block)
          block.call(self)
        end

        delegate :ids_matching, :find_ids_for, :find_or_create_ids_for, :to => :_low_card_row_manager
      end
    end
  end
end
