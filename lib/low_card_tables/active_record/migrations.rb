require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'
require 'low_card_tables/has_low_card_table/base'

module LowCardTables
  module ActiveRecord
    # This module gets included into ::ActiveRecord::Migrations, and overrides key methods (using +alias_method_chain+)
    # to add low-card support. Its job is to detect if a low-card table is being modified, and, if so:
    #
    # * Remove the all-columns unique index before the operation in question, and add it back afterwards
    # * If a column has been removed, collapse any now-duplicate rows in question and update all referring tables
    #
    # It also adds a single method to migrations, #change_low_card_table, which does nothing of its own rather than
    # to call the passed block -- but it does all the checking above at the start and end, and disables any such
    # checking within the block. It thus gives you control over exactly when this happens.
    module Migrations
      extend ActiveSupport::Concern

      # Overrides ::ActiveRecord::Migrations#create_table with low-cardinality support, as described in the comment
      # for LowCardTables::ActiveRecord::Migrations.
      def create_table_with_low_card_support(table_name, options = { }, &block)
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, options) do |new_options|
          create_table_without_low_card_support(table_name, new_options, &block)
        end
      end

      # Overrides ::ActiveRecord::Migrations#add_column with low-cardinality support, as described in the comment
      # for LowCardTables::ActiveRecord::Migrations.
      def add_column_with_low_card_support(table_name, column_name, type, options = {})
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, options) do |new_options|
          add_column_without_low_card_support(table_name, column_name, type, options)
        end
      end

      # Overrides ::ActiveRecord::Migrations#remove_column with low-cardinality support, as described in the comment
      # for LowCardTables::ActiveRecord::Migrations.
      def remove_column_with_low_card_support(table_name, *column_names)
        options = column_names.pop if column_names[-1] && column_names[-1].kind_of?(Hash)
        ::LowCardTables::ActiveRecord::Migrations.with_low_card_support(table_name, options) do |new_options|
          args = [ table_name ]
          args += column_names
          args << new_options if new_options && new_options.size > 0
          remove_column_without_low_card_support(*args)
        end
      end

      # Overrides ::ActiveRecord::Migrations#change_table with low-cardinality support, as described in the comment
      # for LowCardTables::ActiveRecord::Migrations.
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

      # Given the name of a low-card table and a block:
      #
      # * Removes the all-columns unique index for that low-card table;
      # * Calls the block;
      # * Looks for any removed columns, and, if so, collapses now-duplicate rows and updates all referrers;
      # * Creates the all-columns unique index for that table.
      #
      # While inside the block, none of the above checking will be performed against that table, as it otherwise would
      # be if you call #add_column, #remove_column, #create_table, or #change_table. This thus gives you a scope in
      # which to do what you need to do, without the all-columns index interfering.
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
        # Adds all the checking described in the comment on LowCardTables::ActiveRecord::Migrations for the given
        # table name to the supplied block.
        def with_low_card_support(table_name, options = { }, &block)
          # Don't do this if we're already inside such a check -- this is needed because:
          #
          #    change_table :foo do |t|
          #      t.remove :bar
          #    end
          #
          # ...actually translates internally to a call to remove_column inside change_table, and, otherwise, we'll
          # try to do our work twice, which is bad news.
          (options, low_card_options) = partition_low_card_options(options)
          return block.call(options) if inside_migrations_check?

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
        # Are we currently inside a call to #with_low_card_support?
        def inside_migrations_check?
          !! Thread.current[:_low_card_migrations_only_once]
        end

        # Wrap the given block in code notifying us that we're inside a call to #with_low_card_support.
        def with_migrations_check(&block)
          begin
            Thread.current[:_low_card_migrations_only_once] = true
            block.call
          ensure
            Thread.current[:_low_card_migrations_only_once] = false
          end
        end

        # Wrap the given block in code that checks to see if we've removed any columns from the table that the given
        # model is for, and, if so, calls low_card_collapse_rows_and_update_referrers! on that model.
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

        # Wrap the given block in code that removes the all-columns unique index on the given model (which must be
        # a low-card table) beforehand, and recreates it afterwards.
        def without_unique_index(model, low_card_options, &block)
          begin
            model._low_card_remove_unique_index!
            block.call
          ensure
            unless low_card_options.has_key?(:low_card_collapse_rows) && (! low_card_options[:low_card_collapse_rows])
              model._low_card_ensure_has_unique_index!(true)
            end
          end
        end

        # Gets a fresh set of _low_card_value_column_names from the given low-card model.
        def fresh_value_column_names(model)
          model.reset_column_information
          model._low_card_value_column_names
        end

        # Splits an options Hash into two -- the first containing everything but low-card-related options, the second
        # containing only low-card options.
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

        # Given a table name, looks to see if it's a low-card table -- either implicitly, because there's an existing
        # model for that table that declares itself to be a low-card model, or explicitly, because we were passed
        # :low_card => true in the options hash. If so, returns a model to use for that table -- either the existing
        # model (implicit case) or a newly-created temporary model class (explicit case).
        #
        # Prefers an existing model over a temporary model, if there's both an existing model and we were passed
        # :low_card => true.
        def low_card_model_to_use_for(table_name, low_card_options)
          out = existing_low_card_model_for(table_name)
          out ||= temporary_model_class_for(table_name) if low_card_options[:low_card]
          out
        end

        # Creates a temporary low-card model class for the given table_name. This is used only if we explicitly
        # declare a model to be low-card in a migration, but there isn't currently a model for that table that
        # declares itself to be low-card.
        def temporary_model_class_for(table_name)
          temporary_model_class = Class.new(::ActiveRecord::Base)
          temporary_model_class.table_name = table_name
          temporary_model_class.class_eval { is_low_card_table }
          temporary_model_class.reset_column_information
          temporary_model_class
        end

        # Looks at ::ActiveRecord::Base.descendants to see if there's an existing model class that references the given
        # table_name and declares itself to be a low-card model class. If so, returns it.
        #
        # This method will attempt to eager-load all Rails code, so that we can detect the model class properly.
        # (Otherwise, migrations typically don't end up loading most models, so, even if the model is there on disk,
        # it will not be in memory and thus won't appear in ::ActiveRecord::Base.descendants.)
        def existing_low_card_model_for(table_name)
          # Make sure we load all models
          ::Rails.application.eager_load! if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application && ::Rails.application.respond_to?(:eager_load!)
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
