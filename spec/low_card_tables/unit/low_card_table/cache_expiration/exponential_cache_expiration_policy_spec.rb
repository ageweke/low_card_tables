require 'low_card_tables'
require 'active_support/time'

describe LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy do
  def klass
    LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy
  end

  it "should create itself with default values" do
    instance = klass.new({ :start_time => Time.now })

    instance.zero_floor.should == 3.minutes
    instance.min_time.should == 10.seconds
    instance.exponent.should == 2.0
    instance.max_time.should == 1.hour
  end

  it "should prevent specifying invalid values" do
    lambda { klass.new(:start_time => Time.now, :zero_floor_time => 'foo') }.should raise_error(ArgumentError, /zero_floor_time/i)
    lambda { klass.new(:start_time => Time.now, :zero_floor_time => -1.0) }.should raise_error(ArgumentError, /zero_floor_time/i)

    lambda { klass.new(:start_time => Time.now, :min_time => 'foo') }.should raise_error(ArgumentError, /min_time/i)
    lambda { klass.new(:start_time => Time.now, :min_time => -1.0) }.should raise_error(ArgumentError, /min_time/i)
    lambda { klass.new(:start_time => Time.now, :min_time => 0.0) }.should raise_error(ArgumentError, /min_time/i)
    lambda { klass.new(:start_time => Time.now, :min_time => 1.0) }.should raise_error(ArgumentError, /min_time/i)

    lambda { klass.new(:start_time => Time.now, :exponent => 'foo') }.should raise_error(ArgumentError, /exponent/i)
    lambda { klass.new(:start_time => Time.now, :exponent => -1.0) }.should raise_error(ArgumentError, /exponent/i)
    lambda { klass.new(:start_time => Time.now, :exponent => 0.0) }.should raise_error(ArgumentError, /exponent/i)
    lambda { klass.new(:start_time => Time.now, :exponent => 1.0) }.should raise_error(ArgumentError, /exponent/i)

    lambda { klass.new(:start_time => Time.now, :max_time => 'foo') }.should raise_error(ArgumentError, /max_time/i)
    lambda { klass.new(:start_time => Time.now, :max_time => 0.0) }.should raise_error(ArgumentError, /max_time/i)
    lambda { klass.new(:start_time => Time.now, :max_time => -1.0) }.should raise_error(ArgumentError, /max_time/i)
    lambda { klass.new(:start_time => Time.now, :min_time => 3.0, :max_time => 2.0) }.should raise_error(ArgumentError, /max_time/i)
  end

  def with_instance(options = { })
    @start_time = Time.now
    @cache_read_at = @start_time
    @instance = klass.new(options.merge(:start_time => @start_time))

    yield
  end

  def refill!(time)
    @cache_read_at = @start_time + time
  end

  def should_be_stale!(time)
    @instance.stale?(@cache_read_at, @start_time + time).should be
  end

  def should_not_be_stale!(time)
    @instance.stale?(@cache_read_at, @start_time + time).should_not be
  end

  it "should have a zero floor that's adjustable" do
    with_instance(:zero_floor_time => 1.0) do
      should_be_stale!(0.0)
      should_be_stale!(0.5)
      should_be_stale!(0.9)

      refill!(1.0)
      should_not_be_stale!(1.1)
    end

    with_instance(:zero_floor_time => 0.0) do
      should_not_be_stale!(0.0)

      refill!(0.5)
      should_not_be_stale!(0.6)
    end
  end

  it "should start an initial period of min_time seconds" do
    with_instance(:zero_floor_time => 1.0, :min_time => 3.0) do
      should_be_stale!(1.0)
      refill!(1.0)

      should_not_be_stale!(1.5)
      should_not_be_stale!(3.0)
      should_not_be_stale!(3.9)
      should_be_stale!(4.1)
    end
  end

  it "should exponentially increase according to the exponent" do
    with_instance(:zero_floor_time => 1.0, :min_time => 3.0, :exponent => 1.5) do
      # period 1: 1.0 - 4.0 seconds (3.0 duration)
      refill!(1.0)
      should_not_be_stale!(3.9)

      # period 2: 4.0 - 8.5 seconds (4.5 duration)
      refill!(4.0)
      should_not_be_stale!(4.0)
      should_not_be_stale!(7.0)
      should_not_be_stale!(8.4)
      should_be_stale!(8.5)

      # period 3: 8.5 - 15.25 seconds (6.75 duration)
      refill!(8.5)
      should_not_be_stale!(8.5)
      should_not_be_stale!(12.0)
      should_not_be_stale!(15.0)
      should_be_stale!(15.25)
    end
  end

  it "should cap out at the max_time" do
    with_instance(:zero_floor_time => 1.0, :min_time => 5.0, :exponent => 100.0, :max_time => 10.0) do
      # zero floor: 0.0-1.0
      # period 1: 1.0-6.0
      # period 2: 6.0-16.0
      refill!(6.0)

      should_not_be_stale!(6.0)
      should_not_be_stale!(15.9)
      should_be_stale!(16.0)

      # period 3: 16.0-26.0
      refill!(16.0)
      should_not_be_stale!(16.0)
      should_not_be_stale!(25.9)
      should_be_stale!(26.0)
    end
  end
end
