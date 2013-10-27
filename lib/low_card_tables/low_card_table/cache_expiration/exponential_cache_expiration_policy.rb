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
        end

        def stale?(cache_time, current_time)
          current_expiration = current_expiration_time(current_time)
          $stderr.puts "stale? current_time #{current_time}, cache_time #{cache_time}, diff #{current_time - cache_time}, current_expiration #{current_expiration}"
          (current_time - cache_time) >= current_expiration
        end

        private
        def current_expiration_time(current_time)
          if (current_time - base_time) <= @zero_floor
            0
          else
            current_expiration_time_from_exponential(current_time)
          end
        end

        def current_expiration_time_from_exponential(current_time)
          if (! @start_time)
            @start_time = base_time + @zero_floor
            @current_period_start = @start_time
            @current_period_duration = @min_time
          end

          while (@current_period_start + @current_period_duration) < current_time
            @current_period_start += @current_period_duration
            @current_period_duration *= @exponent
          end

          [ @current_period_duration, @max_time ].min
        end

        def base_time
          @base_time ||= current_time
        end

        def current_time
          Time.now
        end
      end
    end
  end
end
