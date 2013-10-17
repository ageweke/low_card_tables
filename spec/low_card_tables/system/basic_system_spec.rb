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

    it "should allow setting all options, and create an appropriate row" do
      u = ::User.new
      u.name = 'User1'
      u.deleted = false
      u.deceased = false
      u.gender = 'female'
      u.donation_level = 3
      u.save!
    end

    it "should expose a low-card row, but not with an ID" do
      u = User.where(:name => 'User1').first
      u.should be
      u.user_status.should be
      u.user_status.id.should_not be
    end
  end
end
