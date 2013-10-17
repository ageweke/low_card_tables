module LowCardTables
  module HasLowCardTable
    class LowCardObjectsManager
      def initialize(model_instance)
        @model_instance = model_instance
        @objects = { }
      end

      def object_for(association_name)
        association_name = association_name.to_s.strip.downcase
        @objects[association_name] ||= begin
          association = model_instance.class._low_card_associations_manager._low_card_association(association_name)
          association.create_low_card_object_for(model_instance)
        end
      end

      private
      attr_reader :model_instance
    end
  end
end
