require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

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

  it "should say #is_low_card_table? appropriately" do
    ::UserStatus.is_low_card_table?.should be
    ::User.is_low_card_table?.should_not be

    ::UserStatus.low_card_options.should == { }
  end

  context "with a trivial setup" do
    before :each do
      @user1 = ::User.new
      @user1.name = 'User1'
      @user1.deleted = false
      @user1.deceased = false
      @user1.gender = 'female'
      @user1.donation_level = 3
      @user1.save!
    end

    it "should allow setting all options, and create an appropriate row" do
      @user1.should be

      rows = ::UserStatusBackdoor.all
      rows.length.should == 1
      row = rows[0]
      row.id.should == @user1.user_status_id
      row.deleted.should == false
      row.deceased.should == false
      row.gender.should == 'female'
      row.donation_level.should == 3

      user1_v2 = User.where(:name => 'User1').first
      user1_v2.deleted.should == false
      user1_v2.deceased.should == false
      user1_v2.gender.should == 'female'
      user1_v2.donation_level.should == 3
    end

    it "should expose a low-card row, but not with an ID, when read in from the DB" do
      @user1.status.should be
      @user1.status.id.should_not be

      user1_v2 = User.where(:name => 'User1').first
      user1_v2.should be
      user1_v2.status.should be
      user1_v2.status.id.should_not be
    end

    it "should not allow re-saving the status to the DB, with or without changes" do
      lambda { @user1.status.save! }.should raise_error
      @user1.deleted = true
      lambda { @user1.status.save! }.should raise_error
    end

    it "should allow changing a property, and create another row, but only for the final set" do
      previous_status_id = @user1.user_status_id

      @user1.gender = 'unknown'
      @user1.gender = 'male'
      @user1.donation_level = 1
      @user1.save!

      rows = ::UserStatusBackdoor.all
      rows.length.should == 2
      new_row = rows.detect { |r| r.id != previous_status_id }
      new_row.id.should == @user1.user_status_id
      new_row.deleted.should == false
      new_row.deceased.should == false
      new_row.gender.should == 'male'
      new_row.donation_level.should == 1
    end

    it "should allow creating another associated row, and they should be independent, even if they start with the same low-card ID" do
      user2 = ::User.new
      user2.name = 'User2'
      user2.deleted = false
      user2.deceased = false
      user2.gender = 'female'
      user2.donation_level = 3
      user2.save!

      @user1.user_status_id.should == user2.user_status_id

      user2.deleted = true
      user2.save!

      @user1.user_status_id.should_not == user2.user_status_id
      @user1.deleted.should == false
      user2.deleted.should == true

      user1_v2 = ::User.where(:name => 'User1').first
      user2_v2 = ::User.where(:name => 'User2').first

      user1_v2.deleted.should == false
      user2_v2.deleted.should == true
    end

    it "should allow multiple references from a table to the same low-card table"

    it "should handle column default values in exactly the same way as ActiveRecord"
  end
end
