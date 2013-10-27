require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe LowCardTables do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
    create_standard_system_spec_models!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should allow 'where' clauses to behave naturally"
  it "should compose 'where' clauses correctly"

  it "should allow using low-card properties in the default scope"
  it "should allow using low-card properties in arbitrary scopes"
  it "should pick up new low-card rows when using a low-card property in an arbitrary scope"
end
