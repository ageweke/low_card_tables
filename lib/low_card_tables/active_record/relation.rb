module LowCardTables
  module ActiveRecord
    module Relation
      def where(*args)
        return super(*args) unless has_any_low_card_tables?

        if args.length == 1 && args[0].kind_of?(Hash)
          # This is a gross hack -- our overridden #where calls LowCardDynamicMethodManager#scope_from_query,
          # but that, in turn, needs to call #where, and we don't want an infinite mutual recursion. So, if we
          # see :_low_card_direct in the Hash passed in, we remove it and then go straight to the superclass --
          # this is the 'escape hatch' for LowCardDynamicMethodManager#scope_from_query.
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
