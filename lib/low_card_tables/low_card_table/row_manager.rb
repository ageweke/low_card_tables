require 'active_support'
require 'activerecord-import'
require 'low_card_tables/low_card_table/cache'
require 'low_card_tables/low_card_table/table_unique_index'
require 'low_card_tables/low_card_table/row_collapser'

module LowCardTables
  module LowCardTable
    # In many ways, the RowManager is the beating heart of +low_card_tables+. It is responsible for finding and
    # creating rows in low-card tables, as well as maintaining the unique index across all columns in the table and
    # dealing with any needs from migrations.
    #
    # Because this class is quite complex, some pieces of functionality have been broken out into other classes.
    # The TableUniqueIndex is responsible for maintaining the unique index across all columns in the table, and
    # the RowCollapser handles the case where rows need to be collapsed (unified) because a column was removed from
    # the low-card table.
    #
    # === Cache Notifications
    #
    # This class uses the ActiveSupport::Notifications interface to notify anyone who's interested of cache-related
    # events. In particular, it fires the following events with the following payloads:
    #
    # [low_card_tables.cache_load] <tt>{ :low_card_model => <ActiveRecord model class> }</tt>; this is fired when
    #                              the cache is loaded from the database, whether that's the first time after startup
    #                              or after a cache flush.
    # [low_card_tables.cache_flush] <tt>{ :low_card_model => <ActiveRecord model class>, :reason => <some reason> }</tt>;
    #                               this is fired when there's a cache that is flushed. Additional payload depends on
    #                               the +:reason+.
    #
    # Reasons for +low_card_tables.cache_flush+ include:
    #
    # [:manually_requested] You called +low_card_flush_cache!+ on the low-card model.
    # [:id_not_found] You requested a low-card row by ID, and we didn't find that ID in the cache. We assume that the ID
    #                 is likely valid and that it's simply been created since we retrieved the cache from the database,
    #                 so we flush the cache and try again. +:ids+ is present in the payload, mapping to an array of
    #                 one or more IDs -- the ID or IDs that weren't found in the cache.
    # [:collapse_rows_and_update_referrers] The low-card table has been migrated and has had a column removed; we've
    #                                       collapsed any now-duplicate rows properly. As such, we need to flush the
    #                                       cache.
    # [:schema_change] We have detected that the schema of the low-card table has changed, and need to flush the cache.
    # [:creating_rows] We're about to create one or more new rows in the low-card table, because a set of attributes
    #                  that has never been seen before was asked for. Before we actually go try to create them, we
    #                  lock the table and flush the cache, so that, in the case where some other process has already
    #                  created them, we simply pick them up now. Then, after we create them, we flush the cache again
    #                  to pick up the newly-created rows. +:context+ is present in the payload, mapped to either
    #                  +:before_import+ or +:after_import+ (corresponding to the two situations above). +:new_rows+ is
    #                  also present in the payload, mapped to an array of one or more Hashes, each of which represents
    #                  a unique combination of attributes to be created.
    # [:stale] By far the most common case -- the cache is simply stale based upon the current cache-expiration policy,
    #          and needs to be reloaded. The payload will contain +:loaded+, which is the time that the cache was
    #          loaded, and +:now+, which is the time at which the cache was checked for validity. (+:now+ will always
    #          be very close to, but not after, the current time; any delay is just due to the time it took to
    #          receive the notification via ActiveSupport::Notifications.)
    class RowManager
      attr_reader :low_card_model

      # Creates a new instance for the given low-card model.
      def initialize(low_card_model)
        unless low_card_model.respond_to?(:is_low_card_table?) && low_card_model.is_low_card_table?
          raise ArgumentError, "You must supply a low-card AR model class, not: #{low_card_model.inspect}"
        end

        @low_card_model = low_card_model
        @table_unique_index = LowCardTables::LowCardTable::TableUniqueIndex.new(low_card_model)
        @referring_models = [ ]
      end

      attr_reader :referring_models

      # Tells us that the low-card model we're operating on behalf of is referenced by the given +referring_model_class+.
      # This +referring_model_class+ should be an ActiveRecord class that has declared 'has_low_card_table' on this
      # low-card table.
      #
      # We keep track of this and expose it for a few reasons:
      #
      # * If we need to collapse the rows in this low-card table because a column has been removed, we use this list of
      #   referring models to know which columns have a foreign key to this table;
      # * When someone calls #reset_column_information on the low-card table, we re-compute (and re-install) the set of
      #   delegated methods from all models that refer to this low-card table.
      def referred_to_by(referring_model_class)
        @referring_models |= [ referring_model_class ]
      end

      # Tells us that someone called #reset_column_information on the low-card table; we'll inform all referring models
      # of that fact.
      def column_information_reset!
        @referring_models.each { |m| m._low_card_associations_manager.low_card_column_information_reset!(@low_card_model) }
      end

      # Returns all rows in the low-card table. This behaves semantically identically to simply calling ActiveRecord's
      # #all method on the low-card table itself, but it returns the data from cache.
      def all_rows
        cache.all_rows
      end

      # Flushes the cache immediately (assuming we have any cached data at all).
      def flush_cache!
        flush!(:manually_requested)
      end

      # Given a single primary-key ID of a low-card row, returns the row for that ID. Given an Array of one or more
      # primary-key IDs, returns a Hash mapping each of those IDs to the corresponding row. Properly flushes the cache
      # and tries again if given an ID that doesn't exist in cache.
      def rows_for_ids(id_or_ids)
        begin
          cache.rows_for_ids(id_or_ids)
        rescue LowCardTables::Errors::LowCardIdNotFoundError => lcinfe
          flush!(:id_not_found, :ids => lcinfe.ids)
          cache.rows_for_ids(id_or_ids)
        end
      end

      # A synonym for #rows_for_ids.
      def row_for_id(id)
        rows_for_ids(id)
      end

      # Given a single Hash specifying zero or more constraints for low-card rows (i.e., mapping zero or more columns
      # of the low-card table to specific values for those columns), returns a (possibly empty) Array of IDs of
      # low-card rows that match those constraints.
      #
      # Given an array of one or more Hashes, each of which specify zero or more constraints for low-card rows, returns
      # a Hash mapping each of those Hashes to a (possibly empty) Array of IDs of low-card rows that match each
      # Hash.
      #
      # Given a block (in which case no hashes may be passed), returns an Array of IDs of low-card rows that match the
      # block. The block is passed an instance of the low-card model class, and the return value of the block (truthy
      # or falsy) determines whether the ID of that row is included in the return value or not.
      def ids_matching(hash_or_hashes = nil, &block)
        do_matching(hash_or_hashes, block, :ids_matching)
      end

      # Given a single Hash specifying zero or more constraints for low-card rows (i.e., mapping zero or more columns
      # of the low-card table to specific values for those columns), returns a (possibly empty) Array of
      # low-card rows that match those constraints.
      #
      # Given an array of one or more Hashes, each of which specify zero or more constraints for low-card rows, returns
      # a Hash mapping each of those Hashes to a (possibly empty) Array of low-card rows that match each
      # Hash.
      #
      # Given a block (in which case no hashes may be passed), returns an Array of low-card rows that match the
      # block. The block is passed an instance of the low-card model class, and the return value of the block (truthy
      # or falsy) determines whether that row is included in the return value or not.
      def rows_matching(hash_or_hashes = nil, &block)
        do_matching(hash_or_hashes, block, :rows_matching)
      end

      # Given a single Hash specifying values for every column in the low-card table, returns an instance of the
      # low-card table, already existing in the database, for that combination of values.
      #
      # Given an array of Hashes, each specifying values for every column in the low-card table, returns a Hash
      # mapping each of those Hashes to an instance of the low-card table, already existing in the database, for that
      # combination of values.
      #
      # If you request an instance for a combination of values that doesn't exist in the table, it will simply be
      # mapped to +nil+. Under no circumstances will rows be added to the database.
      def find_rows_for(hash_hashes_object_or_objects)
        do_find_or_create(hash_hashes_object_or_objects, false)
      end

      # Given a single Hash specifying values for every column in the low-card table, returns an instance of the
      # low-card table for that combination of values. The row in question will be created if it doesn't already
      # exist.
      #
      # Given an array of Hashes, each specifying values for every column in the low-card table, returns a Hash
      # mapping each of those Hashes to an instance of the low-card table for that combination of values. Rows for
      # any missing combinations of values will be created. (Creation is done in bulk, using +activerecord_import+,
      # so this method will be fast no matter how many rows need to be created.)
      def find_or_create_rows_for(hash_hashes_object_or_objects)
        do_find_or_create(hash_hashes_object_or_objects, true)
      end

      # Behaves identically to #find_rows_for, except that it returns IDs instead of rows.
      def find_ids_for(hash_hashes_object_or_objects)
        row_map_to_id_map(find_rows_for(hash_hashes_object_or_objects))
      end

      # Behaves identically to #find_or_create_rows_for, except that it returns IDs instead of rows.
      def find_or_create_ids_for(hash_hashes_object_or_objects)
        row_map_to_id_map(find_or_create_rows_for(hash_hashes_object_or_objects))
      end

      # Returns the set of columns on the low-card table that we should consider "value columns" -- i.e., those that
      # contain data values, rather than metadata, like the primary key, created_at/updated_at, and so on.
      #
      # Columns that are excluded:
      #
      # * The primary key
      # * created_at and updated_at
      # * Any additional columns specified using the +:exclude_column_names+ option when declaring +is_low_card_table+.
      def value_column_names
        value_columns.map(&:name)
      end

      # Iterates through this table, finding duplicate rows and collapsing them. See RowCollapser for far more
      # information.
      def collapse_rows_and_update_referrers!(low_card_options = { })
        collapser = LowCardTables::LowCardTable::RowCollapser.new(@low_card_model, low_card_options)
        collapse_map = collapser.collapse!

        flush!(:collapse_rows_and_update_referrers)
        collapse_map
      end

      # If this table already has the correct unique index across all value columns, does nothing.
      #
      # If this table does not have the correct unique index, and +create_if_needed+ is truthy, then creates the index.
      # If this table does not have the correct unique index, and +create_if_needed+ is falsy, then raises
      # LowCardTables::Errors::LowCardNoUniqueIndexError.
      def ensure_has_unique_index!(create_if_needed = false)
        @table_unique_index.ensure_present!(create_if_needed)
      end

      # If this table currently has a unique index across all value columns, removes it.
      def remove_unique_index!
        @table_unique_index.remove!
      end


      private
      # Given a Hash that maps keys to instances of the low-card class, returns a Hash that is identical in every way
      # except that rows are replaced with their IDs. This is what we use to implement, for example,
      # #find_or_create_ids_for on top of #find_or_create_rows_for, trivially.
      def row_map_to_id_map(m)
        if m.kind_of?(Hash)
          out = { }
          m.each do |k,v|
            if v
              out[k] = v.id
            else
              out[k] = nil
            end
          end
          out
        else
          m.id if m
        end
      end

      # This is used to implement #rows_matching and #ids_matching on top of the Cache. +hash_or_hashes+ is a single
      # Hash or an array of Hashes, +block+ is a callable block (and you're only allowed to pass +hash_or_hashes+ _or_
      # +block+, not both), and +method_name+ is the name of the method on Cache that we should call to implement this
      # method.
      #
      # Since Cache does most of the work for us, this method is basically responsible for sanitizing input/output, and
      # detecting schema-change issues (as evidenced by LowCardColumnNotPresentError) and retrying, once. (This is so
      # that if code starts using a column name that was not present on the table at the last time the cache was read,
      # but since has been migrated in, we'll detect the change and react correctly.)
      def do_matching(hash_or_hashes, block, method_name)
        result = begin
          hashes = to_array_of_partial_hashes(hash_or_hashes)
          cache.send(method_name, hashes, &block)
        rescue LowCardTables::Errors::LowCardColumnNotPresentError => lccnpe
          flush!(:schema_change)
          hashes = to_array_of_partial_hashes(hash_or_hashes)
          cache.send(method_name, hashes, &block)
        end

        if hash_or_hashes.kind_of?(Array)
          result
        else
          raise "We passed in #{hash_or_hashes.inspect}, but got back #{result.inspect}?" unless result.kind_of?(Hash) && result.size <= 1
          result.values[0] if result.size > 0
        end
      end

      # This is used to implement #find_rows_for and #find_or_create_rows_for; the two methods are very similar except
      # in how they handle nonexistent rows, so we use this method to deal with both of them.
      def do_find_or_create(hash_hashes_object_or_objects, do_create)
        # Input manipulation...
        input_to_complete_hash_map = map_input_to_complete_hashes(hash_hashes_object_or_objects)
        complete_hashes = input_to_complete_hash_map.values

        # Do the actual lookup in the cache.
        existing = rows_matching(complete_hashes)
        not_found = complete_hashes.reject { |h| existing[h].length > 0 }

        # See if there's something we still don't have and if we need to create it.
        if not_found.length > 0 && do_create
          # We actually pass in _all_ the rows we want here, rather than just the ones that aren't found yet. Why?
          # Under the covers, #flush_lock_and_create_rows_for! is at the heart of our transactional core -- it locks
          # the table and checks again for which rows are present. We want to give it all of the data required, so that,
          # once it acquires the exclusive table-level lock, it knows exactly which data it needs to ensure is present
          # in the table.
          #
          # Passing data acquired outside a transaction into a transaction that's supposed to act on it is just asking
          # for trouble.
          existing = flush_lock_and_create_rows_for!(complete_hashes)
        end

        # Output manipulation and validation.
        out = { }
        input_to_complete_hash_map.each do |input, complete_hash|
          values = existing[complete_hash]

          if values.length == 0 && do_create
            raise %{Whoa: we asked for a row for this hash: #{key.inspect};
since this has been asserted to be a complete key, we should only ever get back a single row,
and we should always get back one row since we will have created the row if necessary,
but we got back these rows:

#{values.inspect}}
          end

          out[input] = values[0]
        end

        if hash_hashes_object_or_objects.kind_of?(Array)
          out
        else
          out[out.keys.first]
        end
      end

      # Returns all of the ::ActiveRecord::ConnectionAdapters::Column objects for all of the value columns in this
      # table.
      #
      # If this table doesn't exist yet, we return an empty set. This is important: this allows your Rails app to still
      # pass through the boot phase if you have a model for a low-card model whose underlying database table hasn't
      # actually been created yet. (If we didn't do this, then the traditional pattern of adding a migration and a model
      # in the same commit would fail -- other developers would get the model but not have the table, and Rails wouldn't
      # even be able to boot to migrate the table in.)
      def value_columns
        return [ ] unless @low_card_model.table_exists?

        @low_card_model.columns.select do |column|
          column_name = column.name.to_s.strip.downcase

          use = true
          use = false if column.primary
          use = false if column_names_to_skip.include?(column_name)
          use
        end
      end

      # This simply raises an exception when we can't create new rows in the low-card table for some reason. We want
      # to get a very nice, detailed message in return, so we have a method that composes something telling us exactly
      # what happened.
      #
      # +exception+ is the exception we got upon creation, if any. +keys+ is the set of keys (names of columns) we
      # passed to the #import call, and +failed_instances+ is the set of instances that +activerecord_import+ reported
      # as failing.
      #
      # This method eventually raises a LowCardInvalidLowCardRowsError.
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

      # This method is called when someone has called #find_or_create_rows_for or #find_or_create_ids_for, and we've
      # discovered that we do, in fact, need to create one or more rows in the database.
      #
      # Because we need to be careful of race conditions -- many other processes may be running the exact same code at
      # the exact same time -- we do the following:
      #
      # * First, obtain an exclusive table lock for the database we're using. Exactly how this works is database-
      #   dependent and not something ActiveRecord knows how to handle for us.
      # * Flush the cache and re-check if we still need to create rows. We do this because it's possible some other
      #   process created the rows in-between the time we checked and the time we locked the table. But, now, if we
      #   still are missing rows, we know we're the only process who can create them, since we have the exclusive
      #   table lock.
      # * Create the rows in the database, raising a detailed exception if the database raises an exception or if
      #   +activerecord_import+ reports any failed instances.
      # * Fire an ActiveSupport::Notifications event telling everybody that we just created rows.
      # * Flush the cache again, since we just created rows in the database and so the cache is guaranteed to be
      #   out-of-date.
      # * Return the rows that now should be present and match the input.
      def flush_lock_and_create_rows_for!(input)
        with_locked_table do
          flush!(:creating_rows, :context => :before_import, :new_rows => input)

          # because it's possible there was a schema modification that we just now picked up
          input_to_hashes_map = map_input_to_complete_hashes(input)
          hashes = input_to_hashes_map.values

          existing = rows_matching(hashes)
          still_not_found = hashes.reject { |h| existing[h].length > 0 }

          if still_not_found.length > 0
            keys = value_column_names
            values = still_not_found.map do |hash|
              keys.map { |k| hash[k] }
            end

            begin
              import_result = @low_card_model.import(keys, values, :validate => true)
              could_not_create_new_rows!(nil, keys, import_result.failed_instances) if import_result.failed_instances.length > 0
            rescue ::ActiveRecord::StatementInvalid => si
              could_not_create_new_rows!(si, keys, values)
            end

            instrument('rows_created', :keys => keys, :values => values)
          end

          flush!(:creating_rows, :context => :after_import, :new_rows => hashes)

          existing = rows_matching(hashes)
          still_not_found = hashes.reject { |h| existing[h].length > 0 }

          if still_not_found.length > 0
            raise LowCardTables::Errors::LowCardError, %{You asked for low-card IDs for one or more hashes specifying rows that didn't exist,
but, when we tried to create them, even after an import that appeared to succeed, we couldn't
find the models that should've now existed. This should never happen, and may be indicative
of a bug in the low-card tables system. Here's what we tried to create, but then couldn't find:

#{still_not_found.join("\n")}}
          end

          existing
        end
      end

      # Locks the table for this @low_card_model, using whatever database-specific code is required. This also surrounds
      # the block passed with a transaction on the table in question.
      def with_locked_table(&block)
        @low_card_model.transaction do
          with_database_exclusive_table_lock do
            block.call
          end
        end
      end

      # Obtains an exclusive lock on the table for this low-card model. This is much, much stronger than the built-in
      # ActiveRecord #lock! or #with_lock support (see ActiveRecord::Locking::Pessimistic); this should always lock
      # the entire table against reading and writing.
      #
      # We could've handled this by injecting methods into the ActiveRecord connection adapters for each specific
      # database type, but that's actually quite a bit more tricky metaprogramming (what if the adapters haven't been
      # loaded yet when our Gem starts up, but will get loaded later? -- and we definitely don't want to make this
      # Gem depend on the union of all supported database adapters!) than doing it this way.
      #
      # In other words, this may be a bit of a gross hack (groping the class name of the adapter in question), but it's
      # arguably a lot more reliable and easier to understand than the other way of doing this.
      def with_database_exclusive_table_lock(&block)
        case @low_card_model.connection.class.name
        when /postgresql/i then with_database_exclusive_table_lock_postgresql(&block)
        when /mysql/i then with_database_exclusive_table_lock_mysql(&block)
        when /sqlite/i then with_database_exclusive_table_lock_sqlite(&block)
        else
          raise LowCardTables::Errors::LowCardUnsupportedDatabaseError, %{You asked for low-card IDs for one or more hashes specifying rows that didn't exist,
but, when we went to create them, we discovered that we don't know how to exclusively
lock tables in your database. (This is very important so that we don't accidentally
create duplicate rows.)

Your database adapter's class name is '#{@low_card_model.connection.class.name}'; please submit at least
a bug report, or, even better, a patch. :) Adding support is quite easy, as long as you know the
equivalent of 'LOCK TABLE'(s) in your database.}
        end
      end

      # Obtains an exclusive table lock for a PostgreSQL database. PostgreSQL releases all table locks at the end of
      # the current transaction, so we just need to lock the table -- unlocking happens automatically when we release
      # our transaction, above.
      def with_database_exclusive_table_lock_postgresql(&block)
        # If we just use the regular :sanitize_sql support, we get:
        #    LOCK TABLE 'foo'
        # ...which, for whatever reason, PostgreSQL doesn't like. Escaping it this way works fine.
        escaped = @low_card_model.connection.quote_table_name(@low_card_model.table_name)
        run_sql("LOCK TABLE #{escaped}", { })
        block.call
      end

      # Obtains an exclusive table lock for a SQLite database. There is no locking possible or needed, since SQLite is
      # a single-user database.
      def with_database_exclusive_table_lock_sqlite(&block)
        block.call
      end

      # Obtains an exclusive table lock for a MySQL database. We need to make sure we unlock the table once the block
      # is complete.
      def with_database_exclusive_table_lock_mysql(&block)
        begin
          escaped = @low_card_model.connection.quote_table_name(@low_card_model.table_name)
          run_sql("LOCK TABLES #{escaped} WRITE", { })
          block.call
        ensure
          begin
            run_sql("UNLOCK TABLES", { })
          rescue ::ActiveRecord::StatementInvalid => si
            # we tried our best!
          end
        end
      end

      # Runs a SQL statement, specified as a string with substitution parameters.
      def run_sql(statement, params)
        @low_card_model.connection.execute(@low_card_model.send(:sanitize_sql, [ statement, params ]))
      end

      # Names of columns in low-card tables that we should always skip, no matter what.
      COLUMN_NAMES_TO_ALWAYS_SKIP = %w{created_at updated_at}

      # Returns the names of all columns in this table that we should skip when determining what to treat as a value
      # column for this table (as opposed to things like the primary key, created_at, updated_at, and so on, which are
      # metadata and shouldn't play a direct role in the low-card system).
      def column_names_to_skip
        @column_names_to_skip ||= begin
          COLUMN_NAMES_TO_ALWAYS_SKIP +
          Array(@low_card_model.low_card_options[:exclude_column_names] || [ ]).map { |n| n.to_s.strip.downcase }
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
        # to do that here! I kind of hate that behavior of Array()...
        as_array = if hash_hashes_object_or_objects.kind_of?(Array) then hash_hashes_object_or_objects else [ hash_hashes_object_or_objects ] end

        out = { }
        as_array.uniq.each do |hash_or_object|
          hash = nil

          if hash_or_object.kind_of?(Hash)
            # Allow us to use Strings or Symbols as indexes into the Hash
            hash = hash_or_object.with_indifferent_access
          elsif hash_or_object.kind_of?(@low_card_model)
            hash = hash_or_object.attributes.dup.with_indifferent_access
            hash.delete(@low_card_model.primary_key)
          else
            raise "Invalid input to this method -- this must be a Hash, or an instance of #{@low_card_model}: #{hash_or_object.inspect}"
          end

          hash = ensure_complete_key(hash)
          out[hash_or_object] = hash
        end

        out
      end

      # Given a single Hash that should contain values for all value columns in the low-card table -- no less, no more --
      # validates that the Hash contains no extra columns and no missing columns, and returns it. This method will allow
      # you to skip any columns in the input that have defaults in the database, and will correctly fill in those defaults
      # in the returned Hash.
      #
      # Because this requires all columns to be present in the input, it can only be used for methods like
      # #find_rows_for or #find_or_create_ids_for that require fully-specified input hashes.
      def ensure_complete_key(hash)
        keys_as_strings = hash.keys.map(&:to_s)
        missing = value_column_names - keys_as_strings
        extra = keys_as_strings - value_column_names

        missing = missing.select do |missing_column_name|
          column = @low_card_model.columns.detect { |c| c.name.to_s.strip.downcase == missing_column_name.to_s.strip.downcase }
          if column && column.default
            hash[column.name] = column.default
            false
          else
            true
          end
        end

        if missing.length > 0
          raise LowCardTables::Errors::LowCardColumnNotSpecifiedError, "The following is not a complete specification of all columns in low-card table '#{@low_card_model.table_name}'; it is missing these columns: #{missing.join(", ")}: #{hash.inspect}"
        end

        if extra.length > 0
          raise LowCardTables::Errors::LowCardColumnNotPresentError, "The following specifies extra columns that are not present in low-card table '#{@low_card_model.table_name}'; these columns are not present in the underlying model: #{extra.join(", ")}: #{hash.inspect}"
        end

        hash
      end

      # Given something that may be a single Hash or an array of Hashes, returns an array of Hashes, and makes sure that
      # the input (or each element of the input) is a valid partial key into the low-card table. A partial key is a Hash
      # that specifies zero or more value columns from the low-card table -- but you're not allowed to specify anything
      # in the Hash that isn't a value column in the low-card table.
      def to_array_of_partial_hashes(array)
        array = if array.kind_of?(Array) then array else [ array ] end
        array.each { |h| assert_partial_key!(h) }
        array
      end

      # Given a Hash, raises an error if that Hash is not a valid partial key into the low-card table -- i.e., if it
      # contains keys that are not valid value columns in the low-card table.
      def assert_partial_key!(hash)
        keys_as_strings = hash.keys.map(&:to_s)
        extra = keys_as_strings - value_column_names

        if extra.length > 0
          raise LowCardTables::Errors::LowCardColumnNotPresentError, "The following specifies extra columns that are not present in low-card table '#{@low_card_model.table_name}'; these columns are not present in the underlying model: #{extra.join(", ")}: #{hash.inspect}"
        end
      end

      # Fetches the cache we should use. This takes care of creating a cache if one is not present; it also takes care
      # of flushing the cache and creating a new one if the current cache is stale.
      def cache
        the_current_time = current_time
        cache_loaded_at = @cache.loaded_at if @cache

        if @cache && cache_expiration_policy_object.stale?(cache_loaded_at, the_current_time)
          flush!(:stale, :loaded => cache_loaded_at, :now => the_current_time)
        end

        unless @cache
          instrument('cache_load') do
            @cache = LowCardTables::LowCardTable::Cache.new(@low_card_model, @low_card_model.low_card_options)
          end
        end

        @cache
      end

      # Flushes the cache, for the reason given, and fires the appropriate ActiveSupport::Notification instrumentation.
      # +reason+ is the reason given in the notification, and +notification_options+ are added to the payload for the
      # notification.
      #
      # Whenever we flush the cache, we also ask ActiveRecord to purge its idea of what columns are on the table. This
      # ensures that we'll stay in sync with any underlying schema changes, and hence adapt to an evolving schema on
      # the fly, as best we can.
      def flush!(reason, notification_options = { })
        if @cache
          instrument('cache_flush', notification_options.merge(:reason => reason)) do
            @cache = nil
          end
        end

        @low_card_model.reset_column_information
      end

      # A thin wrapper around ActiveSupport::Notifications.
      def instrument(event, options = { }, &block)
        ::ActiveSupport::Notifications.instrument("low_card_tables.#{event}", options.merge(:low_card_model => @low_card_model), &block)
      end

      # Returns the correct cache-expiration policy object to use for the table in question.
      def cache_expiration_policy_object
        @low_card_model.low_card_cache_expiration_policy_object || LowCardTables.low_card_cache_expiration_policy_object
      end

      # Returns the current time. Broken out into a separate method so that we can easily override it in tests.
      def current_time
        Time.now
      end
    end
  end
end
