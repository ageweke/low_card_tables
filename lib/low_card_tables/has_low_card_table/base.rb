require 'active_support/concern'
require 'low_card_tables/has_low_card_table/low_card_associations_manager'

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
      end

      def _low_card_update_values
        _low_card_associations_manager._low_card_update_values(self)
      end
    end
  end
end
