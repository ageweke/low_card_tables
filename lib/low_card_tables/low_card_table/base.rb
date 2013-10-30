require 'active_support/concern'
require 'low_card_tables/low_card_table/cache_expiration/has_cache_expiration'
require 'low_card_tables/low_card_table/row_manager'

module LowCardTables
  module LowCardTable
    module Base
      extend ActiveSupport::Concern
      include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

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

      module ClassMethods
        def is_low_card_table?
          true
        end

        def reset_column_information
          super
          _low_card_row_manager.column_information_reset!
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

        def _low_card_value_column_names
          _low_card_row_manager.value_column_names
        end

        def _low_card_ensure_has_unique_index!(create_if_needed = false)
          _low_card_row_manager.ensure_has_unique_index!(create_if_needed)
        end

        def _low_card_remove_unique_index!
          _low_card_row_manager.remove_unique_index!
        end

        def _low_card_referred_to_by(referring_model_class)
          _low_card_row_manager.referred_to_by(referring_model_class)
        end

        [ :all_rows, :row_for_id, :rows_for_ids, :rows_matching, :ids_matching, :find_ids_for, :find_or_create_ids_for,
          :find_rows_for, :find_or_create_rows_for, :flush_cache!, :referring_models,
          :collapse_rows_and_update_referrers! ].each do |delegated_method_name|
          define_method("low_card_#{delegated_method_name}") do |*args|
            _low_card_row_manager.send(delegated_method_name, *args)
          end
        end
      end
    end
  end
end
