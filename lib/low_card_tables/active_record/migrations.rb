require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'
require 'low_card_tables/has_low_card_table/base'

module LowCardTables
  module ActiveRecord
    module Migrations
      extend ActiveSupport::Concern

      def create_table_with_low_card_support(table_name, options = { }, &block)
        ::LowCardTables::ActiveRecord::Migrations.verify_unique_index_as_needed(table_name, options) do |new_options|
          create_table_without_low_card_support(table_name, new_options, &block)
        end
      end

      def add_column_with_low_card_support(table_name, column_name, type, options = {})
        ::LowCardTables::ActiveRecord::Migrations.verify_unique_index_as_needed(table_name, options) do |new_options|
          add_column_without_low_card_support(table_name, column_name, type, options)
        end
      end

      def remove_column_with_low_card_support(table_name, *column_names)
        options = column_names.pop if column_names[-1] && column_names[-1].kind_of?(Hash)
        ::LowCardTables::ActiveRecord::Migrations.verify_unique_index_as_needed(table_name, options) do |new_options|
          remove_column_without_low_card_support(table_name, *column_names)
        end
      end

      def change_table_with_low_card_support(table_name, options = { }, &block)
        ::LowCardTables::ActiveRecord::Migrations.verify_unique_index_as_needed(table_name, options) do |new_options|
          change_table_without_low_card_support(table_name, new_options, &block)
        end
      end

      def change_low_card_table(table_name, &block)
        ::LowCardTables::ActiveRecord::Migrations.verify_unique_index_as_needed(table_name, { :low_card => true }) do |new_options|
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
        def verify_unique_index_as_needed(table_name, options = { }, &block)
          return block.call(options) if Thread.current[:_low_card_in_verify_unique_index_as_needed]

          Thread.current[:_low_card_in_verify_unique_index_as_needed] = true
          begin
            options = (options || { }).dup

            low_card_options = { }
            options.keys.each do |k|
              low_card_options[k] = options.delete(k) if k.to_s =~ /^low_card/
            end

            low_card_model = existing_low_card_model_for(table_name)

            model_class_to_use = low_card_model || temporary_model_class_for(table_name)
            is_low_card = (low_card_options[:low_card] || low_card_model)

            model_class_to_use.reset_column_information
            previous_columns = model_class_to_use._low_card_value_column_names

            begin
              model_class_to_use._low_card_remove_unique_index! if is_low_card
              result = block.call(options)
            ensure
              if is_low_card
                model_class_to_use.connection.schema_cache.clear!
                model_class_to_use.reset_column_information
                new_columns = model_class_to_use._low_card_value_column_names

                if (previous_columns - new_columns).length > 0
                  model_class_to_use.low_card_collapse_rows_and_update_referrers!(low_card_options)
                end

                unless low_card_options.has_key?(:low_card_collapse_rows) && (! low_card_options[:low_card_collapse_rows])
                  model_class_to_use._low_card_ensure_has_unique_index!(true)
                end
              end
            end

            result
          ensure
            Thread.current[:_low_card_in_verify_unique_index_as_needed] = false
          end
        end

        private
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
