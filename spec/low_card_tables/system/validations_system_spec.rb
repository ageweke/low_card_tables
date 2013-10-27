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

    class ::UserStatus
      validates :gender, :inclusion => { :in => %w{male female other} }
    end

    class ::User
      validates :donation_level, :numericality => { :greater_than_or_equal_to => 0, :less_than_or_equal_to => 10 }
    end

    @user1 = ::User.new
    @user1.name = 'User1'
    @user1.deleted = false
    @user1.deceased = false
    @user1.gender = 'female'
    @user1.donation_level = 3
    @user1.save!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should allow validations on the low-card table that are enforced" do
    @user1.gender = 'amazing'
    e = nil

    begin
      @user1.save!
    rescue => x
      e = x
    end

    e.should be
    e.class.should == LowCardTables::Errors::LowCardInvalidLowCardRowsError
    e.message.should match(/lctables_spec_user_statuses/mi)
    e.message.should match(/validation/mi)
    e.message.should match(/gender/mi)
    e.message.should match(/gender is not included in the list/mi)
    e.message.should match(/amazing/mi)
  end

  it "should allow the associated table to validate low-card data" do
    @user1.donation_level = 40
    e = nil

    begin
      @user1.save!
    rescue => x
      e = x
    end

    e.should be
    e.class.should == ::ActiveRecord::RecordInvalid
    e.message.should match(/donation level/mi)
    e.message.should match(/less than or equal to 10/mi)
  end

  it "should gracefully handle database-level rejection of a new low-card row" do
    @user1.deleted = nil
    e = nil

    begin
      @user1.save!
    rescue => x
      e = x
    end

    e.should be
    e.class.should == LowCardTables::Errors::LowCardInvalidLowCardRowsError
    e.message.should match(/lctables_spec_user_statuses/mi)
    e.message.should match(/gender/mi)
    e.message.should match(/nil/mi)
    $stderr.puts "\n\n\nMESSAGE:\n#{e.message}\n\n\n"
    e.message.should match(/ActiveRecord::StatementInvalid/mi)
  end
end
