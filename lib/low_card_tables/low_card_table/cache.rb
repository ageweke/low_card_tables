module LowCardTables
  module LowCardTable
    # This class is responsible for caching all the rows for a given low-card table, and then returning various subsets
    # of those rows on demand.
    #
    # This class is actually pretty simple, and it's largely for one big reason: our cache is very simple -- we cache
    # the entire contents of the table, in memory, and the only way we update it is to throw out the entire cache and
    # create a brand-new one. As such, from the inside, this class has no mechanisms whatsoever for updating the cache
    # (as this object is thrown away and a whole new Cache object created when the cache is invalidated) nor are there
    # any methods for worrying about what should be in cache, doing a LRU, or anything like that.
    class Cache
      # Creates a new Cache for the given +model_class+, which must be an ActiveRecord::Base subclass that has declared
      # +is_low_card_table+.
      #
      # +options+ can contain:
      #
      # [:max_row_count] By default, the cache will raise a fatal error if trying to cache a low-card table that contains
      #                  more than DEFAULT_MAX_ROW_COUNT (5,000) rows. This is provided so that we detect early on if you
      #                  start storing data via the low-card system that is not, in fact, of low cardinality. However,
      #                  if you really are using a low-card table properly and just happen to have more than 5,000
      #                  distinct combinations of values, you can increase this limit via this option.
      def initialize(model_class, options = { })
        unless model_class.respond_to?(:is_low_card_table?) && model_class.is_low_card_table?
          raise ArgumentError, "You must supply a class that is a model class for a low-card table, not #{model_class.inspect}."
        end

        @model_class = model_class
        @options = options

        fill!
      end

      # At what time was this cache loaded? This is used (in conjunction with a cache-expiration policy object) to
      # determine if the cache is stale or not.
      def loaded_at
        @rows_read_at
      end

      # This behaves identically to #rows_matching, except that, everywhere a low-card model object would be returned,
      # a simple integer ID is returned instead.
      def ids_matching(hash_or_hashes = nil, &block)
        matching = rows_matching(hash_or_hashes, &block)

        out = case matching
        when Array then matching.map(&:id)
        when Hash then
          h = { }
          matching.each { |k,v| h[k] = v.map(&:id) }
          h
        when nil then nil
        else raise "Unknown return value from #rows_matching; this should never happen: #{matching.inspect}"
        end

        out
      end

      # Returns an Array of all models of the low-card table in the cache. The order is undefined.
      def all_rows
        @rows_by_id.values
      end

      # Given a single numeric ID of a low-card row, returns that low-card model object.
      #
      # Given an Array of one or more IDs of low-card rows, returns a Hash mapping each of those IDs to the
      # corresponding low-card model object.
      #
      # Raises LowCardTables::Errors::LowCardIdNotFoundError if any of the supplied IDs are not found in the cache.
      # (It is up to calling code -- in our case, the RowManager -- to flush the cache and try again, if desired.)
      def rows_for_ids(id_or_ids)
        ids = Array(id_or_ids)

        missing_ids = [ ]
        out = { }

        ids.each do |id|
          r = @rows_by_id[id]
          if r
            out[id] = r
          else
            missing_ids << id
          end
        end

        unless missing_ids.length == 0
          raise LowCardTables::Errors::LowCardIdNotFoundError.new("Can't find IDs for low-card table #{@model_class.table_name}: #{missing_ids.join(", ")}", missing_ids)
        end

        if id_or_ids.kind_of?(Array)
          out
        else
          out[id_or_ids]
        end
      end

      # Returns a subset of rows in the cache that match a specified set of conditions. (This can be all rows or no
      # rows, depending on the conditions, or any set in between.)
      #
      # You can specify conditions in the following ways:
      #
      # * A single Hash, passed as an argument. The return value will be an Array that contains zero or more instances
      #   of the low-card model class. Only instances that have columns matching the specified Hash will be returned.
      # * An array of one or more Hashes, passed as an argument. The return value will be a Hash; as keys, it will have
      #   exactly the Hashes you passed in. The value for each key will be an array of zero or more instances of the
      #   low-card model class, each of which matches the corresponding key.
      # * A block, passed to the method as a normal Ruby block. The return value will be an Array that contains zero
      #   or more instances of the low-card model class. The block will be invoked with every instance of the low-card
      #   model class, and only those instances where the block returns a value that evaluates to true will be included.
      #
      # In the form where you pass in an array of one or more Hashes, it is possible for the same low-card row to show
      # up in multiple values in the returned Hash, if it matches more than one of the supplied Hashes.
      #
      # Note that all matching is done via LowCardTables::LowCardTable::Base#_low_card_row_matches_any_hash?. See that
      # method for more documentation -- by overriding it, you can change the behavior of this method.
      def rows_matching(hash_or_hashes = nil, &block)
        hashes = hash_or_hashes || [ ]
        hashes = [ hashes ] unless hashes.kind_of?(Array)
        hashes.each { |h| raise ArgumentError, "You must supply Hashes, not: #{h.inspect}" unless h.kind_of?(Hash) }

        if block && hashes.length > 0
          raise ArgumentError, "You can supply either one or more Hashes to match against OR a block, but not both. Hashes: #{hashes.inspect}; block: #{block.inspect}"
        elsif (! block) && hashes.length == 0
          raise ArgumentError, "You must supply either one or more Hashes to match against or a block; you supplied neither."
        end


        if hashes.length > 0
          out = { }

          hashes.each { |h| out[h] = [ ] }

          @rows_by_id.each do |id,r|
            hashes.each do |h|
              out[h] << r if r._low_card_row_matches_any_hash?([ h.with_indifferent_access ])
            end
          end

          if hash_or_hashes.kind_of?(Array)
            out
          else
            out[hash_or_hashes]
          end
        else
          @rows_by_id.values.select { |r| r._low_card_row_matches_block?(block) }
        end
      end

      private
      # Fills the cache. This can only ever be called once.
      def fill!
        # Explode if we don't have a unique index on the underlying table -- because then we have no way of
        # guaranteeing that we won't create duplicate rows. (I am of the opinion that you'll never *truly* be certain
        # that your data obeys rules unless they're in the database, as constraints; application code can be as
        # careful as it wants to be, but, somehow, things always slip by unless you define constraints at the
        # database layer.)
        @model_class.low_card_ensure_has_unique_index!

        raise "Cannot fill: we already have values!" if @rows_by_id

        # We grab the time before we have fired off the query; this makes sure we don't create a race condition where
        # we think the cache is just a tiny bit newer than it actually is.
        read_rows_time = current_time

        # We ask for one more than the number of rows we are willing to accept here; this is so that if we have
        # too many rows, we can detect it, but we still won't do something crazy like try to load one million
        # rows into memory.
        raw_rows = @model_class.order("#{@model_class.primary_key} ASC").limit(max_row_count + 1).to_a
        raise_too_many_rows_error if raw_rows.length > max_row_count

        # Yes, we should never have duplicate IDs here -- it should be a primary key. But if it isn't for some reason,
        # we want to explode right away, rather than failing in strange, unpredicatable, and awful ways later.
        out = { }
        raw_rows.each do |raw_row|
          id = raw_row.id
          raise_duplicate_id_error(id, out[id], raw_row) if out[id]
          out[id] = raw_row
        end

        @rows_by_id = out
        @rows_read_at = read_rows_time
      end

      # This is broken out into a separate method merely for ease of testing.
      def current_time
        Time.now
      end

      DEFAULT_MAX_ROW_COUNT = 5_000

      def max_row_count
        @options[:max_row_count] || DEFAULT_MAX_ROW_COUNT
      end

      def raise_too_many_rows_error
        raise LowCardTables::Errors::LowCardTooManyRowsError, %{We tried to read in all the rows for low-card table '#{@model_class.table_name}', but there were
more rows that we are willing to handle -- there are at least #{max_row_count + 1}.
Most likely, something has gone horribly wrong with your low-card table (such as you
starting to store data that is not, in fact, low-cardinality at all). Alternatively,
perhaps you need to declare :max_row_count => (some larger value) in your
is_low_card_table declaration.}
      end

      def raise_duplicate_id_error(id, row_one, row_two)
        raise %{Duplicate ID in low-card table for class #{@model_class}!
We have at least two rows with ID #{id.inspect}:

#{row_one}

and

#{row_two}}
      end
    end
  end
end
