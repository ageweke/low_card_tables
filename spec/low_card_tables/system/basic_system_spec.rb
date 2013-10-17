require 'low_card_tables'
require 'active_record'
require 'active_record/migration'
require 'low_card_tables/helpers/database_helper'

describe LowCardTables do
  def migrate(&block)
    migration_class = Class.new(::ActiveRecord::Migration)
    metaclass = migration_class.class_eval { class << self; self; end }
    metaclass.instance_eval { define_method(:up, &block) }
    migration_class.migrate(:up)
  end

  def define_model_class(name, table_name, &block)
    model_class = Class.new(::ActiveRecord::Base)
    ::Object.const_set(name, model_class)
    model_class.table_name = table_name
    model_class.class_eval(&block)
  end

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!
  end

  context "with normal table setup" do
    before :each do
      migrate do
        drop_table :lctables_spec_user_statuses rescue nil
        create_table :lctables_spec_user_statuses do |t|
          t.boolean :deleted, :null => false
          t.boolean :deceased
          t.string :gender, :null => false
          t.integer :donation_level
        end

        add_index :lctables_spec_user_statuses, [ :deleted, :deceased, :gender, :donation_level ], :unique => true, :name => 'index_lctables_spec_user_statuses_on_all'

        drop_table :lctables_spec_users rescue nil
        create_table :lctables_spec_users do |t|
          t.string :name, :null => false
          t.integer :user_status_id, :null => false, :limit => 2
        end
      end

      define_model_class(:UserStatus, 'lctables_spec_user_statuses') { is_low_card_table }
      define_model_class(:User, 'lctables_spec_users') { has_low_card_table :status }
      define_model_class(:UserStatusBackdoor, 'lctables_spec_user_statuses') { }
    end

    after :each do
      migrate do
        drop_table :lctables_spec_user_statuses rescue nil
        drop_table :lctables_spec_users rescue nil
      end
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
        # we're really just testing the :before block here
        @user1.should be

        rows = ::UserStatusBackdoor.all
        rows.length.should == 1
        row = rows[0]
        row.id.should == @user1.user_status_id
        row.deleted.should == false
        row.deceased.should == false
        row.gender.should == 'female'
        row.donation_level.should == 3
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
    end
  end
end
