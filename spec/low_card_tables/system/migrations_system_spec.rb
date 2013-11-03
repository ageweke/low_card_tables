require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe "LowCardTables migration support" do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    # We need to use a different table name for every single spec in this test. That's because one of the things that
    # migrations take a look at is whether, for a given table, there's a model pointing to it that declares itself as
    # a low-card model. Once defined, it's impossible to remove these classes from ActiveRecord::Base.descendants,
    # which is what we use to look for these classes.
    @table_name = "lctables_sus_#{rand(1_000_000_000)}".to_sym

    LowCardTables::VersionSupport.clear_schema_cache!(::ActiveRecord::Base)
  end

  after :each do
    tn = @table_name
    migrate do
      drop_table tn rescue nil
      drop_table :lctables_spec_users rescue nil
      drop_table :non_low_card_table rescue nil
    end
  end

  def create_user!(name, deleted, deceased, gender, donation_level = nil, awesomeness = nil)
    user = ::User.new
    user.name = name
    user.deleted = deleted
    user.deceased = deceased
    user.gender = gender
    user.donation_level = donation_level if donation_level
    user.awesomeness = awesomeness if awesomeness
    user.save!
    user
  end

  it "should be able to migrate non-low-card tables" do
    migrate do
      create_table :non_low_card_table do |t|
        t.string :name
      end
    end

    migrate do
      add_column :non_low_card_table, :a, :integer
    end

    migrate do
      remove_column :non_low_card_table, :a
    end

    migrate do
      drop_table :non_low_card_table
    end
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
      remove_column tn, :donation_level
      add_column tn, :awesomeness, :integer, :null => false, :default => 123
    end

    ::UserStatus.reset_column_information
    @user3 = create_user!('User3', false, true, 'male', nil)
    @user3.status.awesomeness.should == 123
    @user3.awesomeness.should == 123

    @user3.awesomeness = 345

    @user3.respond_to?(:donation_level).should_not be
    @user3.respond_to?(:donation_level=).should_not be

    @user3.save!

    @user3_again = ::User.find(@user3.id)
    @user3_again.status.awesomeness.should == 345
    @user3_again.awesomeness.should == 345

    @user3_again.respond_to?(:donation_level).should_not be
    @user3_again.respond_to?(:donation_level=).should_not be
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

      drop_table :lctables_spec_users rescue nil
      create_table :lctables_spec_users do |t|
        t.string :name, :null => false
        t.integer :user_status_id, :null => false, :limit => 2
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

  %w{remove_column change_table}.each do |remove_column_type|
    before :each do
      @remove_column_proc = if remove_column_type == 'remove_column'
        lambda do |tn, opts|
          migrate do
            remove_column tn, :donation_level, opts
          end
        end
      elsif remove_column_type == 'change_table'
        lambda do |tn, opts|
          migrate do
            change_table tn, opts do |t|
              t.remove :donation_level
            end
          end
        end
      else
        raise "Unknown remove_column_type: #{remove_column_type.inspect}"
      end
    end

    it "should be able to remove low-card columns, collapse now-identical rows, and automatically update associated rows (#{remove_column_type})" do
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

      user1 = create_user!('User1', false, false, 'male', 5)
      user2 = create_user!('User2', false, false, 'male', 10)
      user3 = create_user!('User3', false, false, 'male', 7)
      user4 = create_user!('User4', false, false, 'female', 5)
      user5 = create_user!('User5', false, true, 'male', 5)

      # Make sure they all have unique status IDs
      [ user1, user2, user3, user4, user5 ].map(&:user_status_id).uniq.length.should == 5

      define_model_class(:UserStatusBackdoor, @table_name) { }
      ::UserStatusBackdoor.count.should == 5

      @remove_column_proc.call(tn, { })

      ::UserStatusBackdoor.reset_column_information
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

      [ ::User.find(user1.id), ::User.find(user2.id), ::User.find(user3.id) ].map(&:user_status_id).uniq.length.should == 1 # all the same
      [ ::User.find(user1.id), ::User.find(user4.id), ::User.find(user5.id) ].map(&:user_status_id).uniq.length.should == 3 # all different
    end

    context "with several dependent tables" do
      before :each do
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
            t.integer :other_status_id, :null => false, :limit => 2
          end

          drop_table :lctables_spec_admins rescue nil
          create_table :lctables_spec_admins do |t|
            t.string :name, :null => false
            t.integer :admin_status_id, :null => false, :limit => 2
          end
        end

        define_model_class(:UserStatus, @table_name) { is_low_card_table }
        define_model_class(:User, :lctables_spec_users) do
          has_low_card_table :status
          has_low_card_table :other_status, :class => ::UserStatus, :foreign_key => :other_status_id
        end
        define_model_class(:Admin, :lctables_spec_admins) { has_low_card_table :status, :class => ::UserStatus, :foreign_key => :admin_status_id }

        ::User.low_card_value_collapsing_update_scheme 10

        class ::Admin
          class << self
            def low_card_called(x)
              @low_card_calls ||= [ ]
              @low_card_calls << x
            end

            def low_card_calls
              @low_card_calls || [ ]
            end

            def reset_low_card_calls!
              @low_card_calls = [ ]
            end
          end

          low_card_value_collapsing_update_scheme(lambda { |map| ::Admin.low_card_called(map) })
        end

        ::Admin.reset_low_card_calls!

        @all_users = [ ]
        50.times do
          new_user = ::User.new

          new_user.name = "User#{rand(1_000_000_000)}"

          new_user.status.deleted = !! (rand(2) == 0)
          new_user.status.deceased = !! (rand(2) == 0)
          new_user.status.gender = case rand(3); when 0 then 'female'; when 1 then 'male'; when 2 then 'other'; end
          new_user.status.donation_level = rand(10)

          new_user.other_status.deleted = !! (rand(2) == 0)
          new_user.other_status.deceased = !! (rand(2) == 0)
          new_user.other_status.gender = case rand(3); when 0 then 'female'; when 1 then 'male'; when 2 then 'other'; end
          new_user.other_status.donation_level = rand(10)

          new_user.save!

          @all_users << new_user
        end

        @all_admins = [ ]
        25.times do
          new_admin = Admin.new

          new_admin.name = "Admin#{rand(1_000_000_000)}"

          new_admin.deleted = !! (rand(2) == 0)
          new_admin.deceased = !! (rand(2) == 0)
          new_admin.gender = case rand(3); when 0 then 'female'; when 1 then 'male'; when 2 then 'other'; end
          new_admin.donation_level = rand(10)

          new_admin.save!

          @all_admins << new_admin
        end

        define_model_class(:UserStatusBackdoor, @table_name) { }

        class UpdateCollector
          attr_reader :updates

          def initialize
            @updates = [ ]
          end

          def call(name, start, finish, message_id, values)
            sql = values[:sql]
            @updates << values[:sql] if sql =~ /^\s*UPDATE\s+/
          end
        end
        @collector = UpdateCollector.new

        ::ActiveSupport::Notifications.subscribe('sql.active_record', @collector)
      end

      it "should not attempt to update any associated tables if a column is removed and told not to, but should still collapse IDs (#{remove_column_type})" do
        tn = @table_name

        ::UserStatusBackdoor.count.should > 30
        ::UserStatusBackdoor.count.should <= 120

        @remove_column_proc.call(tn, :low_card_update_referring_models => false)

        # The count will depend on randomization, but the chance of us generating fewer than 6 distinct rows should be
        # extremely low -- there are 120 possible (2 deleted * 2 deceased * 3 genders)
        ::UserStatusBackdoor.count.should >= 6
        ::UserStatusBackdoor.count.should <= 12

        ::User.all.each do |user|
          previous_user = @all_users.detect { |u| u.id == user.id }
          user.user_status_id.should == previous_user.user_status_id
        end

        ::Admin.all.each do |admin|
          previous_admin = @all_admins.detect { |u| u.id == admin.id }
          admin.admin_status_id.should == previous_admin.admin_status_id
        end

        admin_change_maps = ::Admin.low_card_calls
        admin_change_maps.length.should == 0
      end

      it "should not attempt to update any associated tables or collapse IDs if a column is removed and told not to (#{remove_column_type})" do
        tn = @table_name

        ::UserStatusBackdoor.count.should > 30
        ::UserStatusBackdoor.count.should <= 120

        @remove_column_proc.call(tn, :low_card_collapse_rows => false)

        ::UserStatusBackdoor.count.should > 30
        ::UserStatusBackdoor.count.should <= 120

        ::User.all.each do |user|
          previous_user = @all_users.detect { |u| u.id == user.id }
          user.user_status_id.should == previous_user.user_status_id
        end

        ::Admin.all.each do |admin|
          previous_admin = @all_admins.detect { |u| u.id == admin.id }
          admin.admin_status_id.should == previous_admin.admin_status_id
        end

        admin_change_maps = ::Admin.low_card_calls
        admin_change_maps.length.should == 0
      end

      it "should update all associated tables, including multiple references to the same low-card table, in chunks as specified, when a column is removed (#{remove_column_type})" do
        tn = @table_name

        # The count will depend on randomization, but the chance of us generating fewer than 30 distinct rows should be
        # extremely low -- there are 120 possible (2 deleted * 2 deceased * 3 genders * 10 donation_levels)
        ::UserStatusBackdoor.count.should > 30
        ::UserStatusBackdoor.count.should <= 120

        @remove_column_proc.call(tn, { })

        # The count will depend on randomization, but the chance of us generating fewer than 6 distinct rows should be
        # extremely low -- there are 120 possible (2 deleted * 2 deceased * 3 genders)
        ::UserStatusBackdoor.count.should >= 6
        ::UserStatusBackdoor.count.should <= 12

        ::UserStatusBackdoor.reset_column_information
        all_user_status_ids = ::UserStatusBackdoor.all.map(&:id)

        ::User.all.each do |verify_user|
          orig_user = @all_users.detect { |u| u.id == verify_user.id }

          verify_user.status.deleted.should == orig_user.status.deleted
          verify_user.status.deceased.should == orig_user.status.deceased
          verify_user.status.gender.should == orig_user.status.gender
          verify_user.status.respond_to?(:donation_level).should_not be
          verify_user.respond_to?(:donation_level).should_not be
        end

        new_admin_status_ids = ::Admin.all.sort_by(&:id).map(&:admin_status_id)
        orig_admin_status_ids = @all_admins.sort_by(&:id).map(&:admin_status_id)

        new_admin_status_ids.should == orig_admin_status_ids # no change

        admin_change_maps = ::Admin.low_card_calls
        admin_change_maps.length.should == 1

        admin_change_maps[0].each do |new_row, old_rows|
          old_rows.length.should >= 1
          old_rows.each do |old_row|
            old_row.deleted.should == new_row.deleted
            old_row.deceased.should == new_row.deceased
            old_row.gender.should == new_row.gender
          end
        end

        collapses = admin_change_maps[0].size
        expected_update_count = collapses
        expected_update_count *= 2 # one for each column in the table
        expected_update_count *= 5 # 50 rows in batches of 10

        user_updates = @collector.updates.select { |u| u =~ /lctables_spec_users/ }
        user_updates.length.should == expected_update_count
      end
    end
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
