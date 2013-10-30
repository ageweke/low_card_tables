require 'active_support/concern'
require 'low_card_tables/has_low_card_table/low_card_associations_manager'
require 'low_card_tables/has_low_card_table/low_card_objects_manager'

module LowCardTables
  module HasLowCardTable
    module Base
      extend ActiveSupport::Concern

      module ClassMethods
        delegate :has_low_card_table, :to => :_low_card_associations_manager

        def _low_card_associations_manager
          @_low_card_associations_manager ||= LowCardTables::HasLowCardTable::LowCardAssociationsManager.new(self)
        end

        def _low_card_association(name)
          _low_card_associations_manager._low_card_association(name)
        end

        def _low_card_update_collapsed_rows(low_card_model, collapse_map)
          _low_card_associations_manager._low_card_update_collapsed_rows(low_card_model, collapse_map)
        end

        def low_card_value_collapsing_update_scheme(new_scheme = nil)
          _low_card_associations_manager.low_card_value_collapsing_update_scheme(new_scheme)
        end
      end

      def low_card_update_foreign_keys!
        self.class._low_card_associations_manager.low_card_update_foreign_keys!(self)
      end

      def _low_card_objects_manager
        @_low_card_objects_manager ||= LowCardTables::HasLowCardTable::LowCardObjectsManager.new(self)
      end
    end
  end
end
