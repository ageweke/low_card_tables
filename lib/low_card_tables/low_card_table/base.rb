require 'active_support/concern'

module LowCardTables
  module LowCardTable
    module Base
      extend ActiveSupport::Concern

      included do

      end

      module ClassMethods
        def is_low_card_table?
          true
        end
      end
    end
  end
end
