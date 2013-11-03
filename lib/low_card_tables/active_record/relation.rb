module LowCardTables
  module ActiveRecord
    # This module gets included into ::ActiveRecord::Relation, and is the reason that you can say, for example:
    #
    #    User.where(:deleted => false)
    #
    # ...when :deleted is actually an attribute on a referenced low-card table. It overrides #where to call
    # LowCardTables::HasLowCardTable::LowCardDynamicMethodManager#scope_from_query if this is a table that has any
    # associated low-card tables; that method, in turn, knows how to create a proper WHERE clause for low-card
    # attributes.
    module Relation
      # Overrides ::ActiveRecord::Relation#where to add support for low-card tables.
      def where(*args)
        # Escape early if this is a model that has nothing to do with any low-card tables.
        return super(*args) unless has_any_low_card_tables?

        if args.length == 1 && args[0].kind_of?(Hash)
          # This is a gross hack -- our overridden #where calls LowCardDynamicMethodManager#scope_from_query,
          # but that, in turn, needs to call #where, and we don't want an infinite mutual recursion. So, if we
          # see :_low_card_direct in the Hash passed in, we remove it and then go straight to the superclass --
          # i.e., this is the 'escape hatch' for LowCardDynamicMethodManager#scope_from_query.
          direct = args[0].delete(:_low_card_direct)

          if direct
            super(*args)
          else
            _low_card_dynamic_method_manager.scope_from_query(self, args[0])
          end
        else
          super(*args)
        end
      end
    end
  end
end
