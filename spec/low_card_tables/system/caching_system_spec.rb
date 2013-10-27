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
      mid_calls.should > 0

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
      mid_calls.should > 0

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

  it "should handle the situation where a row in the database has a low-card ID that's not in cache" do
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
      mid_calls.should > 0

      new_status = ::UserStatusBackdoor.new
      new_status.deleted = false
      new_status.deceased = false
      new_status.gender = 'male'
      new_status.donation_level = 7
      new_status.save!

      old_status_id = user1.user_status_id
      ::User.update_all([ "user_status_id = :new_status_id", { :new_status_id => new_status.id } ], [ "id = :id", { :id => user1.id } ])
      user1.user_status_id.should == old_status_id # make sure we didn't touch the existing object

      # Make sure we didn't somehow invalidate the cache before this
      spy.call_count.should == mid_calls

      user2 = ::User.find(user1.id)
      user2.deleted.should == false
      user2.deceased.should == false
      user2.gender.should == 'male'
      user2.donation_level.should == 7

      (spy.call_count - mid_calls).should > 0
      (spy.call_count - mid_calls).should <= 2
    end
  end

  it "should be OK with manually-assigning an ID that's not in cache (that you somehow got out-of-band)" do
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
      mid_calls.should > 0

      new_status = ::UserStatusBackdoor.new
      new_status.deleted = false
      new_status.deceased = false
      new_status.gender = 'male'
      new_status.donation_level = 7
      new_status.save!

      user1.user_status_id = new_status.id
      user1.deleted.should == false
      user1.deceased.should == false
      user1.gender.should == 'male'
      user1.donation_level.should == 7

      (spy.call_count - mid_calls).should > 0
      (spy.call_count - mid_calls).should <= 2
    end
  end
  it "should notify listeners when refreshing its cache"
  it "should notify listeners when adding a new row"

  it "should use the specified cache policy"
end
