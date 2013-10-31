module LowCardTables
  module HasLowCardTable
    class LowCardObjectsManager
      def initialize(model_instance)
        @model_instance = model_instance
        @objects = { }
      end

      def object_for(association)
        association_name = association.association_name.to_s.strip.downcase
        @objects[association_name] ||= begin
          association = model_instance.class._low_card_associations_manager._low_card_association(association_name)
          association.create_low_card_object_for(model_instance)
        end
      end

      def foreign_key_for(association)
        model_instance[association.foreign_key_column_name]
      end

      def set_foreign_key_for(association, new_value)
        model_instance[association.foreign_key_column_name] = new_value
        invalidate_object_for(association)
        new_value
      end

      private

      def invalidate_object_for(association)
        @objects.delete(association.association_name)
      end

      private
      attr_reader :model_instance
    end
  end
end
