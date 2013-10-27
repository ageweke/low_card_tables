require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

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
    end

    after :each do
      drop_standard_system_spec_tables!
    end

    it "should allow for bulk retrieval of rows"
    it "should allow for bulk retrieval-and-creation of rows"
    it "should not require actually having any associated models"
  end
end
