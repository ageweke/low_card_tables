require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe "LowCardTables STI support" do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!
  end

  context "with the 'type' column defined in a low-card table" do
    before :each do
      migrate do
        drop_table :lctables_spec_account_statuses rescue nil
        create_table :lctables_spec_account_statuses, :low_card => true do |t|
          t.boolean :deleted, :null => false
          t.string :type
          t.integer :account_level
        end

        drop_table :lctables_spec_accounts rescue nil
        create_table :lctables_spec_accounts do |t|
          t.string :name, :null => false
          t.integer :account_status_id, :null => false, :limit => 2
        end
      end

      define_model_class(:AccountStatus, 'lctables_spec_account_statuses') { is_low_card_table }
      define_model_class(:Account, 'lctables_spec_accounts') { has_low_card_table :status; self.inheritance_column = :type }
      define_model_class(:AdminAccount, nil, :superclass => ::Account)
      define_model_class(:AccountStatusBackdoor, 'lctables_spec_account_statuses') { self.inheritance_column = :_disabled_ }
    end

    it "should work normally" do
      account1 = ::Account.new
      account1.name = "account 1"
      account1.deleted = false
      account1.account_level = 10
      account1.save!

      account2 = ::AdminAccount.new
      account2.name = "account 2"
      account2.deleted = true
      account2.account_level = 20
      account2.save!

      account1_again = ::Account.find(account1.id)
      expect(account1_again.class).to eq(::Account)
      expect(account1_again.name).to eq('account 1')
      expect(account1_again.deleted).to eq(false)
      expect(account1_again.account_level).to eq(10)

      account2_again = ::Account.find(account2.id)
      expect(account2_again.class).to eq(::AdminAccount)
      expect(account2_again.name).to eq('account 2')
      expect(account2_again.deleted).to eq(true)
      expect(account2_again.account_level).to eq(20)

      expect(::AccountStatusBackdoor.count).to eq(2)
      asid = account1.account_status_id
      status1 = ::AccountStatusBackdoor.find(asid)
      expect(status1.deleted).to eq(false)
      expect(status1.type).to eq('Account')
      expect(status1.account_level).to eq(10)
      status2 = ::AccountStatusBackdoor.find(account2.account_status_id)
      expect(status2.deleted).to eq(true)
      expect(status2.type).to eq('AdminAccount')
      expect(status2.account_level).to eq(20)
    end
  end

  context "with a normal table that uses STI, and has a low-card table" do
    before :each do
      migrate do
        drop_table :lctables_spec_account_statuses rescue nil
        create_table :lctables_spec_account_statuses, :low_card => true do |t|
          t.boolean :deleted, :null => false
          t.integer :account_level
        end

        drop_table :lctables_spec_accounts rescue nil
        create_table :lctables_spec_accounts do |t|
          t.string :name, :null => false
          t.string :type
          t.integer :account_status_id, :null => false, :limit => 2
        end
      end

      define_model_class(:AccountStatus, 'lctables_spec_account_statuses') { is_low_card_table }
      define_model_class(:Account, 'lctables_spec_accounts') { has_low_card_table :status; self.inheritance_column = :type }
      define_model_class(:AccountStatusBackdoor, 'lctables_spec_account_statuses') { }
    end

    it "should work normally with the base table" do
      account1 = ::Account.new
      account1.name = "account 1"
      account1.deleted = false
      account1.account_level = 10
      account1.save!

      account2 = ::Account.new
      account2.name = "account 2"
      account2.deleted = true
      account2.account_level = 20
      account2.save!

      account1_again = ::Account.find(account1.id)
      expect(account1_again.name).to eq('account 1')
      expect(account1_again.deleted).to eq(false)
      expect(account1_again.account_level).to eq(10)

      account2_again = ::Account.find(account2.id)
      expect(account2_again.name).to eq('account 2')
      expect(account2_again.deleted).to eq(true)
      expect(account2_again.account_level).to eq(20)

      expect(::AccountStatusBackdoor.count).to eq(2)
      status1 = ::AccountStatusBackdoor.find(account1.account_status_id)
      expect(status1.deleted).to eq(false)
      expect(status1.account_level).to eq(10)
      status2 = ::AccountStatusBackdoor.find(account2.account_status_id)
      expect(status2.deleted).to eq(true)
      expect(status2.account_level).to eq(20)
    end

    it "should work normally with the base table and a derived table" do
      define_model_class(:AdminAccount, nil, :superclass => ::Account)

      account1 = ::Account.new
      account1.name = "account 1"
      account1.deleted = false
      account1.account_level = 10
      account1.save!

      account2 = ::AdminAccount.new
      account2.name = "account 2"
      account2.deleted = true
      account2.account_level = 20
      account2.save!

      account1_again = ::Account.find(account1.id)
      expect(account1_again.class).to eq(::Account)
      expect(account1_again.name).to eq('account 1')
      expect(account1_again.deleted).to eq(false)
      expect(account1_again.account_level).to eq(10)

      account2_again = ::Account.find(account2.id)
      expect(account2_again.class.name).to eq('AdminAccount')
      expect(account2_again.name).to eq('account 2')
      expect(account2_again.deleted).to eq(true)
      expect(account2_again.account_level).to eq(20)

      expect(::AccountStatusBackdoor.count).to eq(2)
      status1 = ::AccountStatusBackdoor.find(account1.account_status_id)
      expect(status1.deleted).to eq(false)
      expect(status1.account_level).to eq(10)
      status2 = ::AccountStatusBackdoor.find(account2.account_status_id)
      expect(status2.deleted).to eq(true)
      expect(status2.account_level).to eq(20)
    end
  end
end
