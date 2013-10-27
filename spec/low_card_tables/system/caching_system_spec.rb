require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'
require 'low_card_tables/helpers/query_spy_helper'

describe LowCardTables do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
    create_standard_system_spec_models!

    ::UserStatus.low_card_cache_expiration = :unlimited
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should cache low-card rows in memory" do
    LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
      spy.call_count.should == 0

      user1 = ::User.new
      user1.name = 'User1'
      user1.deleted = false
      user1.deceased = false
      user1.gender = 'female'
      user1.donation_level = 3
      user1.save!

      mid_calls = spy.call_count
      spy.call_count.should > 0

      user2 = ::User.new
      user2.name = 'User2'
      user2.deleted = false
      user2.deceased = false
      user2.gender = 'female'
      user2.donation_level = 3
      user2.save!

      spy.call_count.should == mid_calls
    end
  end

  it "should purge its cache efficiently when adding a new row" do
    LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
      spy.call_count.should == 0

      user1 = ::User.new
      user1.name = 'User1'
      user1.deleted = false
      user1.deceased = false
      user1.gender = 'female'
      user1.donation_level = 3
      user1.save!

      mid_calls = spy.call_count
      spy.call_count.should > 0

      user2 = ::User.new
      user2.name = 'User2'
      user2.deleted = false
      user2.deceased = false
      user2.gender = 'male'
      user2.donation_level = 7
      user2.save!

      # We allow two calls here because we need it for our double-checked locking pattern.
      (spy.call_count - mid_calls).should <= 2
    end
  end

  it "should notify listeners when refreshing its cache"
  it "should notify listeners when adding a new row"

  it "should use the specified cache policy"
end
