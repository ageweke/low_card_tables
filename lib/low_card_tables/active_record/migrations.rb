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

      included do
        alias_method_chain :create_table, :low_card_support
        alias_method_chain :add_column, :low_card_support
      end

      class << self
        def verify_unique_index_as_needed(table_name, options = { }, &block)
          options = (options || { }).dup
          low_card_option = options.delete(:low_card)

          result = block.call(options)

          if low_card_option || model_exists_declaring_as_low_card?(table_name)
            temporary_model_class_for(table_name)._low_card_ensure_has_unique_index!(true)
          end

          result
        end

        private
        def temporary_model_class_for(table_name)
          temporary_model_class = Class.new(::ActiveRecord::Base)
          temporary_model_class.table_name = table_name
          temporary_model_class.class_eval { is_low_card_table }
          temporary_model_class.reset_column_information
          temporary_model_class
        end

        def model_exists_declaring_as_low_card?(table_name)
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
