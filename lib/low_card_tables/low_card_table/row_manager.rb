module LowCardTables
  module LowCardTable
    class RowManager
      def initialize(low_card_model)
        unless low_card_model.respond_to?(:is_low_card_table?) && low_card_model.is_low_card_table?
          raise "You must supply a low-card AR model class, not: #{low_card_model.inspect}"
        end

        @low_card_model = low_card_model
      end

      def cache_expiration=(time_interval)
        unless time_interval && ((time_interval == :unlimited) || (time_interval.kind_of?(Float) && time_interval >= 0))
          raise "You must supply a cache-expiration time that is a nonnegative number or :unlimited, not #{time_interval.inspect}"
        end

        @cache_expiration = time_interval
      end

      def cache_expiration
        out = @cache_expiration
        out = 1_000_000_000 if out == :unlimited # one billion seconds == 31 years
        out ||
      end

      def cache
        if @cache && (! @cache.no_more_stale_than?())
      end
    end
  end
end
