require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'
require 'low_card_tables/has_low_card_table/base'

module LowCardTables
  module ActiveRecord
    module Base
      extend ActiveSupport::Concern
      include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

      module ClassMethods
        def is_low_card_table(options = { })
          include LowCardTables::LowCardTable::Base
          self.low_card_options = options
        end

        def is_low_card_table?
          false
        end

        def has_low_card_table(*args)
          unless @_low_card_has_low_card_table_included
            include LowCardTables::HasLowCardTable::Base
            @_low_card_has_low_card_table_included = true
          end

          has_low_card_table(*args)
        end
      end
    end
  end
end
