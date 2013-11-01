module LowCardTables
  module ActiveRecord
    module Relation
      def where(*args)
        return super(*args) unless has_any_low_card_tables?

        if args.length == 1 && args[0].kind_of?(Hash)
          super(_low_card_dynamic_method_manager.low_card_constraints_from_query(args[0]))
        else
          super(*args)
        end
      end
    end
  end
end
