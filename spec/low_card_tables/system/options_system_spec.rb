require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe "LowCardTables association options" do
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

  it "should allow multiple references from a table to the same low-card table, and method delegation should be from the first one added" do
    migrate do
      add_column :lctables_spec_users, :old_user_status_id, :integer
    end

    ::User.reset_column_information
    class ::User < ::ActiveRecord::Base
      has_low_card_table :old_status, :class => ::UserStatus, :foreign_key => :old_user_status_id
    end

    user1 = ::User.new

    user1.name = 'User1'

    user1.deleted = false
    user1.deceased = false
    user1.gender = 'female'
    user1.donation_level = 8

    user1.old_status.deleted = true
    user1.old_status.deceased = false
    user1.old_status.gender = 'male'
    user1.old_status.donation_level = 3

    user1.save!

    user1.user_status_id.should_not == user1.old_user_status_id

    user1_again = ::User.find(user1.id)

    user1_again.user_status_id.should == user1.user_status_id
    user1_again.old_user_status_id.should == user1.old_user_status_id

    user1_again.status.deleted.should == false
    user1_again.status.deceased.should == false
    user1_again.status.gender.should == 'female'
    user1_again.status.donation_level.should == 8

    user1_again.old_status.deleted.should == true
    user1_again.old_status.deceased.should == false
    user1_again.old_status.gender.should == 'male'
    user1_again.old_status.donation_level.should == 3
  end

  it "should not blow away methods that are already there, in the class itself, but still allow calls to super" do
    define_model_class(:UserTest, :lctables_spec_users) do
      def deleted
        [ @_other_deleted, super ]
      end

      def deleted=(x)
        @_other_deleted ||= [ ]
        @_other_deleted << x
        super(x)
      end

      has_low_card_table :status, :class => ::UserStatus
    end

    user1 = ::UserTest.new

    user1.deleted.should == [ nil, nil ]
    user1.deleted = true
    user1.deleted.should == [ [ true ], true ]
    user1.deleted = false
    user1.deleted.should == [ [ true, false ], false ]
  end

  it "should override methods defined in a superclass"

  it "should allow defining an association twice, and the second one should win"

  it "should allow delegating no methods from the has_low_card_table class"
  it "should allow delegating just some methods from the has_low_card_table class"

  it "should allow prefixing delegated methods with the association name easily"
  it "should allow prefixing delegated methods with any arbitrary string"

  it "should allow specifying the target class manually"
  it "should allow specifying the foreign key manually"
end
