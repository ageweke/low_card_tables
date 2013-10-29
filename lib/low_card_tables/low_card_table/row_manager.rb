require 'active_support'
require 'activerecord-import'
require 'low_card_tables/low_card_table/cache'

module LowCardTables
  module LowCardTable
    class RowManager
      def initialize(low_card_model)
        unless low_card_model.respond_to?(:is_low_card_table?) && low_card_model.is_low_card_table?
          raise "You must supply a low-card AR model class, not: #{low_card_model.inspect}"
        end

        @low_card_model = low_card_model
      end

      def all_rows
        cache.all_rows
      end

      def flush_cache!
        flush!(:manually_requested)
      end

      def rows_for_ids(id_or_ids)
        begin
          cache.rows_for_ids(id_or_ids)
        rescue LowCardTables::Errors::LowCardIdNotFoundError => lcinfe
          flush!(:id_not_found, :ids => lcinfe.ids)
          cache.rows_for_ids(id_or_ids)
        end
      end

      def row_for_id(id)
        rows_for_ids(id)
      end

      def ids_matching(hash_or_hashes = nil, &block)
        do_matching(hash_or_hashes, block, :ids_matching)
      end

      def rows_matching(hash_or_hashes = nil, &block)
        do_matching(hash_or_hashes, block, :rows_matching)
      end

      def find_rows_for(hash_hashes_object_or_objects)
        do_find_or_create(hash_hashes_object_or_objects, false)
      end

      def find_or_create_rows_for(hash_hashes_object_or_objects)
        do_find_or_create(hash_hashes_object_or_objects, true)
      end

      def find_ids_for(hash_hashes_object_or_objects)
        row_map_to_id_map(find_rows_for(hash_hashes_object_or_objects))
      end

      def find_or_create_ids_for(hash_hashes_object_or_objects)
        row_map_to_id_map(find_or_create_rows_for(hash_hashes_object_or_objects))
      end

      def value_column_names
        @value_column_names ||= value_columns.map(&:name)
      end

      def ensure_has_unique_index!(create_if_needed = false)
        current_name = current_unique_all_columns_index_name
        $stderr.puts "ensure_has_unique_index!: #{current_name.inspect}"
        return current_name if current_name

        if create_if_needed
          create_unique_index!
        else
          message = %{You said that the table '#{@low_card_model.table_name}' is a low-card table.
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

      private
      def create_unique_index!
        raise "Whoa -- there should never already be a unique index for #{@low_card_model}!" if current_unique_all_columns_index_name

        table_name = @low_card_model.table_name
        column_names = value_column_names
        ideal_name = ideal_unique_all_columns_index_name

        block = lambda do
          add_index table_name, column_names, :unique => true, :name => ideal_name
        end

        migration_class = Class.new(::ActiveRecord::Migration)
        metaclass = migration_class.class_eval { class << self; self; end }
        metaclass.instance_eval { define_method(:up, &block) }

        ::ActiveRecord::Migration.suppress_messages do
          migration_class.migrate(:up)
        end

        unless current_unique_all_columns_index_name
          raise "Whoa -- there should always be a unique index by now for #{@low_card_model}! We think we created one, but now it still doesn't exist?!?"
        end

        ideal_name
      end

      def current_unique_indexes
        @low_card_model.connection.indexes(@low_card_model.table_name).select { |i| i.unique }
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

      def row_map_to_id_map(m)
        if m.kind_of?(Hash)
          out = { }
          m.each { |k,v| out[k] = v.id }
          out
        else
          m.id
        end
      end

      COLUMN_NAMES_TO_ALWAYS_SKIP = %w{created_at updated_at}

      def do_matching(hash_or_hashes, block, method_name)
        hashes = to_array_of_partial_hashes(hash_or_hashes)

        begin
          cache.send(method_name, hash_or_hashes, &block)
        rescue LowCardTables::Errors::LowCardColumnNotPresentError => lccnpe
          flush!(:schema_change)
          cache.send(method_name, hash_or_hashes, &block)
        end
      end

      def do_find_or_create(hash_hashes_object_or_objects, do_create)
        input_to_complete_hash_map = map_input_to_complete_hashes(hash_hashes_object_or_objects)
        complete_hash_to_input_map = input_to_complete_hash_map.invert

        complete_hashes = input_to_complete_hash_map.values

        existing = rows_matching(complete_hashes)
        still_not_found = complete_hashes - existing.keys

        if still_not_found.length > 0 && do_create
          existing = flush_lock_and_create_rows_for!(complete_hashes)
        end

        out = { }
        existing.each do |key, values|
          if values.length != 1
            raise %{Whoa: we asked for a row for this hash: #{key.inspect};
since this has been asserted to be a complete key, we should only ever get back a single row,
and we should always get back one row since we will have created the row if necessary,
but we got back these rows:

#{values.inspect}}
          end

          input = complete_hash_to_input_map[key]
          out[input] = values[0]
        end

        if hash_hashes_object_or_objects.kind_of?(Array)
          out
        else
          out[out.keys.first]
        end
      end

      # effectively private
      def value_columns
        @value_columns ||= @low_card_model.columns.select do |column|
          column_name = column.name.to_s.strip.downcase

          use = true
          use = false if column.primary
          use = false if column_names_to_skip.include?(column_name)
          use
        end
      end

      def could_not_create_new_rows!(exception, keys, failed_instances)
        message = %{The low_card_tables gem was trying to create one or more new rows in
the low-card table '#{@low_card_model.table_name}', but, when we went to create those rows...

}


        if exception
          message << %{- The database refused to create them. This is usually because one or more of these rows
violates a database constraint -- like a NOT NULL or CHECK constraint.

The exception we got was:

(#{exception.class.name}) #{exception.message}
    #{exception.backtrace.join("\n    ")}}
        elsif failed_instances
          message << "- They failed validation."
        end

        if failed_instances.length > 0
          message << %{Here's what we tried to import:

  Keys: #{keys.inspect}
  Values:

}

          failed_instances.each do |failed_instance|
            line = "    #{failed_instance.inspect}"

            if failed_instance.respond_to?(:errors)
              line << "    ERRORS: #{failed_instance.errors.full_messages.join("; ")}"
            end

            message << "#{line}\n"
          end
        end

        raise LowCardTables::Errors::LowCardInvalidLowCardRowsError, message
      end

      def flush_lock_and_create_rows_for!(hashes)
        with_locked_table do
          flush!(:creating_rows, :context => :before_import, :new_rows => hashes)

          # because it's possible there was a schema modification that we just now picked up -- we're just using this
          # for validation, so that it'll blow up if any of these are now no longer complete hashes
          map_input_to_complete_hashes(hashes)

          existing = rows_matching(hashes)
          still_not_found = hashes - existing.keys

          if still_not_found.length > 0
            keys = value_column_names
            values = still_not_found.map do |hash|
              keys.map { |k| hash[k] }
            end

            import_result = nil
            begin
              instrument('rows_created', :keys => keys, :values => values) do
                import_result = @low_card_model.import(keys, values, :validate => true)
              end
            rescue ::ActiveRecord::StatementInvalid => si
              could_not_create_new_rows!(si, keys, values)
            end

            could_not_create_new_rows!(nil, keys, import_result.failed_instances) if import_result.failed_instances.length > 0
          end

          flush!(:creating_rows, :context => :after_import, :new_rows => hashes)

          existing = rows_matching(hashes)
          still_not_found = hashes - existing.keys

          if still_not_found.length > 0
            raise LowCardTables::Errors::LowCardError, %{You asked for low-card IDs for one or more hashes specifying rows that didn't exist,
but, when we tried to create them, even after an import that appeared to succeed, we couldn't
find the models that should've now existed. Here's what we tried to create, but then
couldn't find:

#{still_not_found.join("\n")}}
          end

          existing
        end
      end

      def with_locked_table(&block)
        @low_card_model.transaction do
          with_database_exclusive_table_lock do
            block.call
          end
        end
      end

      def with_database_exclusive_table_lock(&block)
        case @low_card_model.connection.class.name
        when /postgresql/i then with_database_exclusive_table_lock_postgresql(&block)
        when /mysql/i then with_database_exclusive_table_lock_mysql(&block)
        else
          raise LowCardTables::Errors::UnsupportedDatabaseError, %{You asked for low-card IDs for one or more hashes specifying rows that didn't exist,
but, when we went to create them, we discovered that we don't know how to exclusively
lock tables in your database. (This is very important so that we don't accidentally
create duplicate rows.)

Your database adapter's class name is '#{@low_card_model.connection.class.name}'; please submit at least
a bug report, or, even better, a patch. :) Adding support is quite easy, as long as you know the
equivalent of 'LOCK TABLE'(s) in your database.}
        end
      end

      def with_database_exclusive_table_lock_postgresql(&block)
        # If we just use the regular :sanitize_sql support, we get:
        #    LOCK TABLE 'foo'
        # ...which, for whatever reason, PostgreSQL doesn't like. Escaping it this way works fine.
        escaped = @low_card_model.connection.quote_table_name(@low_card_model.table_name)
        run_sql("LOCK TABLE #{escaped}", { })
        block.call
      end

      def with_database_exclusive_table_lock_mysql(&block)
        begin
          run_sql("LOCK TABLES :table", :table => @low_card_model.table_name)
          block.call
        ensure
          begin
            run_sql("UNLOCK TABLES :table", :table => @low_card_model.table_name)
          rescue ActiveRecord::StatementInvalid => si
            # we tried our best!
          end
        end
      end

      def run_sql(statement, params)
        @low_card_model.connection.execute(@low_card_model.send(:sanitize_sql, [ statement, params ]))
      end

      def column_names_to_skip
        @column_names_to_skip ||= begin
          COLUMN_NAMES_TO_ALWAYS_SKIP +
          (@low_card_model.low_card_options[:exclude_column_names] || [ ]).map { |n| n.to_s.strip.downcase }
        end
      end

      # Given something that can be a single Hash, an array of Hashes, a single instance of the @low_card_model class,
      # or an array of instances of the @low_card_model class, returns a new Hash.
      #
      # This new Hash has, as keys, each of the inputs to this method, and, as values, a Hash for that input that is
      # a complete, normalized Hash representing that input.
      #
      # This method will also raise an exception if any of the inputs do not include all of the necessary keys for the
      # low-card table -- thus, this method can only be used for methods like #find_rows_for or #find_or_create_ids_for,
      # where the input must each specify exactly one low-card row, rather than methods like
      # #rows_matching/#ids_matching, where each input may match multiple low-card rows.
      def map_input_to_complete_hashes(hash_hashes_object_or_objects)
        # We can't use Array(), because that will turn a single Hash into an Array, and we definitely don't want
        # to do that here!
        as_array = if hash_hashes_object_or_objects.kind_of?(Array) then hash_hashes_object_or_objects else [ hash_hashes_object_or_objects ] end

        out = { }
        as_array.uniq.each do |hash_or_object|
          hash = nil

          if hash_or_object.kind_of?(Hash)
            hash = hash_or_object.with_indifferent_access
          elsif hash_or_object.kind_of?(@low_card_model)
            hash = hash_or_object.attributes.dup.with_indifferent_access
            hash.delete(@low_card_model.primary_key)
          else
            raise "Invalid input to this method -- this must be a Hash, or an instance of #{@low_card_model}: #{hash_or_object.inspect}"
          end

          assert_complete_key!(hash)
          out[hash_or_object] = hash
        end

        out
      end

      def assert_complete_key!(hash)
        keys_as_strings = hash.keys.map(&:to_s)
        missing = value_column_names - keys_as_strings
        extra = keys_as_strings - value_column_names

        if missing.length > 0
          raise LowCardTables::Errors::LowCardColumnNotSpecifiedError, "The following is not a complete specification of all columns in low-card table '#{@low_card_model.table_name}'; it is missing these columns: #{missing.join(", ")}: #{hash.inspect}"
        end

        if extra.length > 0
          raise LowCardTables::Errors::LowCardColumnNotPresentError, "The following specifies extra columns that are not present in low-card table '#{@low_card_model.table_name}'; these columns are not present in the underlying model: #{extra.join(", ")}: #{hash.inspect}"
        end
      end

      def to_array_of_partial_hashes(array)
        array = if array.kind_of?(Array) then array else [ array ] end
        array.map do |hash|
          out = hash.with_indifferent_access
          assert_partial_key!(out)
          out
        end
      end

      def assert_partial_key!(hash)
        keys_as_strings = hash.keys.map(&:to_s)
        extra = keys_as_strings - value_column_names

        if extra.length > 0
          raise LowCardTables::Errors::LowCardColumnNotPresentError, "The following specifies extra columns that are not present in low-card table '#{@low_card_model.table_name}'; these columns are not present in the underlying model: #{extra.join(", ")}: #{hash.inspect}"
        end
      end

      def cache
        if @cache && cache_expiration_policy_object.stale?(@cache.loaded_at, current_time)
          flush!(:stale, :loaded => @cache.loaded_at, :now => current_time)
          @cache = nil
        end

        unless @cache
          instrument('cache_load') do
            @cache = LowCardTables::LowCardTable::Cache.new(@low_card_model, @low_card_model.low_card_options)
          end
        end

        @cache
      end

      def flush!(reason, notification_options = { })
        if @cache
          instrument('cache_flush', notification_options.merge(:reason => reason)) do
            @cache = nil
            @value_columns = nil
            @value_column_names = nil
          end
        end

        @low_card_model.reset_column_information
      end

      def instrument(event, options = { }, &block)
        ::ActiveSupport::Notifications.instrument("low_card_tables.#{event}", options.merge(:low_card_model => @low_card_model), &block)
      end

      def cache_expiration_policy_object
        @low_card_model.low_card_cache_expiration_policy_object || LowCardTables.low_card_cache_expiration_policy_object
      end

      def current_time
        Time.now
      end
    end
  end
end
