require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'
require 'low_card_tables/has_low_card_table/base'

module LowCardTables
  module ActiveRecord
    # This is a module that gets included into ActiveRecord::Base. It provides just the bootstrap
    # for LowCardTables: methods that let you declare #is_low_card_table or #has_low_card_table,
    # and see if it's a low-card table or not.
    module Base
      extend ActiveSupport::Concern
      include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

      module ClassMethods
        # Declares that this is a low-card table. This simply includes the LowCardTables::LowCardTable::Base
        # module, and then calls that module's is_low_card_table method, which is the one that does all
        # the real work.
        def is_low_card_table(options = { })
          unless @_low_card_is_low_card_table_included
            include LowCardTables::LowCardTable::Base
            @_low_card_is_low_card_table_included = true
          end

          is_low_card_table(options)
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

        def has_any_low_card_tables?
          false
        end
      end
    end
  end
end
