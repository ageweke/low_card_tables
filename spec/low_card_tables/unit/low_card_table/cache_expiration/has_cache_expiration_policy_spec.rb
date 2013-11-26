require 'low_card_tables'
require 'active_support/time'

describe LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration do
  before :each do
    @test_class = Class.new
    @test_class.send(:include, LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration)
  end

  it "should default to no policy" do
    @test_class.low_card_cache_expiration.should be_nil
  end

  it "should allow setting to a no-caching policy" do
    @test_class.low_card_cache_expiration 0
    @test_class.low_card_cache_expiration.should == 0
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::NoCachingExpirationPolicy
  end

  it "should allow setting to a fixed policy" do
    @test_class.low_card_cache_expiration 15
    @test_class.low_card_cache_expiration.should == 15
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy
    @test_class.low_card_cache_expiration_policy_object.expiration_time.should == 15
  end

  it "should allow setting to an unlimited policy" do
    @test_class.low_card_cache_expiration :unlimited
    @test_class.low_card_cache_expiration.should == :unlimited
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::UnlimitedCacheExpirationPolicy
  end

  it "should allow setting to an exponential policy, with defaults" do
    @test_class.low_card_cache_expiration :exponential
    @test_class.low_card_cache_expiration.should == :exponential
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy
    @test_class.low_card_cache_expiration_policy_object.zero_floor.should == 3.minutes
    @test_class.low_card_cache_expiration_policy_object.min_time.should == 10.seconds
    @test_class.low_card_cache_expiration_policy_object.exponent.should == 2.0
    @test_class.low_card_cache_expiration_policy_object.max_time.should == 1.hour
  end

  it "should allow setting to an exponential policy, with overrides" do
    @test_class.low_card_cache_expiration :exponential, :zero_floor_time => 2.0, :min_time => 3.0, :exponent => 4.0, :max_time => 5.0
    @test_class.low_card_cache_expiration.should == [ :exponential, { :zero_floor_time => 2.0, :min_time => 3.0, :exponent => 4.0, :max_time => 5.0 } ]
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy
    @test_class.low_card_cache_expiration_policy_object.zero_floor.should == 2.0
    @test_class.low_card_cache_expiration_policy_object.min_time.should == 3.0
    @test_class.low_card_cache_expiration_policy_object.exponent.should == 4.0
    @test_class.low_card_cache_expiration_policy_object.max_time.should == 5.0
  end

  it "should allow changing the policy" do
    @test_class.low_card_cache_expiration 15
    @test_class.low_card_cache_expiration.should == 15
    @test_class.low_card_cache_expiration :unlimited
    @test_class.low_card_cache_expiration.should == :unlimited
  end

  it "should not change the policy if there's an exception" do
    @test_class.low_card_cache_expiration 15
    @test_class.low_card_cache_expiration.should == 15

    lambda { @test_class.low_card_cache_expiration :exponential, :zero_floor_time => -10.0 }.should raise_error(ArgumentError)

    @test_class.low_card_cache_expiration.should == 15
  end

  it "should fall back to the inherited class, if there is one" do
    @parent_class = Class.new
    @parent_class.send(:include, LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration)

    @test_class.low_card_cache_policy_inherits_from(@parent_class)

    @test_class.low_card_cache_expiration.should be_nil
    @test_class.low_card_cache_expiration_policy_object.should be_nil

    @parent_class.low_card_cache_expiration 15
    @parent_class.low_card_cache_expiration.should == 15
    @parent_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy
    @parent_class.low_card_cache_expiration_policy_object.expiration_time.should == 15
    @test_class.low_card_cache_expiration.should == 15
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy
    @test_class.low_card_cache_expiration_policy_object.expiration_time.should == 15

    @parent_class.low_card_cache_expiration :exponential
    @test_class.low_card_cache_expiration.should == :exponential
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy

    @test_class.low_card_cache_expiration 27
    @test_class.low_card_cache_expiration.should == 27
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy
    @test_class.low_card_cache_expiration_policy_object.expiration_time.should == 27

    @parent_class.low_card_cache_expiration 105
    @test_class.low_card_cache_expiration.should == 27
    @test_class.low_card_cache_expiration_policy_object.class.should == LowCardTables::LowCardTable::CacheExpiration::FixedCacheExpirationPolicy
    @test_class.low_card_cache_expiration_policy_object.expiration_time.should == 27
  end
end
