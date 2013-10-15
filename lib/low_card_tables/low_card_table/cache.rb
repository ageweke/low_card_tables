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

      def ids_matching(hash = nil, &block)
        matching(hash, block).map(&:id)
      end

      def value_sets_matching(hash = nil, &block)
        out = [ ]

        @value_sets_by_id.each do |id, value_set|
          out << value_set if value_set.matches?(hash, block)
        end

        out
      end

      private
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
