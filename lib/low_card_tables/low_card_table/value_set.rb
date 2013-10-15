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
          raise LowCardColumnNotPresentError, %{You're trying to select low-card rows from '#{@low_card_row.table_name}' and
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

      def matches?(hash = nil, &block)
        if (hash && block) || ((! hash) && (! block))
          raise "You must supply either a hash or a block, but not both, and not neither; you supplied #{hash.inspect} and #{block.inspect}"
        end

        if hash
          matches = true
          hash.keys.each do |key|
            matches = false unless column_matches?(key, hash[key])
          end

          matches
        else
          !! block.call(self)
        end
      end

      private
      def to_hash
        @as_hash ||= begin
          out = { }

          @low_card_row.columns.sort_by(&:name).each do |column|
            next if column.primary
            out[column.name] = @low_card_row[column.name]
          end

          out
        end
      end
    end
  end
end
