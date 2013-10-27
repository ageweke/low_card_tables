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

  it "should handle schema changes to the low-card table"
  it "should be able to remove low-card columns and automatically update associated rows"

  it "should throw out the cache if the schema has changed"

  it "should automatically add a unique index in migrations"
  it "should allow removing a column, and thus collapsing rows that are now identical"
  it "should fail if there is no unique index on a low-card table at startup"
end
