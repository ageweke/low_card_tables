module LowCardTables
  module HasLowCardTable
    class LowCardAssociationsManager
      def initialize(model_class)
        if (! model_class.kind_of?(ActiveRecord::Base))
          raise ArgumentError, "You must supply an ActiveRecord model, not: #{model_class}"
        elsif model_class.is_low_card_table?
          raise ArgumentError, "A low-card table can't itself have low-card associations: #{model_class}"
        end

        @model_class = model_class
      end

      def has_low_card_table(low_card_table_or_model_name)
        # User
        #   has_low_card_table :display_status

        #       - has_one :display_status
        #         - @association_name:

        # undefine methods: <x>, <x>=, build_<x>, create_<x>, create_<x>!
      end
    end
  end
end
