require 'low_card_tables'
require 'active_support/time'

describe LowCardTables::LowCardTable::CacheExpiration::UnlimitedCacheExpirationPolicy do
  it "should never be stale" do
    instance = LowCardTables::LowCardTable::CacheExpiration::UnlimitedCacheExpirationPolicy.new

    start_time = 10.minutes.ago
    instance.stale?(start_time, start_time).should_not be
    instance.stale?(start_time, start_time + 1.minute).should_not be
    instance.stale?(start_time, start_time + 10.minutes).should_not be
    instance.stale?(start_time, start_time + 100.minutes).should_not be
  end
end
