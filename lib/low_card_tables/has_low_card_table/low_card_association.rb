module LowCardTables
  module HasLowCardTable
    class LowCardAssociation
      def initialize(model_class, association_name, options)
        @model_class = model_class
        @association_name = association_name.to_s
        @options = options

        sync_installed_methods!

        # call a few methods that will raise errors if things are configured incorrectly;
        # we call them here so that you get those errors immediately, at startup, instead of
        # at some undetermined later point

        foreign_key_column_name
        low_card_class
      end

      def create_low_card_object_for(model_instance)
        ensure_correct_class!(model_instance)

        id = get_id_from_model(model_instance)

        out = nil
        if id
          template = low_card_class.low_card_row_for_id(get_id_from_model(model_instance))
          out = template.dup
          out.id = nil
          out
        else
          out = low_card_class.new
        end

        out
      end

      def update_value_before_save!(model_instance)
        hash = { }

        low_card_object = model_instance._low_card_objects_manager.object_for(association_name)

        low_card_class._low_card_value_column_names.each do |value_column_name|
          hash[value_column_name] = low_card_object[value_column_name]
        end

        new_id = low_card_class.low_card_find_or_create_ids_for(hash)

        unless get_id_from_model(model_instance) == new_id
          set_id_on_model(model_instance, new_id)
        end
      end

      private
      attr_reader :association_name, :options, :model_class

      def sync_installed_methods!
        # We create an anonymous module and include it, so that the class itself can properly override the
        # method and call 'super' if it wants.
        @methods_module ||= begin
          out = Module.new
          out.module_eval(%{
  def #{association_name}
    _low_card_objects_manager.object_for('#{association_name}')
  end

  def #{foreign_key_column_name}=(*args)
    out = super(*args)
    _low_card_objects_manager.invalidate_object_for('#{association_name}')
    out
  end})

          model_class.send(:include, out)
          out
        end

        @currently_installed_methods ||= [ ]

        desired_methods = low_card_class._low_card_value_column_names.map(&:to_s)
        methods_to_install = desired_methods - @currently_installed_methods
        methods_to_remove = @currently_installed_methods - desired_methods

        methods_to_remove.each do |method_to_remove|
          @methods_module.module_eval("remove_method :#{method_to_remove}")
          @methods_module.module_eval("remove_method :#{method_to_remove}=")
        end

        methods_to_install.each do |method_to_install|
          @methods_module.module_eval(%{
  def #{method_to_install}
    #{association_name}.#{method_to_install}
  end

  def #{method_to_install}=(x)
    #{association_name}.#{method_to_install} = x
  end
  })
          @currently_installed_methods << method_to_install
        end
      end

      def get_id_from_model(model_instance)
        model_instance[foreign_key_column_name]
      end

      def set_id_on_model(model_instance, new_id)
        model_instance[foreign_key_column_name] = new_id
      end

      def foreign_key_column_name
        @foreign_key_column_name ||= begin
          out = options[:foreign_key]

          unless out
            out = low_card_class.name.underscore
            out = $1 if out =~ %r{/[^/]+$}i
            out = out + "_id"
          end

          out = out.to_s if out.kind_of?(Symbol)

          column = model_class.columns.detect { |c| c.name.strip.downcase == out.strip.downcase }
          unless column
            raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name}, and we
have a foreign-key column name of #{out.inspect}, but #{model_class} doesn't seem
to have a column named that at all. Did you misspell it? Or perhaps something else is wrong?}
          end

          out
        end
      end

      def ensure_correct_class!(model_instance)
        unless model_instance.kind_of?(model_class)
          raise %{Whoa! The LowCardAssociation '#{association_name}' for class #{model_class} somehow
was passed a model of class #{model_instance.class} (model: #{model_instance}),
which is not of the correct class.}
        end
      end

      def low_card_class
        @low_card_class ||= begin
          # e.g., class User has_low_card_table :status => UserStatus
          out = options[:class] || "#{model_class.name.underscore.singularize}_#{association_name}"

          out = out.to_s if out.kind_of?(Symbol)
          out = out.camelize

          if out.kind_of?(String)
            begin
              out = out.constantize
            rescue NameError => ne
              raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name}, and we have a
:class of #{out.inspect}, but, when we tried to load that class (via #constantize),
we got a NameError. Perhaps you misspelled it, or something else is wrong?

NameError: (#{ne.class.name}): #{ne.message}}
            end
          end

          unless out.kind_of?(Class)
            raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name} with a
:class of #{out.inspect}, but that isn't a String or Symbol that represents a class,
or a valid Class object itself.}
          end

          unless out.respond_to?(:is_low_card_table?) && out.is_low_card_table?
            raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name},
and we have class #{out} for that low-card table (which is a Class), but it
either isn't an ActiveRecord model or, if so, it doesn't think it is a low-card
table itself (#is_low_card_table? returns false).

Perhaps you need to declare 'is_low_card_table' on that class?}
          end

          out
        end
      end
    end
  end
end
