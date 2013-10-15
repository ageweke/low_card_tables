module LowCardTables
  module LowCardTable
    class RowManager
      def initialize(low_card_model)
        unless low_card_model.respond_to?(:is_low_card_table?) && low_card_model.is_low_card_table?
          raise "You must supply a low-card AR model class, not: #{low_card_model.inspect}"
        end

        @low_card_model = low_card_model
      end

      private
      def cache
        @cache = nil if @cache && cache_expiration_policy_object.stale?(@cache.loaded_at, current_time)
        @cache ||= LowCardTables::LowCardTable::Cache.new(@low_card_model, @low_card_model.low_card_options)
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
