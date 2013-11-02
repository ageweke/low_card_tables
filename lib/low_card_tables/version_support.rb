module LowCardTables
  class VersionSupport
    class << self
      def default_scopes_accept_a_block?
        ! (::ActiveRecord::VERSION::MAJOR <= 3 && ::ActiveRecord::VERSION::MINOR == 0)
      end

      def migrate_is_a_class_method?
        (::ActiveRecord::VERSION::MAJOR <= 3 && ::ActiveRecord::VERSION::MINOR == 0)
      end

      def mysql_gem_version_spec
        if (::ActiveRecord::VERSION::MAJOR <= 3 && ::ActiveRecord::VERSION::MINOR == 0)
          "~> 0.2"
        end
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
