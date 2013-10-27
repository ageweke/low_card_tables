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

  it "should allow delegating no methods from the has_low_card_table class"
  it "should allow delegating just some methods from the has_low_card_table class"

  it "should allow prefixing delegated methods with the association name easily"
  it "should allow prefixing delegated methods with any arbitrary string"

  it "should allow specifying the target class manually"
  it "should allow specifying the foreign key manually"

  it "should allow multiple references from a table to the same low-card table" do
    migrate do
      add_column :lctables_spec_users, :old_user_status_id, :integer
    end

    ::User.reset_column_information!
    class ::User < ::ActiveRecord::Base
      has_low_card_table :old_status, :class_name => ::UserStatus, :foreign_key => :old_user_status_id
    end

    raise "pending"
  end
end
