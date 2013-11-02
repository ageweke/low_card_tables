module LowCardTables
  class VersionSupport
    class << self
      def clear_schema_cache!(model)
        if model.connection.respond_to?(:schema_cache)
          model.connection.schema_cache.clear!
        elsif model.connection.respond_to?(:clear_cache!)
          model.connection.clear_cache!
        end
      end

      def default_scopes_accept_a_block?
        ! (::ActiveRecord::VERSION::MAJOR <= 3 && ::ActiveRecord::VERSION::MINOR == 0)
      end

      def migrate_is_a_class_method?
        (::ActiveRecord::VERSION::MAJOR <= 3 && ::ActiveRecord::VERSION::MINOR == 0)
      end

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
