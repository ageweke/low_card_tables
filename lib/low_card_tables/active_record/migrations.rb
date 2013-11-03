require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'
require 'low_card_tables/has_low_card_table/base'

module LowCardTables
  module ActiveRecord
    module Migrations
      extend ActiveSupport::Concern

      def create_table_with_low_card_support(table_name, options = { }, &block)
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, options) do |new_options|
          create_table_without_low_card_support(table_name, new_options, &block)
        end
      end

      def add_column_with_low_card_support(table_name, column_name, type, options = {})
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, options) do |new_options|
          add_column_without_low_card_support(table_name, column_name, type, options)
        end
      end

      def remove_column_with_low_card_support(table_name, *column_names)
        options = column_names.pop if column_names[-1] && column_names[-1].kind_of?(Hash)
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, options) do |new_options|
          args = [ table_name ]
          args += column_names
          args << new_options if new_options && new_options.size > 0
          remove_column_without_low_card_support(*args)
        end
      end

      def change_table_with_low_card_support(table_name, options = { }, &block)
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, options) do |new_options|
          ar = method(:change_table_without_low_card_support).arity
          if ar > 1 || ar < -2
            change_table_without_low_card_support(table_name, new_options, &block)
          else
            change_table_without_low_card_support(table_name, &block)
          end
        end
      end

      def change_low_card_table(table_name, &block)
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, { :low_card => true }) do |new_options|
          block.call
        end
      end

      included do
        alias_method_chain :create_table, :low_card_support
        alias_method_chain :add_column, :low_card_support
        alias_method_chain :remove_column, :low_card_support
        alias_method_chain :change_table, :low_card_support
      end

      class << self
        def with_low_card_support(table_name, options = { }, &block)
          return block.call(options) if inside_migrations_check?

          (options, low_card_options) = partition_low_card_options(options)
          low_card_model = low_card_model_to_use_for(table_name, low_card_options)

          return block.call(options) if (! low_card_model)

          with_migrations_check do
            without_unique_index(low_card_model, low_card_options) do
              with_removed_column_detection(low_card_model, low_card_options) do
                block.call(options)
              end
            end
          end
        end

        private
        def inside_migrations_check?
          !! Thread.current[:_low_card_migrations_only_once]
        end

        def with_migrations_check(&block)
          begin
            Thread.current[:_low_card_migrations_only_once] = true
            block.call
          ensure
            Thread.current[:_low_card_migrations_only_once] = false
          end
        end

        def with_removed_column_detection(model, low_card_options, &block)
          previous_columns = fresh_value_column_names(model)

          begin
            block.call
          ensure
            LowCardTables::VersionSupport.clear_schema_cache!(model)
            model.reset_column_information
            new_columns = fresh_value_column_names(model)

            if (previous_columns - new_columns).length > 0
              model.low_card_collapse_rows_and_update_referrers!(low_card_options)
            end
          end
        end

        def without_unique_index(model, low_card_options, &block)
          begin
            model._low_card_remove_unique_index!
            block.call
          ensure
            model._low_card_ensure_has_unique_index!(true) unless low_card_options.has_key?(:low_card_collapse_rows) && (! low_card_options[:low_card_collapse_rows])
          end
        end

        def fresh_value_column_names(model)
          model.reset_column_information
          model._low_card_value_column_names
        end

        def partition_low_card_options(options)
          options = (options || { }).dup
          low_card_options = { }

          options.keys.each do |k|
            if k.to_s =~ /^low_card/
              low_card_options[k] = options.delete(k)
            end
          end

          [ options, low_card_options ]
        end

        def low_card_model_to_use_for(table_name, low_card_options)
          out = existing_low_card_model_for(table_name)
          out ||= temporary_model_class_for(table_name) if low_card_options[:low_card]
          out
        end

        def temporary_model_class_for(table_name)
          temporary_model_class = Class.new(::ActiveRecord::Base)
          temporary_model_class.table_name = table_name
          temporary_model_class.class_eval { is_low_card_table }
          temporary_model_class.reset_column_information
          temporary_model_class
        end

        def existing_low_card_model_for(table_name)
          # Make sure we load all models
          ::Rails.application.eager_load! if defined?(::Rails)
          out = ::ActiveRecord::Base.descendants.detect do |klass|
            klass.table_name.strip.downcase == table_name.to_s.strip.downcase &&
              klass.is_low_card_table? &&
              klass.name && klass.name.strip.length > 0
          end

          out
        end
      end
    end
  end
end
