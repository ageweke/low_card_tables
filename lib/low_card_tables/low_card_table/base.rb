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
        # Declares that this is a low-card table. This should only ever be used on tables that are,
        # in fact, low-card tables.
        #
        # options can contain:
        #
        # [:exclude_column_names] Excludes the specified Array of column names from being treated
        #                         as low-card columns; this happens by default to created_at and
        #                         updated_at. These columns will not be touched by the low-card
        #                         code, meaning they have to be nullable or have defaults.
        # [:]
        def is_low_card_table(options = { })
          self.low_card_options = options
          _low_card_disable_save_when_needed!
        end

        def _low_card_disable_save_when_needed!
          send(:define_method, :save_low_card_row!) do |*args|
            begin
              @_low_card_saves_allowed = true
              save!(*args)
            ensure
              @_low_card_saves_allowed = false
            end
          end

          %w{save save!}.each do |method_name|
            send(:define_method, method_name) do |*args|
              if @_low_card_saves_allowed
                super(*args)
              else
                raise LowCardTables::Errors::LowCardCannotSaveAssociatedLowCardObjectsError, %{You just tried to save a model that represents a row in a low-card table.
You can't do this, because the entire low-card system relies on the fact that low-card rows
are immutable once created. Changing this row would therefore change the logical state of
many, many rows that are associated with this one, and that is almost certainly not what
you want.

Instead, simply modify the low-card attributes directly -- typically on the associated object
(e.g., my_user.deleted = true), or on the low-card object (my_user.status.deleted = true),
and then save the associated object instead (my_user.save!). This will trigger the low-card
system to recompute which low-card row the object should be associated with, and update it
as needed, which is almost certainly what you actually want.

If you are absolutely certain you know what you're doing, you can call #save_low_card_row!
on this object, and it will save, but make sure you understand ALL the implications first.}
              end
            end
          end
        end

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
          :collapse_rows_and_update_referrers!, :ensure_has_unique_index!, :remove_unique_index! ].each do |delegated_method_name|
          define_method("low_card_#{delegated_method_name}") do |*args|
            _low_card_row_manager.send(delegated_method_name, *args)
          end
        end
      end
    end
  end
end
