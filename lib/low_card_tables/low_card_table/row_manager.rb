require 'active_support'

module LowCardTables
  module LowCardTable
    class RowManager
      def initialize(low_card_model)
        unless low_card_model.respond_to?(:is_low_card_table?) && low_card_model.is_low_card_table?
          raise "You must supply a low-card AR model class, not: #{low_card_model.inspect}"
        end

        @low_card_model = low_card_model
      end

      def ids_matching(hash_or_hashes = nil, &block)
        begin
          cache.ids_matching(hash_or_hashes, &block)
        rescue LowCardTables::Errors::LowCardColumnNotPresentError => lccnpe
          flush!
          cache.ids_matching(hash_or_hashes, &block)
        end
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

      def do_find_or_create(hash_or_hashes, do_create)
        hashes = Array(hash_or_hashes)
        hashes.each { |hash| assert_complete_key!(hash) }

        existing = ids_matching(hashes)
        still_not_found = hashes - existing.keys

        if still_not_found.length > 0 && do_create
          existing = flush_lock_and_create_ids_for!(hashes)
        end

        if hash_or_hashes.kind_of?(Array)
          existing
        else
          existing[hash_or_hashes]
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

            import_result = @low_card_model.import(keys, values, :validate => true)
            if import_result.failed_instances.length > 0
              raise LowCardTables::Errors::LowCardError, %{You asked for low-card IDs for one or more hashes specifying rows that didn't exist,
but, when we tried to create them, we couldn't import these rows:

#{import_result.failed_instances.join("\n")}}
            end
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
        else raise LowCardTables::Errors::UnsupportedDatabaseError, %{You asked for low-card IDs for one or more hashes specifying rows that didn't exist,
but, when we went to create them, we discovered that we don't know how to exclusively
lock tables in your database. (This is very important so that we don't accidentally
create duplicate rows.)

Your database adapter's class name is '#{@low_card_model.connection.class.name}'; please submit at least
a bug report, or, even better, a patch. :) Adding support is quite easy, as long as you know the
equivalent of 'LOCK TABLE'(s) in your database.}
      end

      def with_database_exclusive_table_lock_postgresql(&block)
        run_sql("LOCK TABLE :table", :table => @low_card_model.table_name)
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
        @low_card_model.cache_expiration_policy_object || LowCardTables.cache_expiration_policy_object
      end

      def current_time
        Time.now
      end
    end
  end
end
