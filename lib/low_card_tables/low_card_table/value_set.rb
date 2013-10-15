module LowCardTables
  module LowCardTable
    class ValueSet
      def initialize(low_card_row)
        unless low_card_row.class.respond_to?(:is_low_card_table?) && low_card_row.class.is_low_card_table?
          raise "This class can only be created with a row from a low-card table, not #{low_card_row.inspect}"
        end

        @low_card_row = low_card_row
      end

      def id
        @low_card_row.id
      end

      def [](column_name)
        our_hash = to_hash
        unless our_hash.has_key?(column_name.to_s)
          raise LowCardTables::Errors::LowCardColumnNotPresentError, %{You're trying to select low-card rows from '#{@low_card_row.table_name}' and
look at column '#{column_name}', but no such column exists. We have columns named:
#{our_hash.keys.sort}}
        end

        our_hash[column_name]
      end

      def column_matches?(column_name, value)
        self[column_name] == value
      end

      def to_s
        @to_s ||= begin
          s = "<LowCard '#{@low_card_row.class.table_name}': #{@low_card_row.id}: "
          s << to_hash.keys.sort.map { |k| s << "'#{k}'=#{self[k]}" }.join(", ")
          s << ">"
          s
        end
      end

      def matches?(hash_or_hashes = nil, &block)
        hashes = Array(hash_or_hashes || [ ])
        hashes.each { |h| raise ArgumentError, "You must supply a Hash, not: #{h.inspect}" unless h.kind_of?(Hash) }

        if (hashes.length > 0 && block) || (hashes.length == 0 && (! block))
          raise ArgumentError, "You must supply either a hash or a block, but not both, and not neither; you supplied #{hashes.inspect} and #{block.inspect}"
        end

        if hashes.length > 0
          hashes.detect { |hash| hash.keys.all? { |key| column_matches?(key, hash[key]) } }
        else
          !! block.call(self)
        end
      end

      private
      def row_manager
        @row_manager ||= @low_card_row.class._low_card_row_manager
      end

      def to_hash
        @as_hash ||= begin
          out = { }

          row_manager.value_column_names.each do |column_name|
            out[column_name] = @low_card_row[column_name]
          end

          out.with_indifferent_access
        end
      end
    end
  end
end
