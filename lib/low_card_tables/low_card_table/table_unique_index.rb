module LowCardTables
  module LowCardTable
    # A TableUniqueIndex represents the concept of a unique index for a given low-card model class. I say "the concept",
    # because there should only be one instance of this class for any given low-card model class -- there isn't one
    # instance of this class for each actual unique index for the class in question.
    #
    # This class started as code that was directly part of the RowManager, and was factored out to create this class
    # instead -- simply so that the RowManager wouldn't have any more code in it than necessary.
    class TableUniqueIndex
      # Creates a new instance for the low-card model class in question.
      def initialize(low_card_model)
        unless low_card_model.respond_to?(:is_low_card_table?) && low_card_model.is_low_card_table?
          raise ArgumentError, "You must supply a low-card AR model class, not: #{low_card_model.inspect}"
        end

        @low_card_model = low_card_model
      end

      # Ensures that the unique index is present. If the index is present, does nothing else.
      #
      # If the index is not present, then looks at +create_if_needed+. If this evaluates to true, then it will create
      # the index. If this evaluates to false, then it will raise an exception.
      def ensure_present!(create_if_needed)
        return unless @low_card_model.table_exists?

        current_name = current_unique_all_columns_index_name
        return true if current_name

        if create_if_needed
          create_unique_index!
          true
        else
          message = %{You said that the table '#{low_card_model.table_name}' is a low-card table.
However, it currently does not seem to have a unique index on all its columns. For the
low-card system to work properly, this is *required* -- although the low-card system
tries very hard to lock tables and otherwise ensure that it never will create duplicate
rows, this is important enough that we really want the database to enforce it.

We're looking for an index on the following columns:

  #{value_column_names.sort.join(", ")}

...and we have the following unique indexes:

}
          current_unique_indexes.each do |unique_index|
            message << "  '#{unique_index.name}': #{unique_index.columns.sort.join(", ")}\n"
          end
          message << "\n"

          raise LowCardTables::Errors::LowCardNoUniqueIndexError, message
        end
      end

      # Removes the unique index, if one is present. If one is not present, does nothing.
      def remove!
        table_name = low_card_model.table_name
        current_name = current_unique_all_columns_index_name

        if current_name
          migrate do
            remove_index table_name, :name => current_name
          end

          now_current_name = current_unique_all_columns_index_name
          if now_current_name
            raise "Whoa -- we tried to remove the unique index on #{table_name}, which was named '#{current_name}', but, after we removed it, we still have a unique all-columns index called '#{now_current_name}'!"
          end
        end
      end

      private
      attr_reader :low_card_model

      def value_column_names
        low_card_model.low_card_value_column_names
      end

      def migrate(&block)
        migration_class = Class.new(::ActiveRecord::Migration)
        metaclass = migration_class.class_eval { class << self; self; end }
        metaclass.instance_eval { define_method(:up, &block) }

        ::ActiveRecord::Migration.suppress_messages do
          migration_class.migrate(:up)
        end

        low_card_model.reset_column_information
        LowCardTables::VersionSupport.clear_schema_cache!(low_card_model)
      end

      def create_unique_index!
        raise "Whoa -- there should never already be a unique index for #{low_card_model}!" if current_unique_all_columns_index_name

        table_name = low_card_model.table_name
        column_names = value_column_names.sort
        ideal_name = ideal_unique_all_columns_index_name

        migrate do
          remove_index table_name, :name => ideal_name rescue nil
          add_index table_name, column_names, :unique => true, :name => ideal_name
        end

        unless current_unique_all_columns_index_name
          raise "Whoa -- there should always be a unique index by now for #{low_card_model}! We think we created one, but now it still doesn't exist?!?"
        end
      end

      def current_unique_indexes
        return [ ] if (! low_card_model.table_exists?)
        low_card_model.connection.indexes(low_card_model.table_name).select { |i| i.unique }
      end

      def current_unique_all_columns_index_name
        index = current_unique_indexes.detect { |index| index.columns.sort == value_column_names.sort }
        index.name if index
      end

      # We just limit all index names to this length -- this should be the smallest maximum index-name length that
      # any database supports.
      MINIMUM_MAX_INDEX_NAME_LENGTH = 63

      def ideal_unique_all_columns_index_name
        index_part_1 = "index_"
        index_part_2 = "_lc_on_all"

        remaining_characters = MINIMUM_MAX_INDEX_NAME_LENGTH - (index_part_1.length + index_part_2.length)
        index_name = index_part_1 + (@low_card_model.table_name[0..(remaining_characters - 1)]) + index_part_2

        index_name
      end
    end
  end
end
