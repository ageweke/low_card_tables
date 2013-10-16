require 'low_card_tables'
require 'active_record'
require 'active_record/migration'
require 'low_card_tables/helpers/database_helper'

describe LowCardTables do
  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    class ::CreateUserStatuses < ::ActiveRecord::Migration
      def self.up
        drop_table :lctables_spec_user_statuses rescue nil
        create_table :lctables_spec_user_statuses do |t|
          t.boolean :deleted, :null => false
          t.boolean :deceased
          t.string :gender, :null => false
          t.integer :donation_level
        end

        add_index :lctables_spec_user_statuses, [ :deleted, :deceased, :gender, :donation_level ], :unique => true, :name => 'index_lctables_spec_user_statuses_on_all'
      end

      def self.down
        drop_table :lctables_spec_user_statuses
      end
    end

    class ::CreateUsers < ::ActiveRecord::Migration
      def self.up
        drop_table :lctables_spec_users rescue nil
        create_table :lctables_spec_users do |t|
          t.string :name, :null => false
          t.integer :user_status_id, :null => false, :limit => 2
        end
      end

      def self.down
        drop_table :lctables_spec_users
      end
    end

    # ::ActiveRecord::Migration.run(CreateUserStatuses)
    ::CreateUserStatuses.migrate(:up)
    ::CreateUsers.migrate(:up)

    class ::UserStatus < ActiveRecord::Base
      self.table_name = "lctables_spec_user_statuses"

      is_low_card_table
    end

    class ::User < ActiveRecord::Base
      self.table_name = "lctables_spec_users"

      has_low_card_table :status
    end
  end

  it "should say #is_low_card_table? appropriately" do
    ::UserStatus.is_low_card_table?.should be
    ::User.is_low_card_table?.should_not be
  end
end
