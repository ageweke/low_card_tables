require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'
require 'low_card_tables/helpers/query_spy_helper'

describe "LowCardTables caching" do
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

  def create_basic_user(name = 'User1')
    out = ::User.new
    out.name = 'User1'
    out.deleted = false
    out.deceased = false
    out.gender = 'female'
    out.donation_level = 3
    out.save!

    out
  end

  it "should have an explicit cache-flush call that works" do
    LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
      create_basic_user("User1")

      mid_count = spy.call_count

      create_basic_user("User2")

      spy.call_count.should == mid_count

      ::UserStatus.low_card_flush_cache!
      create_basic_user("User3")

      spy.call_count.should > mid_count
    end
  end

  it "should cache low-card rows in memory" do
    LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
      spy.call_count.should == 0

      user1 = create_basic_user

      mid_calls = spy.call_count
      mid_calls.should > 0

      user2 = create_basic_user('User2')

      spy.call_count.should == mid_calls
    end
  end

  it "should purge its cache efficiently when adding a new row" do
    LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
      spy.call_count.should == 0

      user1 = create_basic_user

      mid_calls = spy.call_count
      mid_calls.should > 0

      user2 = ::User.new
      user2.name = 'User2'
      user2.deleted = false
      user2.deceased = false
      user2.gender = 'male'
      user2.donation_level = 7
      user2.save!

      # We allow two calls here because we need it for our double-checked locking pattern.
      (spy.call_count - mid_calls).should <= 2
    end
  end

  it "should handle the situation where a row in the database has a low-card ID that's not in cache" do
    LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
      spy.call_count.should == 0

      user1 = create_basic_user

      mid_calls = spy.call_count
      mid_calls.should > 0

      new_status = ::UserStatusBackdoor.new
      new_status.deleted = false
      new_status.deceased = false
      new_status.gender = 'male'
      new_status.donation_level = 7
      new_status.save!

      old_status_id = user1.user_status_id
      ::User.update_all([ "user_status_id = :new_status_id", { :new_status_id => new_status.id } ], [ "id = :id", { :id => user1.id } ])
      user1.user_status_id.should == old_status_id # make sure we didn't touch the existing object

      # Make sure we didn't somehow invalidate the cache before this
      spy.call_count.should == mid_calls

      user2 = ::User.find(user1.id)
      user2.deleted.should == false
      user2.deceased.should == false
      user2.gender.should == 'male'
      user2.donation_level.should == 7

      (spy.call_count - mid_calls).should > 0
      (spy.call_count - mid_calls).should <= 2
    end
  end

  it "should be OK with manually-assigning an ID that's not in cache (that you somehow got out-of-band)" do
    LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
      spy.call_count.should == 0

      user1 = create_basic_user

      mid_calls = spy.call_count
      mid_calls.should > 0

      new_status = ::UserStatusBackdoor.new
      new_status.deleted = false
      new_status.deceased = false
      new_status.gender = 'male'
      new_status.donation_level = 7
      new_status.save!

      user1.user_status_id = new_status.id
      user1.deleted.should == false
      user1.deceased.should == false
      user1.gender.should == 'male'
      user1.donation_level.should == 7

      (spy.call_count - mid_calls).should > 0
      (spy.call_count - mid_calls).should <= 2
    end
  end

  context "with a cache listener" do
    before :each do
      class CacheListener
        def initialize
          @calls = [ ]
        end

        def call(name, started, finished, unique_id, data)
          @calls << { :name => name, :started => started, :finished => finished, :unique_id => unique_id, :data => data }
        end

        def listen!(*event_names)
          event_names.each do |event_name|
            ActiveSupport::Notifications.subscribe(event_name, self)
          end
        end

        def unlisten!
          ActiveSupport::Notifications.unsubscribe(self)
        end

        attr_reader :calls
      end

      @cache_listener = CacheListener.new
      @cache_listener.listen!('low_card_tables.cache_load', 'low_card_tables.cache_flush', 'low_card_tables.rows_created')
    end

    after :each do
      @cache_listener.unlisten!
    end

    it "should notify listeners when flushing and loading its cache" do
      @cache_listener.calls.length.should == 0

      user1 = create_basic_user

      call_count = @cache_listener.calls.length
      call_count.should > 0
      @cache_listener.calls.detect { |c| c[:name] == 'low_card_tables.cache_load' }.should be

      start_time = Time.now
      user1.deleted = true
      user1.save!
      end_time = Time.now

      new_calls = @cache_listener.calls[call_count..-1]
      new_calls.length.should > 0

      flush_event = new_calls.detect { |c| c[:name] == 'low_card_tables.cache_flush' }
      load_event = new_calls.detect { |c| c[:name] == 'low_card_tables.cache_load' }
      flush_event.should be
      load_event.should be

      flush_event[:started].should >= start_time
      flush_event[:finished].should >= flush_event[:started]
      flush_event[:finished].should <= end_time
      flush_event[:data][:reason].should == :creating_rows
      flush_event[:data][:low_card_model].should == ::UserStatus

      load_event[:started].should >= start_time
      load_event[:started].should >= flush_event[:finished]
      load_event[:finished].should >= load_event[:started]
      load_event[:finished].should <= end_time
      load_event[:data][:low_card_model].should == ::UserStatus
    end

    it "should notify listeners when the cache is manually flushed" do
      user1 = create_basic_user
      call_count = @cache_listener.calls.length

      start_time = Time.now
      ::UserStatus.low_card_flush_cache!
      new_calls = @cache_listener.calls[call_count..-1]
      end_time = Time.now

      new_calls.length.should == 1
      new_call = new_calls[0]
      new_call[:name].should == 'low_card_tables.cache_flush'
      new_call[:started].should >= start_time
      new_call[:finished].should >= new_call[:started]
      new_call[:finished].should <= end_time
      new_call[:data][:reason].should == :manually_requested
      new_call[:data][:low_card_model].should == ::UserStatus
    end

    it "should notify listeners when the cache is flushed because an ID was not found" do
      user1 = create_basic_user
      call_count = @cache_listener.calls.length

      start_time = Time.now
      lambda do
        ::UserStatus.low_card_rows_for_ids([ user1.user_status_id, user1.user_status_id + 1000 ])
      end.should raise_error(LowCardTables::Errors::LowCardIdNotFoundError)

      new_calls = @cache_listener.calls[call_count..-1]
      end_time = Time.now

      new_calls.length.should > 1
      new_call = new_calls.detect { |c| c[:name] == 'low_card_tables.cache_flush' && c[:data][:reason] == :id_not_found }
      new_call[:name].should == 'low_card_tables.cache_flush'
      new_call[:started].should >= start_time
      new_call[:finished].should >= new_call[:started]
      new_call[:finished].should <= end_time
      new_call[:data][:reason].should == :id_not_found
      new_call[:data][:low_card_model].should == ::UserStatus
    end

    it "should notify listeners when adding a new row" do
      @cache_listener.calls.length.should == 0

      user1 = create_basic_user

      call_count = @cache_listener.calls.length
      call_count.should > 0

      start_time = Time.now
      user1.gender = 'male'
      user1.donation_level = 9
      user1.save!
      end_time = Time.now

      new_calls = @cache_listener.calls[call_count..-1]
      new_calls.length.should > 0

      create_calls = new_calls.select { |c| c[:name] == 'low_card_tables.rows_created' }
      create_calls.length.should == 1
      create_call = create_calls[0]

      create_call[:started].should >= start_time
      create_call[:finished].should <= end_time
      create_call[:finished].should >= create_call[:started]
      create_call[:data][:low_card_model].should == ::UserStatus

      keys = create_call[:data][:keys].map(&:to_s)
      keys.sort.should == %w{deceased deleted donation_level gender}

      values_array = create_call[:data][:values]
      values_array.length.should == 1
      values = values_array[0]
      values.length.should == keys.length

      values[keys.index('deceased')].should == false
      values[keys.index('deleted')].should == false
      values[keys.index('gender')].should == 'male'
      values[keys.index('donation_level')].should == 9
    end
  end

  context "cache policies" do
    before :each do
      class LowCardTables::LowCardTable::RowManager
        def current_time
          self.class.override_current_time || Time.now
        end

        class << self
          def override_current_time=(x)
            @override_current_time = x
          end

          def override_current_time
            @override_current_time
          end
        end
      end

      class LowCardTables::LowCardTable::Cache
        def current_time
          LowCardTables::LowCardTable::RowManager.override_current_time || Time.now
        end
      end

      class LowCardTables::LowCardTable::CacheExpiration::ExponentialCacheExpirationPolicy
        def current_time
          LowCardTables::LowCardTable::RowManager.override_current_time || Time.now
        end
      end
    end

    def check_cache_expiration(*cache_expiration_settings, &block)
      LowCardTables::Helpers::QuerySpyHelper.with_query_spy("lctables_spec_user_statuses") do |spy|
        @start_time = Time.now
        set_current_time(0)

        ::UserStatus.low_card_cache_expiration *cache_expiration_settings

        user1 = create_basic_user

        @last_call_count = spy.call_count
        @spy = spy

        block.call
      end
    end

    def set_current_time(x)
      LowCardTables::LowCardTable::RowManager.override_current_time = @start_time + x
    end

    def time_and_check(time, cached_or_not)
      set_current_time(time)
      new_user = create_basic_user

      if cached_or_not == :cached
        @spy.call_count.should == @last_call_count
      elsif cached_or_not == :uncached
        @spy.call_count.should > @last_call_count
        @last_call_count = @spy.call_count
      else
        raise "Unknown cached_or_not: #{cached_or_not.inspect}"
      end
    end

    it "should apply a fixed setting correctly" do
      check_cache_expiration(2.minutes) do |spy, initial_call_count|
        time_and_check(119.seconds, :cached)
        time_and_check(121.seconds, :uncached)
        time_and_check(240.seconds, :cached)
        time_and_check(242.seconds, :uncached)
      end
    end

    it "should apply a setting of 0 correctly" do
      check_cache_expiration(0) do |spy, initial_call_count|
        time_and_check(1.seconds, :uncached)
        time_and_check(1.seconds, :uncached)
        time_and_check(2.seconds, :uncached)
        time_and_check(3.seconds, :uncached)
        time_and_check(3.seconds, :uncached)
      end
    end

    it "should apply a setting of :unlimited correctly" do
      check_cache_expiration(:unlimited) do |spy, initial_call_count|
        time_and_check(1.seconds, :cached)
        time_and_check(2.seconds, :cached)
        time_and_check(5.years, :cached)
      end
    end

    it "should apply a setting of :exponential with default settings correctly" do
      check_cache_expiration(:exponential) do |spy, initial_call_count|
        # 0-180: zero floor
        time_and_check(0.seconds, :uncached)
        time_and_check(1.seconds, :uncached)
        time_and_check(30.seconds, :uncached)
        time_and_check(90.seconds, :uncached)
        time_and_check(179.seconds, :uncached)

        # 180-190: ten second minimum
        time_and_check(181.seconds, :uncached)
        time_and_check(182.seconds, :cached)
        time_and_check(189.seconds, :cached)

        # 190-210: first doubling (20 seconds)
        time_and_check(191.seconds, :uncached)
        time_and_check(192.seconds, :cached)
        time_and_check(209.seconds, :cached)

        # 210-250: second doubling (40 seconds)
        # don't check here -- want to make sure we skip this properly

        # 250-330: third doubling (80 seconds)
        time_and_check(251.seconds, :uncached)
        time_and_check(295.seconds, :cached)
        time_and_check(329.seconds, :cached)

        # 330-490: fourth doubling (160 seconds)
        # 490-810: fifth doubling (320 seconds)
        # 810-1450: sixth doubling (640 seconds)
        # 1450-2730: seventh doubling (1280 seconds)
        # 2730-5290: eighth doubling (2560 seconds)
        time_and_check(2731.seconds, :uncached)
        time_and_check(2732.seconds, :cached)
        time_and_check(5289.seconds, :cached)

        # 5290-8890: max (3600 seconds)
        time_and_check(5291.seconds, :uncached)
        time_and_check(5292.seconds, :cached)
        time_and_check(8889.seconds, :cached)

        # 8890-12490: max (3600 seconds)
        time_and_check(8891.seconds, :uncached)
        time_and_check(8892.seconds, :cached)
        time_and_check(12489.seconds, :cached)

        # 12490-16090: max (3600 seconds)
        time_and_check(12491.seconds, :uncached)
        time_and_check(16089.seconds, :cached)
      end
    end

    it "should apply a setting of :exponential with custom settings correctly" do
      check_cache_expiration(:exponential, :zero_floor_time => 10.seconds, :min_time => 5.seconds, :exponent => 3.0, :max_time => 200.seconds) do |spy, initial_call_count|
        # 0-10: zero floor
        time_and_check(0.seconds, :uncached)
        time_and_check(1.seconds, :uncached)
        time_and_check(9.seconds, :uncached)

        # 10-15: five second minimum
        time_and_check(10.seconds, :uncached)
        time_and_check(14.seconds, :cached)

        # 15-30: first tripling (15 seconds)
        time_and_check(16.seconds, :uncached)
        time_and_check(17.seconds, :cached)
        time_and_check(29.seconds, :cached)

        # 30-75: second tripling (45 seconds)
        time_and_check(31.seconds, :uncached)
        time_and_check(32.seconds, :cached)
        time_and_check(74.seconds, :cached)

        # 75-210: third tripling (135 seconds)

        # 210-410: max (200 seconds)
        time_and_check(211.seconds, :uncached)
        time_and_check(212.seconds, :cached)
        time_and_check(409.seconds, :cached)

        # 410-610: max (200 seconds)
        time_and_check(411.seconds, :uncached)
        time_and_check(412.seconds, :cached)
        time_and_check(609.seconds, :cached)
      end
    end

    it "should apply a setting of :exponential with custom settings with no zero floor" do
      check_cache_expiration(:exponential, :zero_floor_time => 0, :min_time => 5.seconds, :exponent => 3.0, :max_time => 200.seconds) do |spy, initial_call_count|
        # 0-5: five second minimum
        time_and_check(1.seconds, :cached)
        time_and_check(4.seconds, :cached)

        # 5-20: first tripling (15 seconds)
        time_and_check(6.seconds, :uncached)
        time_and_check(7.seconds, :cached)
        time_and_check(19.seconds, :cached)

        # 20-65: second tripling (45 seconds)
        time_and_check(21.seconds, :uncached)
        time_and_check(22.seconds, :cached)
        time_and_check(64.seconds, :cached)

        # 65-200: third tripling (135 seconds)

        # 200-400: max (200 seconds)
        time_and_check(201.seconds, :uncached)
        time_and_check(202.seconds, :cached)
        time_and_check(399.seconds, :cached)

        # 400-600: max (200 seconds)
        time_and_check(401.seconds, :uncached)
        time_and_check(402.seconds, :cached)
        time_and_check(599.seconds, :cached)
      end
    end
  end
end
