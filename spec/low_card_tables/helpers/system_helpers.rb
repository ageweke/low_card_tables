require 'active_record'
require 'active_record/migration'

module LowCardTables
  module Helpers
    module SystemHelpers
      def migrate(&block)
        migration_class = Class.new(::ActiveRecord::Migration)
        metaclass = migration_class.class_eval { class << self; self; end }
        metaclass.instance_eval { define_method(:up, &block) }

        ::ActiveRecord::Migration.suppress_messages do
          migration_class.migrate(:up)
        end

        LowCardTables::VersionSupport.clear_schema_cache!(::ActiveRecord::Base)
      end

      def define_model_class(name, table_name, options = { }, &block)
        superclass = options[:superclass] || ::ActiveRecord::Base
        model_class = Class.new(superclass)
        ::Object.send(:remove_const, name) if ::Object.const_defined?(name)
        ::Object.const_set(name, model_class)
        model_class.table_name = table_name if table_name
        model_class.class_eval(&block) if block
      end

      def create_standard_system_spec_tables!
        migrate do
          drop_table :lctables_spec_user_statuses rescue nil
          create_table :lctables_spec_user_statuses do |t|
            t.boolean :deleted, :null => false
            t.boolean :deceased
            t.string :gender, :null => false
            t.integer :donation_level
          end

          add_index :lctables_spec_user_statuses, [ :deleted, :deceased, :gender, :donation_level ], :unique => true, :name => 'index_lctables_spec_user_statuses_on_all'

          drop_table :lctables_spec_users rescue nil
          create_table :lctables_spec_users do |t|
            t.string :name, :null => false
            t.integer :user_status_id, :null => false, :limit => 2
          end
        end
      end

      def create_standard_system_spec_models!
        define_model_class(:UserStatus, 'lctables_spec_user_statuses') { is_low_card_table }
        define_model_class(:User, 'lctables_spec_users') { has_low_card_table :status }
        define_model_class(:UserStatusBackdoor, 'lctables_spec_user_statuses') { }

        ::UserStatus.low_card_cache_expiration :unlimited
      end

      def drop_standard_system_spec_tables!
        migrate do
          drop_table :lctables_spec_user_statuses rescue nil
          drop_table :lctables_spec_users rescue nil
        end
      end
    end
  end
end
