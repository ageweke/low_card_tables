module LowCardTables
  module HasLowCardTable
    class LowCardAssociation
      def initialize(model_class, association_name, options)
        @model_class = model_class
        @association_name = association_name.to_s
        @options = options

        install_methods!
      end

      def low_card_object(model_instance)
        ensure_correct_class!(model_instance)

      end

      private
      def install_methods!
        @model_class.class_eval(%{
  def #{@association_name}
    _low_card_association('#{@association_name}').low_card_object(self)
  end})
      end

      def ensure_correct_class!(model_instance)
        unless model_instance.kind_of?(@model_class)
          raise %{Whoa! The LowCardAssociation '#{@association_name}' for class #{@model_class} somehow
was passed a model of class #{model_instance.class} (model: #{model_instance}),
which is not of the correct class.}
        end
      end
    end
  end
end
