require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'

module LowCardTables
  module ActiveRecord
    module Base
      extend ActiveSupport::Concern

      module ClassMethods
        def is_low_card_table
          include LowCardTables::LowCardTable::Base
        end

        def is_low_card_table?
          false
        end
      end
    end
  end
end
