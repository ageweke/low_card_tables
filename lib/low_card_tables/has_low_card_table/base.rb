require 'active_support/concern'

module LowCardTables
  module HasLowCardTable
    module Base
      extend ActiveSupport::Concern

      module ClassMethods
        delegate :has_low_card_table, :to => :_low_card_associations_manager

        def _low_card_associations_manager
          @_low_card_associations_manager ||= LowCardTables::HasLowCardTable::LowCardAssociationsManager.new(self)
        end
      end
    end
  end
end
