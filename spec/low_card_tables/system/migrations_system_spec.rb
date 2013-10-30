require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'
require 'pry'

describe LowCardTables do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    # We need to use a different table name for every single spec in this test. That's because one of the things that
    # migrations take a look at is whether, for a given table, there's a model pointing to it that declares itself as
    # a low-card model. Once defined, it's impossible to remove these classes from ActiveRecord::Base.descendants,
    # which is what we use to look for these classes.
    @table_name = "lctables_sus_#{rand(1_000_000_000)}".to_sym
  end

  after :each do
    tn = @table_name
    migrate do
      drop_table tn rescue nil
    end
  end

  def create_user!(name, deleted, deceased, gender, donation_level, awesomeness = nil)
    user = ::User.new
    user.name = name
    user.deleted = deleted
    user.deceased = deceased
    user.gender = gender
    user.donation_level = donation_level
    user.awesomeness = awesomeness if awesomeness
    user.save!
    user
  end

  it "should handle schema changes to the low-card table" do
    tn = @table_name
    migrate do
      drop_table tn rescue nil
      create_table tn, :low_card => true do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end

      drop_table :lctables_spec_users rescue nil
      create_table :lctables_spec_users do |t|
        t.string :name, :null => false
        t.integer :user_status_id, :null => false, :limit => 2
      end
    end

    define_model_class(:UserStatus, @table_name) { is_low_card_table }
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status }

    @user1 = create_user!('User1', false, true, 'male', 5)
    @user2 = create_user!('User2', false, false, 'female', 5)

    migrate do
      add_column tn, :awesomeness, :integer, :null => false, :default => 123
    end

    ::UserStatus.reset_column_information
    @user3 = create_user!('User3', false, true, 'male', 10)
    @user3.status.awesomeness.should == 123
    @user3.awesomeness.should == 123

    @user3.awesomeness = 345
    @user3.save!

    @user3_again = ::User.find(@user3.id)
    @user3_again.status.awesomeness.should == 345
    @user3_again.awesomeness.should == 345
  end

  it "should automatically add a unique index in migrations if explicitly told it's a low-card table" do
    tn = @table_name
    migrate do
      drop_table tn rescue nil
      create_table tn, :low_card => true do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    # This is deliberately *not* a low-card table
    define_model_class(:UserStatus, @table_name) { }

    status_1 = ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    # make sure we can create a different one
    status_2 = ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 10)
    # now, make sure we can't create a duplicate
    lambda {
      ::UserStatus.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    }.should raise_error(ActiveRecord::StatementInvalid)
  end

  it "should automatically add a unique index in migrations if there's a model saying it's a low-card table" do
    define_model_class(:UserStatus, @table_name) { is_low_card_table }
    tn = @table_name

    migrate do
      drop_table tn rescue nil
      create_table tn do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    # This is deliberately *not* a low-card table
    define_model_class(:UserStatusBackdoor, @table_name) { }

    status_1 = ::UserStatusBackdoor.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    # make sure we can create a different one
    status_2 = ::UserStatusBackdoor.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 10)
    # now, make sure we can't create a duplicate
    lambda {
      ::UserStatusBackdoor.create!(:deleted => false, :deceased => false, :gender => 'male', :donation_level => 5)
    }.should raise_error(ActiveRecord::StatementInvalid)
  end

  def check_unique_index_modification(explicit_or_model, common_hash, first, second, third, &block)
    if explicit_or_model == :model
      define_model_class(:UserStatus, @table_name) { is_low_card_table }
    end

    tn = @table_name
    migrate do
      drop_table tn rescue nil
      create_table tn do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    migrate(&block)

    # This is deliberately *not* a low-card table
    define_model_class(:UserStatusBackdoor, @table_name) { }
    ::UserStatusBackdoor.reset_column_information

    status_1 = ::UserStatusBackdoor.create!(common_hash.merge(first))
    # make sure we can create a different one
    status_2 = ::UserStatusBackdoor.create!(common_hash.merge(second))
    # now, make sure we can't create a duplicate
    lambda {
      ::UserStatusBackdoor.create!(common_hash.merge(third))
    }.should raise_error(ActiveRecord::StatementInvalid)
  end

  %w{explicit model}.map(&:to_sym).each do |explicit_or_model|
    def extra_options(explicit_or_model)
      if explicit_or_model == :explicit then { :low_card => true } else { } end
    end

    describe "should automatically change the unique index in migrations if told it's a low-card table (#{explicit_or_model})" do
      it "using #add_column" do
        tn = @table_name
        eo = extra_options(explicit_or_model)
        check_unique_index_modification(explicit_or_model, { :deleted => false, :deceased => false, :gender => 'male', :donation_level => 5 },
          { :awesomeness => 10 },
          { :awesomeness => 5 },
          { :awesomeness => 10 }) do
          add_column tn, :awesomeness, :integer, eo
        end
      end

      it "using #remove_column" do
        tn = @table_name
        eo = extra_options(explicit_or_model)
        check_unique_index_modification(explicit_or_model, { :deleted => false, :deceased => false },
          { :gender => 'male' },
          { :gender => 'female' },
          { :gender => 'male' }) do
          if eo.size > 0
            remove_column tn, :donation_level, eo
          else
            remove_column tn, :donation_level
          end
        end
      end

      it "using #change_table" do
        tn = @table_name
        eo = extra_options(explicit_or_model)
        check_unique_index_modification(explicit_or_model, { :deleted => false, :deceased => false, :gender => 'male', :donation_level => 5 },
          { :awesomeness => 10 },
          { :awesomeness => 5 },
          { :awesomeness => 10 }) do
          change_table tn, eo do |t|
            t.integer :awesomeness
          end
        end
      end

      it "using #change_low_card_table" do
        tn = @table_name
        eo = extra_options(explicit_or_model)
        check_unique_index_modification(explicit_or_model, { :deleted => false, :deceased => false, :gender => 'male', :donation_level => 5 },
          { :awesomeness => 10 },
          { :awesomeness => 5 },
          { :awesomeness => 10 }) do
          change_low_card_table(tn) do
            execute "ALTER TABLE #{tn} ADD COLUMN awesomeness INTEGER"
          end
        end
      end
    end
  end

  it "should remove the unique index during #change_low_card_table" do
    tn = @table_name
    migrate do
      drop_table tn rescue nil
      create_table tn, :low_card => true do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    define_model_class(:UserStatus, @table_name) { is_low_card_table }
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status }

    user1 = create_user!('User1', false, false, 'male', 5)
    status_1 = user1.status
    status_1_id = user1.user_status_id
    status_1_id.should > 0

    migrate do
      change_low_card_table(tn) do
        status_1_attributes = status_1.attributes.dup
        status_1_attributes.delete(:id)
        status_1_attributes.delete("id")

        new_status = ::UserStatus.new(status_1_attributes)
        new_status.save_low_card_row!

        new_status.id.should_not == status_1.id
        new_status.id.should > 0

        ::UserStatus.delete_all("id = #{new_status.id}")
      end
    end
  end

  it "should be able to remove low-card columns, collapse now-identical rows, and automatically update associated rows" do
    tn = @table_name
    migrate do
      drop_table tn rescue nil
      create_table tn, :low_card => true do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    define_model_class(:UserStatus, @table_name) { is_low_card_table }
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status }

    user1 = create_user!('User1', false, false, 'male', 5)
    user2 = create_user!('User2', false, false, 'male', 10)
    user3 = create_user!('User3', false, false, 'male', 7)
    user4 = create_user!('User4', false, false, 'female', 5)
    user5 = create_user!('User5', false, true, 'male', 5)

    # Make sure they all have unique status IDs
    [ user1, user2, user3, user4, user5 ].map(&:user_status_id).uniq.length.should == 5

    define_model_class(:UserStatusBackdoor, @table_name) { }
    ::UserStatusBackdoor.count.should == 5

    migrate do
      remove_column tn, :donation_level
    end

    [ user1, user2, user3 ].map(&:user_status_id).uniq.length.should == 3 # all different
    [ user1, user4, user5 ].map(&:user_status_id).uniq.length.should == 1 # all the same

    ::UserStatusBackdoor.count.should == 3

    user123_status = ::UserStatusBackdoor.find(user1.user_status_id)
    user123_status.deleted.should == false
    user123_status.deceased.should == false
    user123_status.gender.should == 'male'

    user4_status = ::UserStatusBackdoor.find(user4.user_status_id)
    user4_status.deleted.should == false
    user4_status.deceased.should == false
    user4_status.gender.should == 'female'

    user5_status = ::UserStatusBackdoor.find(user5.user_status_id)
    user5_status.deleted.should == false
    user5_status.deceased.should == true
    user5_status.gender.should == 'male'
  end

  it "should fail if there is no unique index on a low-card table at startup" do
    tn = @table_name

    migrate do
      drop_table tn rescue nil
      create_table tn do |t|
        t.boolean :deleted, :null => false
        t.boolean :deceased
        t.string :gender, :null => false
        t.integer :donation_level
      end
    end

    define_model_class(:UserStatus, @table_name) { is_low_card_table }

    e = nil
    begin
      ::UserStatus.low_card_all_rows
    rescue LowCardTables::Errors::LowCardNoUniqueIndexError => lcnuie
      e = lcnuie
    end

    e.should be
    e.message.should match(/#{@table_name}/mi)
    e.message.should match(/deceased/mi)
    e.message.should match(/deleted/mi)
    e.message.should match(/gender/mi)
    e.message.should match(/donation_level/mi)
  end
end
