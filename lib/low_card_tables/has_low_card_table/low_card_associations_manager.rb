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
        @associations = nil

        install_methods!
      end

      def has_low_card_table(association_name, options = { })
        unless association_name.kind_of?(Symbol) || (association_name.kind_of?(String) && association_name.strip.length > 0)
          raise ArgumentError, "You must supply an association name, not: #{association_name.inspect}"
        end

        if @associations[association_name]
          raise LowCardTables::Errors::LowCardAssociationAlreadyExistsError, "There is already a low-card association named '#{association_name}' for #{@model_class.name}."
        end

        @associations[association_name] = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, association_name, options)
      end

      def _low_card_association(name)
        @association_name[name.to_s] || raise LowCardTables::Errors::LowCardAssociationNotFoundError, "There is no low-card association named '#{association_name}' for #{@model_class.name}."
      end

      def _low_card_update_values
        raise "nyi"
      end

      private
      def install_methods!
        @model_class.class_eval %{
  before_save :_low_card_update_values
}
      end
    end
  end
end
