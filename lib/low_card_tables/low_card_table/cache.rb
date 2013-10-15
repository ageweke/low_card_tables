module LowCardTables
  module LowCardTable
    class Cache
      def initialize(model_class, options = { })
        @model_class = model_class
        @options = options

        fill!
      end

      def loaded_at
        @value_sets_read_at
      end

      def ids_matching(hash_or_hashes = nil, &block)
        matching = value_sets_matching(hash_or_hashes, block)

        case matching
        when Array then matching.map(&:id)
        when Hash then
          out = { }
          matching.each { |k,v| out[k] = v.map(&:id) }
        when nil then nil
        else raise "Unknown return value from #value_sets_matching; this should never happen: #{matching.inspect}"
        end
      end

      def value_sets_for_ids(id_or_ids)
        ids = Array(id_or_ids)

        missing_ids = [ ]
        out = { }

        ids.each do |id|
          vs = @value_sets_by_id[id]
          if vs
            out[id] = vs
          else
            missing_ids << id
          end
        end

        unless missing_ids.length == 0
          raise LowCardTables::Errors::LowCardIdNotFoundError, "Can't find IDs for low-card table #{@model_class.table_name}: #{missing_ids.join(", ")}"
        end

        if id_or_ids.kind_of?(Array)
          out
        else
          out[id_or_ids]
        end
      end

      def value_sets_matching(hash_or_hashes = nil, &block)
        hashes = Array(hash_or_hashes || [ ])
        hashes.each { |h| raise ArgumentError, "You must supply Hashes, not: #{h.inspect}" unless h.kind_of?(Hash) }

        if block && hashes.length > 0
          raise ArgumentError, "You can supply either one or more Hashes to match against OR a block, but not both. Hashes: #{hashes.inspect}; block: #{block.inspect}"
        elsif (! block) && hashes.length == 0
          raise ArgumentError, "You must supply either one or more Hashes to match against or a block; you supplied neither."
        end


        if hashes.length > 0
          out = { }

          @value_sets_by_id.each do |vs|
            matching_hash = vs.matches?(hashes)
            if matching_hash
              out[matching_hash] ||= [ ]
              out[matching_hash] << vs
            end
          end

          if hash_or_hashes.kind_of?(Array)
            out
          else
            out[hash_or_hashes]
          end
        else
          @value_sets_by_id.values.select { |vs| vs.matches?(nil, &block) }
        end
      end

      def fill!
        raise "Cannot fill: we already have values!" if @value_sets_by_id

        # We ask for one more than the number of rows we are willing to accept here; this is so that if we have
        # too many rows, we can detect it, but we still won't do something crazy like try to load one million
        # rows into memory.
        read_rows_time = Time.now

        raw_rows = @model_class.order("#{@model_class.primary_key} ASC").limit(max_row_count + 1).all
        raise_too_many_rows_error if raw_rows.length > max_row_count

        out = { }
        raw_rows.each do |raw_row|
          id = raw_row.id
          raise_duplicate_id_error(id, out[id], raw_row) if out[id]
          out[id] = raw_row.to_low_card_value_set
        end

        @value_sets_by_id = out
        @value_sets_read_at = read_rows_time
      end

      DEFAULT_MAX_ROW_COUNT = 5_000

      def max_row_count
        @options[:max_row_count] || DEFAULT_MAX_ROW_COUNT
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
end
