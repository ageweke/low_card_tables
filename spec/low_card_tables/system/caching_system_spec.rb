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

    ::UserStatus.low_card_cache_expiration = :unlimited

    @_ar_sql_calls = [ ]

    @_ar_sql_spy = lambda do |notification_name, when1, when2, id, data|
      sql = data[:sql]
      if sql && sql.strip.length > 0
        if sql =~ /^\s*SELECT.*FROM\s+['"]*\s*lctables_spec_user_statuses\s*['"]*\s+/mi
          @_ar_sql_calls << true
          $stderr.puts ">>> MATCH: #{sql}\n#{caller.join("\n")}"
        end
      end
    end

    ActiveSupport::Notifications.subscribe("sql.active_record", @_ar_sql_spy)
  end

  after :each do
    drop_standard_system_spec_tables!
    ActiveSupport::Notifications.unsubscribe(@_ar_sql_spy)
  end

  it "should cache low-card rows in memory" do
    @_ar_sql_calls.length.should == 0

    user1 = ::User.new
    user1.name = 'User1'
    user1.deleted = false
    user1.deceased = false
    user1.gender = 'female'
    user1.donation_level = 3
    user1.save!

    mid_calls = @_ar_sql_calls.length
    @_ar_sql_calls.length.should > 0

    user2 = ::User.new
    user2.name = 'User2'
    user2.deleted = false
    user2.deceased = false
    user2.gender = 'female'
    user2.donation_level = 3
    user2.save!

    @_ar_sql_calls.length.should == mid_calls
  end

  it "should notify listeners when refreshing its cache"
  it "should notify listeners when adding a new row"

  it "should use the specified cache policy"
end
