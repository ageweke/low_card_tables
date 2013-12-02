require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'
require 'low_card_tables/helpers/query_spy_helper'

describe "LowCardTables bulk operations" do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!
  end

  context "with standard setup" do
    before :each do
      create_standard_system_spec_tables!
      create_standard_system_spec_models!

      # create several low-card rows in our table
      user = User.new
      user.name = 'User1'
      user.deleted = false
      user.deceased = false
      user.gender = 'male'
      user.donation_level = 5
      user.save!

      @hash1_id = user.user_status_id

      user.deleted = true
      user.save!

      @hash2_id = user.user_status_id

      user.deleted = false
      user.gender = 'female'
      user.donation_level = 9
      user.save!

      @hash3_id = user.user_status_id

      @hash1 = { :deleted => false, :deceased => false, :gender => 'male', :donation_level => 5 }.with_indifferent_access
      @hash2 = { :deleted => true, :deceased => false, :gender => 'male', :donation_level => 5 }.with_indifferent_access
      @hash3 = { :deleted => false, :deceased => false, :gender => 'female', :donation_level => 9 }.with_indifferent_access
      @hash4 = { :deleted => false, :deceased => true, :gender => 'female', :donation_level => 3 }.with_indifferent_access
      @hash5 = { :deleted => false, :deceased => true, :gender => 'male', :donation_level => 2 }.with_indifferent_access
    end

    after :each do
      drop_standard_system_spec_tables!
    end

    def verify_row(row, deleted, deceased, gender, donation_level)
      row.deleted.should == deleted
      row.deceased.should == deceased
      row.gender.should == gender
      row.donation_level.should == donation_level
    end

    def verify_by_id(rows, id, deleted, deceased, gender, donation_level)
      row = rows.detect { |r| r.id == id }
      row.should be
      verify_row(row, deleted, deceased, gender, donation_level)
    end

    def ensure_zero_database_calls(&block)
      LowCardTables::Helpers::QuerySpyHelper.with_query_spy('lctables_spec_user_statuses') do |spy|
        ::UserStatus.low_card_all_rows

        pre_count = spy.call_count
        block.call
        post_count = spy.call_count
        post_count.should == pre_count
      end
    end

    it "should allow for bulk retrieval of subsets of rows" do
      ensure_zero_database_calls do
        hash_selector_1 = { :deleted => false, :deceased => false }
        hash_selector_2 = { :deceased => false, :donation_level => 5 }
        results = ::UserStatus.low_card_rows_matching([ hash_selector_1, hash_selector_2 ])

        results.size.should == 2

        results[hash_selector_1].should be
        results[hash_selector_1].length.should == 2
        results[hash_selector_1].map(&:id).sort.should == [ @hash1_id, @hash3_id ].sort

        verify_by_id(results[hash_selector_1], @hash1_id, false, false, 'male', 5)
        verify_by_id(results[hash_selector_1], @hash3_id, false, false, 'female', 9)

        results[hash_selector_2].should be
        results[hash_selector_2].length.should == 2
        results[hash_selector_2].map(&:id).sort.should == [ @hash1_id, @hash2_id ].sort

        verify_by_id(results[hash_selector_2], @hash1_id, false, false, 'male', 5)
        verify_by_id(results[hash_selector_2], @hash2_id, true, false, 'male', 5)
      end
    end

    it "should allow for bulk retrieval of subsets of IDs" do
      ensure_zero_database_calls do
        hash_selector_1 = { :deleted => false, :deceased => false }
        hash_selector_2 = { :deceased => false, :donation_level => 5 }
        results = ::UserStatus.low_card_ids_matching([ hash_selector_1, hash_selector_2 ])

        results.size.should == 2

        results[hash_selector_1].should be
        results[hash_selector_1].length.should == 2
        results[hash_selector_1].sort.should == [ @hash1_id, @hash3_id ].sort

        results[hash_selector_2].should be
        results[hash_selector_2].length.should == 2
        results[hash_selector_2].sort.should == [ @hash1_id, @hash2_id ].sort
      end
    end

    it "should raise an exception if passed invalid values in the hashes" do
      ensure_zero_database_calls do
        lambda { ::UserStatus.low_card_rows_matching([ { :deleted => false, :foo => 1 }]) }.should raise_error(LowCardTables::Errors::LowCardColumnNotPresentError)
        lambda { ::UserStatus.low_card_ids_matching([ { :deleted => false, :foo => 1 }]) }.should raise_error(LowCardTables::Errors::LowCardColumnNotPresentError)
      end
    end

    it "should raise an exception if there are missing values in the hashes" do
      ensure_zero_database_calls do
        lambda { ::UserStatus.low_card_find_rows_for([ { :deleted => false, :gender => 'male', :donation_level => 5 }]) }.should raise_error(LowCardTables::Errors::LowCardColumnNotSpecifiedError)
        lambda { ::UserStatus.low_card_find_ids_for([ { :deleted => false, :gender => 'male', :donation_level => 5 }]) }.should raise_error(LowCardTables::Errors::LowCardColumnNotSpecifiedError)
      end
    end

    context "with a table with defaults" do
      before :each do
        migrate do
          drop_table :lctables_spec_bulk_defaults rescue nil
          create_table :lctables_spec_bulk_defaults do |t|
            t.boolean :deleted, :null => false
            t.string :gender, :null => false, :default => 'female'
            t.integer :donation_level, :default => 10
          end

          add_index :lctables_spec_bulk_defaults, [ :deleted, :gender, :donation_level ], :unique => true, :name => 'index_lctables_spec_bulk_defaults_on_all'

          drop_table :lctables_spec_users_defaults rescue nil
          create_table :lctables_spec_users_defaults do |t|
            t.string :name, :null => false
            t.integer :user_status_id, :null => false, :limit => 2
          end
        end

        define_model_class(:UserStatusBulkDefaults, :lctables_spec_bulk_defaults) { is_low_card_table }
        define_model_class(:UserBulkDefaults, :lctables_spec_users_defaults) { has_low_card_table :status, :class => 'UserStatusBulkDefaults', :foreign_key => :user_status_id }
      end

      after :each do
        migrate do
          drop_table :lctables_spec_bulk_defaults rescue nil
        end
      end

      it "should fill in missing values in the hashes with defaults when finding rows" do
        u1 = ::UserBulkDefaults.new
        u1.name = 'User 1'
        u1.deleted = false
        u1.save!

        u1.name.should == 'User 1'
        u1.deleted.should == false
        u1.gender.should == 'female'
        u1.donation_level.should == 10

        u2 = ::UserBulkDefaults.new
        u2.name = 'User 2'
        u2.deleted = false
        u2.gender = 'female'
        u2.donation_level = 8
        u2.save!

        status_id_1 = u1.user_status_id
        status_id_1.should be
        status_row_1 = ::UserStatusBulkDefaults.find(status_id_1)

        status_id_2 = u2.user_status_id
        status_id_2.should be
        status_row_2 = ::UserStatusBulkDefaults.find(status_id_2)

        lambda { ::UserStatusBulkDefaults.low_card_find_rows_for({ :gender => 'female' }) }.should raise_error(LowCardTables::Errors::LowCardColumnNotSpecifiedError)
        ::UserStatusBulkDefaults.low_card_find_rows_for({ :deleted => false }).should == status_row_1
        ::UserStatusBulkDefaults.low_card_find_rows_for({ :deleted => false, :donation_level => 8 }).should == status_row_2
      end

      it "should fill in missing values in the hashes with defaults when creating rows" do
        row = ::UserStatusBulkDefaults.low_card_find_or_create_rows_for({ :deleted => false })
        row.should be
        row.id.should be
        row.id.should > 0

        row.deleted.should == false
        row.gender.should == 'female'
        row.donation_level.should == 10
      end
    end

    it "should allow for bulk retrieval of rows by IDs" do
      ensure_zero_database_calls do
        results = ::UserStatus.low_card_rows_for_ids([ @hash1_id, @hash3_id ])
        results.size.should == 2
        verify_row(results[@hash1_id], false, false, 'male', 5)
        verify_row(results[@hash3_id], false, false, 'female', 9)
      end
    end

    it "should raise if asked for an ID that's not present" do
      random_id = 1_000_000 + rand(1_000_000)

      e = nil
      begin
        ::UserStatus.low_card_rows_for_ids([ @hash1_id, @hash3_id, random_id ])
      rescue => x
        e = x
      end

      e.should be
      e.class.should == LowCardTables::Errors::LowCardIdNotFoundError
      e.ids.should == [ random_id ]
    end

    it "should allow for retrieving all rows" do
      ensure_zero_database_calls do
        results = ::UserStatus.low_card_all_rows
        results.size.should == 3
        verify_by_id(results, @hash1_id, false, false, 'male', 5)
        verify_by_id(results, @hash2_id, true, false, 'male', 5)
        verify_by_id(results, @hash3_id, false, false, 'female', 9)
      end
    end

    it "should allow retrieving an individual row directly" do
      ensure_zero_database_calls do
        row = ::UserStatus.low_card_row_for_id(@hash2_id)
        verify_row(row, true, false, 'male', 5)
      end
    end

    def row_from_hash(h)
      ::UserStatus.new(h)
    end

    %w{hash object}.each do |input_type|
      def to_desired_input_type(hashes, type)
        case type
        when 'hash' then hashes
        when 'object' then hashes.map { |h| ::UserStatus.new(h) }
        else raise "Unknown input_type: #{input_type.inspect}"
        end
      end

      it "should allow for bulk retrieval-and-creation of rows by #{input_type}" do
        input = to_desired_input_type([ @hash1, @hash3, @hash4, @hash5 ], input_type)

        result = ::UserStatus.low_card_find_or_create_rows_for(input)
        result.size.should == 4

        result[input[0]].id.should == @hash1_id
        result[@hash2].should be_nil
        result[input[1]].id.should == @hash3_id

        known_ids = [ @hash1_id, @hash2_id, @hash3_id ]
        known_ids.include?(result[input[2]].id).should_not be
        known_ids.include?(result[input[3]].id).should_not be

        verify_row(result[input[2]], false, true, 'female', 3)
        verify_row(result[input[3]], false, true, 'male', 2)

        ::UserStatusBackdoor.count.should == 5
        verify_row(::UserStatusBackdoor.find(result[input[0]].id), false, false, 'male', 5)
        verify_row(::UserStatusBackdoor.find(result[input[1]].id), false, false, 'female', 9)
        verify_row(::UserStatusBackdoor.find(result[input[2]].id), false, true, 'female', 3)
        verify_row(::UserStatusBackdoor.find(result[input[3]].id), false, true, 'male', 2)
      end

      it "should allow for bulk retrieval-and-creation of IDs by #{input_type}" do
        input = to_desired_input_type([ @hash1, @hash3, @hash4, @hash5 ], input_type)

        result = ::UserStatus.low_card_find_or_create_ids_for(input)
        result.size.should == 4

        result[input[0]].should == @hash1_id
        result[@hash2].should be_nil
        result[input[1]].should == @hash3_id

        known_ids = [ @hash1_id, @hash2_id, @hash3_id ]
        known_ids.include?(result[input[2]]).should_not be
        known_ids.include?(result[input[3]]).should_not be

        ::UserStatusBackdoor.count.should == 5
        verify_row(::UserStatusBackdoor.find(result[input[0]]), false, false, 'male', 5)
        verify_row(::UserStatusBackdoor.find(result[input[1]]), false, false, 'female', 9)
        verify_row(::UserStatusBackdoor.find(result[input[2]]), false, true, 'female', 3)
        verify_row(::UserStatusBackdoor.find(result[input[3]]), false, true, 'male', 2)
      end

      it "should allow for bulk retrieval of rows with exact matches by #{input_type}" do
        ensure_zero_database_calls do
          results = ::UserStatus.low_card_find_rows_for([ @hash1, @hash2, @hash3, @hash4, @hash5 ])
          results.size.should == 5

          verify_row(results[@hash1], false, false, 'male', 5)
          verify_row(results[@hash2], true, false, 'male', 5)
          verify_row(results[@hash3], false, false, 'female', 9)

          results[@hash4].should be_nil
          results[@hash5].should be_nil
        end
      end

      it "should allow for bulk retrieval of IDs with exact matches by #{input_type}" do
        ensure_zero_database_calls do
          input = to_desired_input_type([ @hash1, @hash2, @hash3, @hash4, @hash5 ], input_type)
          results = ::UserStatus.low_card_find_ids_for(input)
          results.size.should == 5

          results[input[0]].should == @hash1_id
          results[input[1]].should == @hash2_id
          results[input[2]].should == @hash3_id

          results[input[3]].should be_nil
          results[input[4]].should be_nil
        end
      end
    end
  end
end
