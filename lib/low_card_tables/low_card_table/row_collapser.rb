module LowCardTables
  module LowCardTable
    class RowCollapser
      def initialize(low_card_model, low_card_options)
        @low_card_model = low_card_model
        @low_card_options = low_card_options
      end

      def collapse!
        return if low_card_options.has_key?(:low_card_collapse_rows) && (! low_card_options[:low_card_collapse_rows])

        additional_referring_models = low_card_options[:low_card_referrers]

        attributes_to_rows_map = { }
        low_card_model.all.sort_by(&:id).each do |row|
          attributes = value_attributes(row)

          attributes_to_rows_map[attributes] ||= [ ]
          attributes_to_rows_map[attributes] << row
        end

        collapse_map = { }
        attributes_to_rows_map.each do |attributes, rows|
          if rows.length > 1
            winner = rows.shift
            losers = rows

            collapse_map[winner] = losers
          end
        end

        ids_to_delete = collapse_map.values.map { |row_array| row_array.map(&:id) }.flatten
        low_card_model.delete_all([ "id IN (:ids)", { :ids => ids_to_delete } ])

        all_referring_models = low_card_model.low_card_referring_models | (additional_referring_models || [ ])
        transaction_models = all_referring_models + [ low_card_model ]

        unless low_card_options.has_key?(:low_card_update_referring_models) && (! low_card_options[:low_card_update_referring_models])
          transactions_on(transaction_models) do
            all_referring_models.each do |referring_model|
              referring_model._low_card_update_collapsed_rows(low_card_model, collapse_map)
            end
          end
        end

        collapse_map
      end

      private
      attr_reader :low_card_options, :low_card_model

      def value_attributes(row)
        attributes = row.attributes
        out = { }
        low_card_model.low_card_value_column_names.each { |n| out[n] = attributes[n] }
        out
      end

      def transactions_on(transaction_models, &block)
        if transaction_models.length == 0
          block.call
        else
          model = transaction_models.shift
          model.transaction { transactions_on(transaction_models, &block) }
        end
      end
    end
  end
end
