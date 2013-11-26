require 'low_card_tables'

describe LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy do
  def klass
    LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy
  end

  it "should require a non-negative expiration time" do
    lambda { klass.new("foo") }.should raise_error(ArgumentError)
    lambda { klass.new(-1.0) }.should raise_error(ArgumentError)
  end

  it "should expire at that time" do
    i = klass.new(1.0)

    the_time = Time.now - rand(100_000)
    i.stale?(the_time, the_time).should_not be
    i.stale?(the_time, the_time + 0.5).should_not be
    i.stale?(the_time, the_time + 0.99).should_not be
    i.stale?(the_time, the_time + 1.0).should be
    i.stale?(the_time, the_time + 15.0).should be
  end
end
