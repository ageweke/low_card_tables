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

      def rows_for_ids(id_or_ids)
        begin
          cache.rows_for_ids(id_or_ids)
        rescue LowCardTables::Errors::LowCardIdNotFoundError => lcinfe
          flush!
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

      def find_ids_for(hash_or_hashes)
        do_find_or_create(hash_or_hashes, false)
      end

      def find_or_create_ids_for(hash_or_hashes)
        do_find_or_create(hash_or_hashes, true)
      end

      def value_column_names
        @value_column_names ||= value_columns.map(&:name)
      end

      private
      COLUMN_NAMES_TO_ALWAYS_SKIP = %w{created_at updated_at}

      def do_matching(hash_or_hashes, block, method_name)
        hashes = if hash_or_hashes.kind_of?(Array) then hash_or_hashes else [ hash_or_hashes ] end
        hashes.each { |h| assert_partial_key!(h) }

        begin
          cache.send(method_name, hash_or_hashes, &block)
        rescue LowCardTables::Errors::LowCardColumnNotPresentError => lccnpe
          flush!
          cache.send(method_name, hash_or_hashes, &block)
        end
      end

      def do_find_or_create(hash_or_hashes, do_create)
        hashes = if hash_or_hashes.kind_of?(Array) then hash_or_hashes else [ hash_or_hashes ] end
        hashes.each { |hash| assert_complete_key!(hash) }

        existing = ids_matching(hashes)
        still_not_found = hashes - existing.keys

        if still_not_found.length > 0 && do_create
          existing = flush_lock_and_create_ids_for!(hashes)
        end

        out = { }
        existing.each do |key, values|
          if values.length != 1
            raise %{Whoa: we asked for an ID for this hash: #{key.inspect};
since this has been asserted to be a complete key, we should only ever get back a single value,
and we should always get back one value since we will have created the row if necessary,
but we got back these values:

#{values.inspect}}
          end

          out[key] = values[0]
        end

        if hash_or_hashes.kind_of?(Array)
          out
        else
          out[hash_or_hashes]
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


        if failed_instances
          message << %{- They failed validation.

Here's what we tried to import:

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

        if exception
          message << %{- The database refused to create them. This is usually because one or more of these rows
violates a database constraint -- like a NOT NULL or CHECK constraint.

The exception we got was:

(#{exception.class.name}) #{exception.message}
    #{exception.backtrace.join("\n    ")}}
        end

        raise LowCardTables::Errors::LowCardInvalidLowCardRowsError, message
      end

      def flush_lock_and_create_ids_for!(hashes)
        with_locked_table do
          flush!

          # because it's possible there was a schema modification that we just now picked up
          hashes.each { |hash| assert_complete_key!(hash) }

          existing = ids_matching(hashes)
          still_not_found = hashes - existing.keys

          if still_not_found.length > 0
            keys = value_column_names
            values = still_not_found.map do |hash|
              keys.map { |k| hash[k] }
            end

            import_result = nil
            begin
              import_result = @low_card_model.import(keys, values, :validate => true)
            rescue ::ActiveRecord::StatementInvalid => si
              could_not_create_new_rows!(si, keys, values)
            end

            could_not_create_new_rows!(nil, keys, import_result.failed_instances) if import_result.failed_instances.length > 0
          end

          flush!

          existing = ids_matching(hashes)
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

      def assert_partial_key!(hash)
        keys_as_strings = hash.keys.map(&:to_s)
        extra = keys_as_strings - value_column_names

        if extra.length > 0
          raise LowCardTables::Errors::LowCardColumnNotPresentError, "The following specifies extra columns that are not present in low-card table '#{@low_card_model.table_name}'; these columns are not present in the underlying model: #{extra.join(", ")}: #{hash.inspect}"
        end
      end

      def cache
        @cache = nil if @cache && cache_expiration_policy_object.stale?(@cache.loaded_at, current_time)
        @cache ||= LowCardTables::LowCardTable::Cache.new(@low_card_model, @low_card_model.low_card_options)
      end

      def flush!
        @cache = nil
        @value_columns = nil
        @value_column_names = nil
        @low_card_model.reset_column_information
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
