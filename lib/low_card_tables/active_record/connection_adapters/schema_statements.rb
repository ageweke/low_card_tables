require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'
require 'low_card_tables/has_low_card_table/base'

module LowCardTables
  module ActiveRecord
    module ConnectionAdapters
      module SchemaStatements
        extend ActiveSupport::Concern

        def create_table_with_low_card_support(table_name, options = { }, &block)
          result = create_table_without_low_card_support(table_name, options, &block)

          if (options && options[:low_card]) || ::LowCardTables::ActiveRecord::ConnectionAdapters::SchemaStatements._low_card_model_exists_declaring_as_low_card?(table_name)
            temporary_model_class = Class.new(::ActiveRecord::Base)
            temporary_model_class.table_name = table_name
            temporary_model_class.class_eval { is_low_card_table }
            temporary_model_class._low_card_ensure_has_unique_index!(true)
          end

          result
        end

        class << self
          def _low_card_model_exists_declaring_as_low_card?(table_name)
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

        included do
          alias_method_chain :create_table, :low_card_support
        end
      end
    end
  end
end
