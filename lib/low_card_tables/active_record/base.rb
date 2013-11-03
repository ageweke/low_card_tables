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
        # Declares that this is a low-card table. This should only ever be used on tables that are,
        # in fact, low-card tables.
        #
        # options can contain:
        #
        # [:exclude_column_names] Excludes the specified Array of column names from being treated
        #                         as low-card columns; this happens by default to created_at and
        #                         updated_at.
        def is_low_card_table(options = { })
          include LowCardTables::LowCardTable::Base
          self.low_card_options = options
          _low_card_disable_save_when_needed!
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
