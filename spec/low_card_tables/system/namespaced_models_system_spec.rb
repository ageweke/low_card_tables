require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe "LowCardTables namespaced models operations" do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should allow namespaced models for both tables, if specified explicitly" do
    module ::LowCardSpecNamespace3; end

    user_status_class = Class.new(::ActiveRecord::Base)
    ::LowCardSpecNamespace3.send(:remove_const, 'UserStatus') rescue nil
    ::LowCardSpecNamespace3.const_set(:UserStatus, user_status_class)
    user_status_class.table_name = 'lctables_spec_user_statuses'
    user_status_class.is_low_card_table

    user_class = Class.new(::ActiveRecord::Base)
    ::LowCardSpecNamespace3.send(:remove_const, :User) rescue nil
    ::LowCardSpecNamespace3.const_set(:User, user_class)
    user_class.table_name = 'lctables_spec_users'
    user_class.has_low_card_table :status

    @user1 = ::LowCardSpecNamespace3::User.new
    @user1.name = 'User1'
    @user1.deleted = false
    @user1.deceased = false
    @user1.gender = 'female'
    @user1.donation_level = 3
    @user1.save!

    user1_again = ::LowCardSpecNamespace3::User.find(@user1.id)
    expect(user1_again.name).to eq('User1')
    expect(user1_again.deleted).to eq(false)
    expect(user1_again.deceased).to eq(false)
    expect(user1_again.gender).to eq('female')
    expect(user1_again.donation_level).to eq(3)
  end

  it "should allow namespaced models for both tables, if specified explicitly" do
    module ::LowCardSpecNamespace1; end
    module ::LowCardSpecNamespace2; end

    user_status_class = Class.new(::ActiveRecord::Base)
    ::LowCardSpecNamespace2.send(:remove_const, :UserStatus) rescue nil
    ::LowCardSpecNamespace2.const_set(:UserStatus, user_status_class)
    user_status_class.table_name = 'lctables_spec_user_statuses'
    user_status_class.is_low_card_table

    user_class = Class.new(::ActiveRecord::Base)
    ::LowCardSpecNamespace1.send(:remove_const, :User) rescue nil
    ::LowCardSpecNamespace1.const_set(:User, user_class)
    user_class.table_name = 'lctables_spec_users'
    user_class.has_low_card_table :status, :class => user_status_class

    @user1 = ::LowCardSpecNamespace1::User.new
    @user1.name = 'User1'
    @user1.deleted = false
    @user1.deceased = false
    @user1.gender = 'female'
    @user1.donation_level = 3
    @user1.save!

    user1_again = ::LowCardSpecNamespace1::User.find(@user1.id)
    expect(user1_again.name).to eq('User1')
    expect(user1_again.deleted).to eq(false)
    expect(user1_again.deceased).to eq(false)
    expect(user1_again.gender).to eq('female')
    expect(user1_again.donation_level).to eq(3)
  end
end
