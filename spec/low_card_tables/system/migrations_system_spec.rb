require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

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

  it "should handle schema changes to the low-card table"
  it "should be able to remove low-card columns and automatically update associated rows"

  it "should throw out the cache if the schema has changed"

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

  it "should allow removing a column, and thus collapsing rows that are now identical"

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
