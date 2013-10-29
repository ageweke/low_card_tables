require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe LowCardTables do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!
  end

  after :each do
    migrate do
      drop_table :lctables_spec_user_statuses rescue nil
      drop_table :lctables_spec_user_statuses_2 rescue nil
    end
  end

  it "should handle schema changes to the low-card table"
  it "should be able to remove low-card columns and automatically update associated rows"

  it "should throw out the cache if the schema has changed"

  it "should automatically add a unique index in migrations if explicitly told it's a low-card table" do
    migrate do
      drop_table :lctables_spec_user_statuses rescue nil
      create_table :lctables_spec_user_statuses, :low_card => true do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    # This is deliberately *not* a low-card table
    define_model_class(:UserStatus, 'lctables_spec_user_statuses') { }

    status_1 = ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    # make sure we can create a different one
    status_2 = ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 10)
    # now, make sure we can't create a duplicate
    lambda {
      ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    }.should raise_error(ActiveRecord::StatementInvalid)
  end

  it "should automatically add a unique index in migrations if there's a model saying it's a low-card table" do
    define_model_class(:UserStatus, 'lctables_spec_user_statuses') { is_low_card_table }

    migrate do
      drop_table :lctables_spec_user_statuses rescue nil
      create_table :lctables_spec_user_statuses do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    # This is deliberately *not* a low-card table
    define_model_class(:UserStatusBackdoor, 'lctables_spec_user_statuses') { }

    status_1 = ::UserStatusBackdoor.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    # make sure we can create a different one
    status_2 = ::UserStatusBackdoor.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 10)
    # now, make sure we can't create a duplicate
    lambda {
      ::UserStatusBackdoor.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    }.should raise_error(ActiveRecord::StatementInvalid)
  end

  it "should automatically change the unique index in migrations if explicitly told it's a low-card table" do
    migrate do
      drop_table :lctables_spec_user_statuses rescue nil
      create_table :lctables_spec_user_statuses, :low_card => true do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    $stderr.puts "ADDING COLUMN..."
    migrate do
      add_column :lctables_spec_user_statuses, :awesomeness, :integer, :low_card => true
    end
    $stderr.puts "ADDED COLUMN."

    # This is deliberately *not* a low-card table
    define_model_class(:UserStatus, 'lctables_spec_user_statuses') { }
    ::UserStatus.reset_column_information

    status_1 = ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5, :awesomeness => 10)
    # make sure we can create a different one
    status_2 = ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5, :awesomeness => 5)
    # now, make sure we can't create a duplicate
    lambda {
      ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5, :awesomeness => 10)
    }.should raise_error(ActiveRecord::StatementInvalid)
  end


  it "should automatically change the unique index in migrations if there's a model saying it's a low-card table"


  it "should allow removing a column, and thus collapsing rows that are now identical"

  it "should fail if there is no unique index on a low-card table at startup" do
    # Very important: we have to use a different table name here than we've used previously, because there may well
    # still be model class definitions hanging around from other tests, and there's really no good way of excluding
    # them from our code's search for model definitions.
    migrate do
      drop_table :lctables_spec_user_statuses_2 rescue nil
      create_table :lctables_spec_user_statuses_2 do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    define_model_class(:UserStatus2, 'lctables_spec_user_statuses_2') { is_low_card_table }

    e = nil
    begin
      ::UserStatus2.low_card_all_rows
    rescue LowCardTables::Errors::LowCardNoUniqueIndexError => lcnuie
      e = lcnuie
    end

    e.should be
    e.message.should match(/lctables_spec_user_statuses_2/mi)
    e.message.should match(/deceased/mi)
    e.message.should match(/deleted/mi)
    e.message.should match(/gender/mi)
    e.message.should match(/donation_level/mi)
  end
end
