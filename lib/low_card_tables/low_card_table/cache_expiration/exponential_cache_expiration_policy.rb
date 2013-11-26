require 'active_support/time'

module LowCardTables
  module LowCardTable
    module CacheExpiration
      # If you don't understand the low-card cache and why cache-expiration policies are interesting and important,
      # please read the Github Wiki page at https://github.com/ageweke/low_card_tables/wiki/Caching for more
      # background first.
      #
      # An ExponentialCacheExpirationPolicy is by far the most sophisticated cache-expiration policy allowed. It breaks
      # apart the cache-expiration time into three separate regions. In order, they are:
      #
      # * <b>Zero Floor</b>, an intitial period of time (which can be zero in length) during which the cache expires
      #   immediately -- effectively meaning there is no cache;
      # * <b>Exponential Increase</b>, where the cache-expiration time starts at a given minimum, and increases by
      #   some geometric factor at each expiration thereafter;
      # * <b>Maximum</b>, where the cache-expiration time tops out at a particular value.
      #
      # The idea is that, in any system with a significant amount of production traffic, the stable state has basically
      # no new low-cardinality values being created at all -- any combination that can be created, will have already
      # been created. (This is true for a very large number of systems; but, of course, it all depends on _your_
      # particular system. It's possible you have a very "long-tailed" set of low-card values.)
      #
      # As such, it's safe to cache low-card tables for very long periods of time in the steady state. However, after
      # a deploy that introduces code that can create never-before-seen combinations of low-card values, there will be
      # new values created relatively rapidly, with the creation rate tapering off over time until we reach a steady
      # state where no new values are created at all. This fits exactly the model of the
      # ExponentialCacheExpirationPolicy.
      #
      # A word about measured timings:
      #
      # Measured timings are completely deterministic and do not depend on when the cache is actually accessed. That is,
      # one way of implementing this class would be to only check and advance what period we're in when someone calls
      # #stale? on it. However, this would mean that thinking about how the class works is very difficult: what time
      # period we're in depends on how often someone has asked us whether we're stale or not.
      #
      # Instead, the start time of this object (that is, the time when the +:zero_floor+ begins) is passed in to the
      # constructor, as +:start_time+. All time periods involved start from this point and are measured back-to-back --
      # that is, the first exponential time period begins immediately upon completion of the +:zero_floor+ period, the
      # next one immediately after that, and so on. (No, this doesn't happen in real time; there's no thread waiting
      # around just to update this object. Rather, when needed, we determine which period we're in on-demand.)
      class ExponentialCacheExpirationPolicy
        # Creates a new instance. +options+ must be a Hash that can must contain:
        #
        # * +:start_time+: The time at which this caching policy should start -- _i.e._, the start time for the
        #   zero floor. This must be a Time object.
        #
        # ...and can contain any of the following:
        #
        # * +:zero_floor_time+: The amount of time at the start that the cache will not cache anything; default is
        #   three minutes.
        # * +:min_time+: Once the zero floor has completed, the initial period during which the cache will be valid;
        #   default is ten seconds.
        # * +:exponent+: Once the initial +:min_time+ period has passed, subsequent periods will each geometrically
        #   increase by this exponent. (For example, if :+min_time+ is 3.0, and +:exponent+ is 1.5, then the first
        #   period will be 3.0 seconds; the second will be 3.0 * 1.5 = 4.5 seconds; the third will be 4.5 * 1.5 = 6.75
        #   seconds; and so on.) Default is 2.0, meaning the validity time doubles.
        # * +:max_time+: Once the cache validity period reaches +:max_time+ seconds, it is pinned at this value, and
        #   will not increase further. Default is one hour.
        def initialize(options)
          options.assert_valid_keys(:zero_floor_time, :min_time, :exponent, :max_time, :start_time)

          @start_time = options[:start_time]
          raise ArgumentError, "start_time cannot be #{@start_time.inspect}" unless @start_time && @start_time.kind_of?(::Time)

          @zero_floor = options[:zero_floor_time] || 3.minutes
          @min_time = options[:min_time] || 10.seconds
          @exponent = options[:exponent] || 2.0
          @max_time = options[:max_time] || 1.hour

          raise ArgumentError, "zero_floor_time cannot be #{@zero_floor.inspect}" unless @zero_floor.kind_of?(Numeric) && @zero_floor >= 0.0
          raise ArgumentError, "min_time cannot be #{@min_time.inspect}" unless @min_time.kind_of?(Numeric) && @min_time > 1.0
          raise ArgumentError, "exponent cannoot be #{@exponent.inspect}" unless @exponent.kind_of?(Numeric) && @exponent > 1.0
          raise ArgumentError, "max_time cannot be #{@max_time.inspect}" unless @max_time.kind_of?(Numeric) && @max_time > 0.0 && @max_time > @min_time

          # @segment_start_time is the time at which the current segment started.
          # @segment_end_time is the time at which the current segment ends.
          # @segment_expiration_time is the time at which the current cache will expire (absolute time, not relative);
          #   typically this will be the same as @segment_end_time, but it's different (zero) during the initial
          #   @min_time period.
          @segment_start_time = @start_time

          if @zero_floor > 0
            @segment_end_time = @segment_start_time + @zero_floor
            @segment_expiration_time = 0
          else
            @segment_end_time = @segment_start_time + @min_time
            @segment_expiration_time = @min_time
          end

          # Let's just make sure the clock doesn't run backwards, shall we?
          @last_seen_time = @start_time
        end

        attr_reader :zero_floor, :min_time, :exponent, :max_time

        # Called by LowCardTables::LowCardTable::Cache; this indicates whether the cache is stale or not. In order to
        # make testing easier, the time at which the cache was read (+cache_time+) and the current time (+current_time+)
        # are passed in, rather than implied using +Time.now+.
        #
        # It is an error to call this method with a +current_time+ that is before a previously-seen +current_time+.
        # (In other words, no, the clock can't run backwards.)
        def stale?(cache_time, current_time)
          if current_time < @last_seen_time
            raise ArgumentError, "Our clock is running backwards?!? We have previously seen a time of #{@last_seen_time.to_f}, and now it's #{current_time.to_f}?"
          elsif current_time > @last_seen_time
            @last_seen_time = current_time
          end

          next_segment! until within_current_segment?(current_time)

          out = if cache_time < @segment_start_time
            true
          else
            (current_time - cache_time) >= @segment_expiration_time
          end

          out
        end

        private
        attr_reader :start_time

        # Are we within the current segment, according to @segment_start_time and @segment_end_time?
        def within_current_segment?(cache_time)
          cache_time < @segment_end_time
        end

        # Advances @segment_start_time, @segment_end_time, and @segment_expiration_time to the next segment.
        def next_segment!
          if @segment_expiration_time == 0
            # We're in the initial @min_time segment -- advance to the first exponential.
            @segment_start_time += @zero_floor
            @segment_end_time = @segment_start_time + @min_time
            @segment_expiration_time = @min_time
          elsif @segment_expiration_time >= @max_time
            # We're in the final @max_time -- simply create another period of that duration.
            @segment_start_time = @segment_end_time
            @segment_end_time = @segment_start_time + @max_time
            @segment_expiration_time = @max_time
          else
            # We're in the exponential-increase period -- move to the next, longer, period.
            @segment_start_time = @segment_end_time
            @segment_expiration_time = [ @segment_expiration_time * @exponent, @max_time ].min
            @segment_end_time = @segment_start_time + @segment_expiration_time
          end
        end
      end
    end
  end
end
