require 'low_card_tables'
require 'active_support/time'

describe LowCardTables::LowCardTable::CacheExpiration::NoCachingExpirationPolicy do
  it "should always be stale" do
    instance = LowCardTables::LowCardTable::CacheExpiration::NoCachingExpirationPolicy.new

    start_time = 10.minutes.ago
    instance.stale?(start_time, start_time).should be
    instance.stale?(start_time, start_time + 1.minute).should be
    instance.stale?(start_time, start_time + 10.minutes).should be
    instance.stale?(start_time, start_time + 100.minutes).should be
  end
end
