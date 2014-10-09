module LowCardTables
  # Contains methods used by the codebase to support differing ActiveRecord versions. This is just a clean way of
  # factoring out differing ActiveRecord API into a single class.
  class VersionSupport
    class << self
      # Clear the schema cache for a given model.
      def clear_schema_cache!(model)
        if model.connection.respond_to?(:schema_cache)
          model.connection.schema_cache.clear!
        elsif model.connection.respond_to?(:clear_cache!)
          model.connection.clear_cache!
        end
      end

      # Can you specify a block on default_scope? This was added in ActiveRecord 3.1.
      def default_scopes_accept_a_block?
        ! (::ActiveRecord::VERSION::MAJOR <= 3 && ::ActiveRecord::VERSION::MINOR == 0)
      end

      # Is #migrate a class method, or an instance method, on ActiveRecord::Migration? It changed to an instance method
      # as of ActiveRecord 3.1.
      def migrate_is_a_class_method?
        (::ActiveRecord::VERSION::MAJOR <= 3 && ::ActiveRecord::VERSION::MINOR == 0)
      end

      def sti_uses_discriminate_class_for_record?
        ::ActiveRecord::VERSION::MAJOR >= 4
      end

      # Define a default scope on the class in question. This is only actually used from our specs.
      def define_default_scope(klass, conditions)
        if default_scopes_accept_a_block?
          if conditions
            klass.instance_eval %{
    default_scope { where(#{conditions.inspect}) }
}
          else
            klass.instance_eval %{
    default_scope { }
}
          end
        else
          if conditions
            klass.instance_eval %{
    default_scope where(#{conditions.inspect})
}
          else
            klass.instance_eval %{
    default_scope nil
}
          end
        end
      end
    end
  end
end
