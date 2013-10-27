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

      context "with basic validations" do
        before :each do
          class ::UserStatus
            validates :gender, :inclusion => { :in => %w{male female other} }
          end

          class ::User
            validates :donation_level, :numericality => { :greater_than_or_equal_to => 0, :less_than_or_equal_to => 10 }
          end
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
          e.class.should == ActiveRecord::RecordInvalid
          e.message.should match(/donation level/mi)
          e.message.should match(/less than or equal to 10/mi)
        end
      end

      it "should gracefully handle database-level rejection of a new low-card row" do
        @user1.gender = nil
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
        e.message.should match(/ActiveRecord::StatementInvalid/mi)
      end

      it "should allow multiple references from a table to the same low-card table"

      it "should handle schema changes to the low-card table"
      it "should be able to remove low-card columns and automatically update associated rows"

      it "should cache low-card rows in memory"
      it "should throw out the cache if the schema has changed"

      it "should notify listeners when refreshing its cache"
      it "should notify listeners when adding a new row"

      it "should allow delegating no methods from the has_low_card_table class"
      it "should allow delegating just some methods from the has_low_card_table class"

      it "should allow specifying the target class manually"
      it "should allow specifying the foreign key manually"

      it "should allow 'where' clauses to behave naturally"
      it "should compose 'where' clauses correctly"

      it "should allow using low-card properties in the default scope"
      it "should allow using low-card properties in arbitrary scopes"
      it "should pick up new low-card rows when using a low-card property in an arbitrary scope"

      it "should automatically add a unique index in migrations"
      it "should allow removing a column, and thus collapsing rows that are now identical"
      it "should fail if there is no unique index on a low-card table at startup"
    end
  end
end
