require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'
require 'low_card_tables/helpers/query_spy_helper'

describe LowCardTables do
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

    it "should allow for bulk retrieval of rows with exact matches" do
      ensure_zero_database_calls do
        results = ::UserStatus.low_card_find_rows_for([ @hash1, @hash2, @hash3, @hash4, @hash5 ])
        results.size.should == 3

        verify_row(results[@hash1], false, false, 'male', 5)
        verify_row(results[@hash2], true, false, 'male', 5)
        verify_row(results[@hash3], false, false, 'female', 9)

        results[@hash4].should_not be
        results[@hash5].should_not be
      end
    end

    it "should allow for bulk retrieval of IDs with exact matches" do
      ensure_zero_database_calls do
        results = ::UserStatus.low_card_find_ids_for([ @hash1, @hash2, @hash3, @hash4, @hash5 ])
        results.size.should == 3

        results[@hash1].should == @hash1_id
        results[@hash2].should == @hash2_id
        results[@hash3].should == @hash3_id

        results[@hash4].should_not be
        results[@hash5].should_not be
      end
    end

    it "should raise an exception if there are missing values in the hashes" do
      ensure_zero_database_calls do
        lambda { ::UserStatus.low_card_find_rows_for([ { :deleted => false, :gender => 'male', :donation_level => 5 }]) }.should raise_error(LowCardTables::Errors::LowCardColumnNotSpecifiedError)
        lambda { ::UserStatus.low_card_find_ids_for([ { :deleted => false, :gender => 'male', :donation_level => 5 }]) }.should raise_error(LowCardTables::Errors::LowCardColumnNotSpecifiedError)
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

    it "should allow for bulk retrieval-and-creation of rows" do
      result = ::UserStatus.low_card_find_or_create_rows_for([ @hash1, @hash3, @hash4, @hash5 ])
      result.size.should == 4
    end

    it "should not require actually having any associated models"
  end
end
