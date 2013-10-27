require 'active_support/time'

module LowCardTables
  module LowCardTable
    module CacheExpiration
      class ExponentialCacheExpirationPolicy
        def initialize(options)
          options.assert_valid_keys(:zero_floor_time, :min_time, :exponent, :max_time)

          @zero_floor = options[:zero_floor_time] || 3.minutes
          @min_time = options[:min_time] || 10.seconds
          @exponent = options[:exponent] || 2.0
          @max_time = options[:max_time] || 1.hour

          raise ArgumentError, "zero_floor cannot be #{@zero_floor.inspect}" unless @zero_floor.kind_of?(Numeric) && @zero_floor >= 0.0
          raise ArgumentError, "min_time cannot be #{@min_time.inspect}" unless @zero_floor.kind_of?(Numeric) && @min_time > 0.0
          raise ArgumentError, "exponent cannoot be #{@exponent.inspect}" unless @exponent.kind_of?(Numeric) && @exponent > 1.0
          raise ArgumentError, "max_time cannot be #{@max_time.inspect}" unless @max_time.kind_of?(Numeric) && @max_time > 0.0 && @max_time > @min_time

          @start_time = current_time
          @segment_start_time = @start_time

          if @zero_floor > 0
            @segment_end_time = @segment_start_time + @zero_floor
            @segment_expiration_time = 0
          else
            @segment_end_time = @segment_start_time + @min_time
            @segment_expiration_time = @min_time
          end
        end

        def stale?(cache_time, current_time)
          next_segment! until within_current_segment?(current_time)

          out = if cache_time < @segment_start_time
            true
          else
            (current_time - cache_time) >= @segment_expiration_time
          end

          out
        end

        private
        def within_current_segment?(cache_time)
          cache_time < @segment_end_time
        end

        def next_segment!
          if @segment_expiration_time == 0
            @segment_start_time += @zero_floor
            @segment_end_time = @segment_start_time + @min_time
            @segment_expiration_time = @min_time
          elsif @segment_expiration_time >= @max_time
            @segment_start_time = @segment_end_time
            @segment_end_time = @segment_start_time + @max_time
            @segment_expiration_time = @max_time
          else
            @segment_start_time = @segment_end_time
            @segment_expiration_time = [ @segment_expiration_time * @exponent, @max_time ].min
            @segment_end_time = @segment_start_time + @segment_expiration_time
          end
        end

        def start_time
          @start_time ||= current_time
        end

        def current_time
          Time.now
        end
      end
    end
  end
end
