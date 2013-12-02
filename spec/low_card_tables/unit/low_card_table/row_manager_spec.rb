require 'low_card_tables'

describe LowCardTables::LowCardTable::RowManager do
  def klass
    LowCardTables::LowCardTable::RowManager
  end

  before :each do
    klass.class_eval do
      class << self
        def next_time
          if @next_time
            @next_time += 1
            @next_time
          end
        end

        def next_time=(x)
          @next_time = x
        end
      end

      def current_time
        self.class.next_time || Time.now
      end
    end

    LowCardTables::LowCardTable::Cache.class_eval do
      def current_time
        LowCardTables::LowCardTable::RowManager.next_time || Time.now
      end
    end

    klass.next_time = 0

    @cache_loads = [ ]
    cl = @cache_loads
    ::ActiveSupport::Notifications.subscribe("low_card_tables.cache_load") do |name, start, finish, id, payload|
      cl << payload
    end

    @cache_flushes = [ ]
    cf = @cache_flushes
    ::ActiveSupport::Notifications.subscribe("low_card_tables.cache_flush") do |name, start, finish, id, payload|
      cf << payload
    end
  end

  after :each do
    klass.next_time = nil
  end

  it "should require a low-card model for instantiation" do
    low_card_model = double("low_card_model")
    lambda { klass.new(low_card_model) }.should raise_error(ArgumentError)

    allow(low_card_model).to receive(:is_low_card_table?).and_return(false)
    lambda { klass.new(low_card_model) }.should raise_error(ArgumentError)
  end

  context "with an instance" do
    before :each do
      @low_card_model = double("low_card_model")
      allow(@low_card_model).to receive(:is_low_card_table?).and_return(true)
      allow(@low_card_model).to receive(:low_card_options).and_return({ :foo => :bar })
      allow(@low_card_model).to receive(:reset_column_information)
      allow(@low_card_model).to receive(:table_exists?).and_return(true)
      allow(@low_card_model).to receive(:table_name).and_return("thetablename")

      @column_id = double("column_id")
      allow(@column_id).to receive(:name).and_return("id")
      allow(@column_id).to receive(:primary).and_return(true)
      @column_foo = double("column_foo")
      allow(@column_foo).to receive(:name).and_return("foo")
      allow(@column_foo).to receive(:primary).and_return(false)
      allow(@column_foo).to receive(:default).and_return(nil)
      @column_bar = double("column_bar")
      allow(@column_bar).to receive(:name).and_return("bar")
      allow(@column_bar).to receive(:primary).and_return(false)
      allow(@column_bar).to receive(:default).and_return('yohoho')
      allow(@low_card_model).to receive(:columns).and_return([ @column_id, @column_foo, @column_bar ])

      @cache_expiration_policy = double("cache_expiration_policy")
      allow(@low_card_model).to receive(:low_card_cache_expiration_policy_object).and_return(@cache_expiration_policy)

      @instance = klass.new(@low_card_model)

      @created_cache_count = 0
      @expected_caches = [ ]
      ec = @expected_caches

      allow(LowCardTables::LowCardTable::Cache).to receive(:new) do
        if ec.length > 0
          @expected_caches.shift
        else
          raise "created a cache that we didn't expect to create"
        end
      end

      @expected_stale_calls = [ ]
      esc = @expected_stale_calls

      allow(@cache_expiration_policy).to receive(:stale?) do |cache_time, current_time|
        if esc.length > 0
          (expected_cache_time, expected_current_time, stale) = esc.shift
          if (cache_time != expected_cache_time) || (current_time != expected_current_time)
            raise "incorrect call to stale?; cache time: expected #{expected_cache_time}, got #{cache_time}; current time: expected #{expected_current_time}, got #{current_time}"
          end

          stale
        else
          raise "unexpected call to stale? (#{cache_time}, #{current_time})"
        end
      end
    end

    after :each do
      if @expected_caches.length > 0
        raise "didn't create as many caches as expected; still have: #{@expected_caches.inspect}"
      end

      if @expected_stale_calls.length > 0
        raise "didn't call stale? as many times as expected; still have: #{@expected_stale_calls.inspect}"
      end
    end

    def expect_cache_creation
      @created_cache_count += 1
      cache = double("cache-#{@created_cache_count}")
      @expected_caches << cache
      cache
    end

    def expect_cache_validation(cache, expected_cache_time, expected_current_time, stale)
      expect(cache).to receive(:loaded_at).once.and_return(expected_cache_time)
      @expected_stale_calls << [ expected_cache_time, expected_current_time, stale ]
    end

    describe "referring models" do
      before :each do
        @referring_class_1 = double("referring_class_1")
        @referring_class_2 = double("referring_class_2")
      end

      it "should have no referring models, by default" do
        @instance.referring_models.should == [ ]
      end

      it "should unify and return referring models" do
        @instance.referred_to_by(@referring_class_1)
        @instance.referred_to_by(@referring_class_2)
        @instance.referred_to_by(@referring_class_1)

        @instance.referring_models.sort_by(&:object_id).should == [ @referring_class_1, @referring_class_2 ].sort_by(&:object_id)
      end

      it "should tell all referring models when column information is reset" do
        @instance.referred_to_by(@referring_class_1)
        @instance.referred_to_by(@referring_class_2)

        lcam_1 = double("lcam_1")
        lcam_2 = double("lcam_2")

        expect(@referring_class_1).to receive(:_low_card_associations_manager).once.and_return(lcam_1)
        expect(@referring_class_2).to receive(:_low_card_associations_manager).once.and_return(lcam_2)

        expect(lcam_1).to receive(:low_card_column_information_reset!).once.with(@low_card_model)
        expect(lcam_2).to receive(:low_card_column_information_reset!).once.with(@low_card_model)

        @instance.column_information_reset!
      end
    end

    describe "cache management" do
      it "should return #all_rows directly from cache, and notify that it loaded a cache" do
        cache = expect_cache_creation
        expect(cache).to receive(:all_rows).once.and_return(:allrows)

        @instance.all_rows.should == :allrows

        @cache_loads.length.should == 1
        @cache_loads[0].should == { :low_card_model => @low_card_model }
        @cache_flushes.length.should == 0
      end

      it "should check the cache on the second call, and use that cache" do
        cache = expect_cache_creation
        expect(cache).to receive(:all_rows).twice.and_return(:allrows)
        expect_cache_validation(cache, 1, 2, false)

        @instance.all_rows.should == :allrows
        @instance.all_rows.should == :allrows

        @cache_loads.length.should == 1
        @cache_loads[0].should == { :low_card_model => @low_card_model }
        @cache_flushes.length.should == 0
      end

      it "should refresh the cache on the second call, if needed; also, reset column information when doing so, and fire both load and flush notifications" do
        cache1 = expect_cache_creation
        expect(cache1).to receive(:all_rows).once.and_return(:allrows1)
        expect_cache_validation(cache1, 1, 2, true)

        cache2 = expect_cache_creation
        expect(cache2).to receive(:all_rows).once.and_return(:allrows2)

        expect(@low_card_model).to receive(:reset_column_information).once

        @instance.all_rows.should == :allrows1
        @instance.all_rows.should == :allrows2

        @cache_loads.length.should == 2
        @cache_loads[0].should == { :low_card_model => @low_card_model }
        @cache_loads[1].should == { :low_card_model => @low_card_model }
        @cache_flushes.length.should == 1
        @cache_flushes[0].should == { :reason => :stale, :low_card_model => @low_card_model, :now => 2, :loaded => 1 }
      end

      it "should only reset column information if asked to flush the cache when there isn't one, and not fire a notification" do
        expect(@low_card_model).to receive(:reset_column_information).once

        @instance.flush_cache!
        @cache_loads.length.should == 0
        @cache_flushes.length.should == 0
      end

      it "should flush the cache if asked to manually, and fire a notification" do
        cache1 = expect_cache_creation
        expect(cache1).to receive(:all_rows).once.and_return(:allrows1)

        cache2 = expect_cache_creation
        expect(cache2).to receive(:all_rows).once.and_return(:allrows2)

        expect(@low_card_model).to receive(:reset_column_information).once

        @instance.all_rows.should == :allrows1

        @instance.flush_cache!

        @instance.all_rows.should == :allrows2

        @cache_loads.length.should == 2
        @cache_loads[0].should == { :low_card_model => @low_card_model }
        @cache_loads[1].should == { :low_card_model => @low_card_model }

        @cache_flushes.length.should == 1
        @cache_flushes[0].should == { :low_card_model => @low_card_model, :reason => :manually_requested }
      end
    end

    %w{rows_for_ids row_for_id}.each do |method_name|
      describe "##{method_name}" do
        it "should return a single row from cache if present" do
          row1 = double("row1")
          cache = expect_cache_creation
          expect(cache).to receive(:rows_for_ids).with(12345).and_return(row1)

          @instance.send(method_name, 12345).should be(row1)

          @cache_loads.length.should == 1
          @cache_loads[0].should == { :low_card_model => @low_card_model }
          @cache_flushes.length.should == 0
        end

        it "should flush the cache and try again if not present" do
          row1 = double("row1")
          cache1 = expect_cache_creation
          expect(cache1).to receive(:rows_for_ids).with(12345).and_raise(LowCardTables::Errors::LowCardIdNotFoundError.new("not found yo", 12345))

          cache2 = expect_cache_creation
          expect(cache2).to receive(:rows_for_ids).with(12345).and_return(row1)

          @instance.send(method_name, 12345).should be(row1)

          @cache_loads.length.should == 2
          @cache_loads[0].should == { :low_card_model => @low_card_model }
          @cache_loads[1].should == { :low_card_model => @low_card_model }

          @cache_flushes.length.should == 1
          @cache_flushes[0].should == { :low_card_model => @low_card_model, :reason => :id_not_found, :ids => 12345 }
        end
      end
    end

    %w{ids_matching rows_matching}.each do |method_name|
      describe "##{method_name}" do
        it "should call through to the cache" do
          hash = { :foo => 'bar' }

          cache = expect_cache_creation
          expect(cache).to receive(method_name).once.with([ { :foo => "bar" } ]).and_return({ { :foo => :bar } => :foobar })

          @instance.send(method_name, hash).should == :foobar
        end

        it "should reject hashes containing invalid data, but only after flushing and trying again" do
          cache = expect_cache_creation
          expect(cache).to receive(:all_rows).once.and_return(:allrows)

          @instance.all_rows.should == :allrows

          lambda { @instance.send(method_name, { :quux => :a }) }.should raise_error(LowCardTables::Errors::LowCardColumnNotPresentError, /quux/)
          @cache_flushes.length.should == 1
          @cache_flushes[0].should == { :low_card_model => @low_card_model, :reason => :schema_change }
        end

        it "should accept hashes containing valid data, if it isn't found the first time through" do
          column_baz = double("column_bar")
          allow(column_baz).to receive(:name).and_return("baz")
          allow(column_baz).to receive(:primary).and_return(false)

          columns_to_return = [
            [ @column_id, @column_foo, @column_bar ],
            [ @column_id, @column_foo, @column_bar, column_baz ]
          ]

          allow(@low_card_model).to receive(:columns) do
            columns_to_return.shift || raise("too many calls")
          end

          cache = expect_cache_creation
          expect(cache).to receive(method_name).once.with([ { :baz => "bonk" } ]).and_return({ { :baz => 'bonk' } => :foobar })
          @instance.send(method_name, { :baz => 'bonk' }).should == :foobar
        end
      end
    end

    describe "#find_rows_for" do
      it "should require a complete Hash" do
        lambda { @instance.find_rows_for({ :bar => 'baz' }) }.should raise_error(LowCardTables::Errors::LowCardColumnNotSpecifiedError)
        lambda { @instance.find_rows_for({ :foo => 'bar', :quux => 'aa' }) }.should raise_error(LowCardTables::Errors::LowCardColumnNotPresentError)
      end
    end
  end
end
