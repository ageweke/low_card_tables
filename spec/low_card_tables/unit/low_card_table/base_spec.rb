require 'low_card_tables'

describe LowCardTables::LowCardTable::Base do
  before :each do
    @test_class = Class.new
    allow(@test_class).to receive(:inheritance_column=).with('_sti_on_low_card_tables_should_never_be_used')
    @test_class.send(:include, LowCardTables::LowCardTable::Base)
  end

  it "should make its recipient inherit the low-card policy from LowCardTables" do
    LowCardTables.low_card_cache_expiration 20
    @test_class.low_card_cache_expiration.should == 20

    LowCardTables.low_card_cache_expiration 45
    @test_class.low_card_cache_expiration.should == 45
  end

  context "with an instance" do
    before :each do
      @instance = @test_class.new
    end

    describe "row-matching" do
      it "should match columns by hash-indexing, by default" do
        expect(@instance).to receive(:[]).with('foo').twice.and_return(:bar)

        @instance._low_card_column_matches?(:foo, :bar).should be
        @instance._low_card_column_matches?(:foo, :baz).should_not be
      end

      it "should match a hash one-by-one, by calling through to _low_card_column_matches?" do
        expect(@instance).to receive(:_low_card_column_matches?).with(:foo, :bar).and_return(true)
        expect(@instance).to receive(:_low_card_column_matches?).with(:baz, :quux).and_return(true)

        @instance._low_card_row_matches_hash?(:foo => :bar, :baz => :quux).should be
      end

      it "should not match a different hash, by calling through to _low_card_column_matches?" do
        expect(@instance).to receive(:_low_card_column_matches?).with(:foo, :bar).and_return(false)

        @instance._low_card_row_matches_hash?(:foo => :bar).should_not be
      end

      it "should always match if the hash contains nothing" do
        @instance._low_card_row_matches_hash?({ }).should be
      end

      it "should match a set of hashes, by looking for one that matches, by calling through to _low_card_row_matches_hash?" do
        h1 = { :foo => :bar, :bar => :baz }
        h2 = { :a => :b, 'c' => 12345 }

        expect(@instance).to receive(:_low_card_row_matches_hash?).with(h1).and_return(false)
        expect(@instance).to receive(:_low_card_row_matches_hash?).with(h2).and_return(true)

        @instance._low_card_row_matches_any_hash?([ h1, h2 ]).should be
      end

      it "should fail to match a set of hashes, by looking for one that matches, by calling through to _low_card_row_matches_hash?" do
        h1 = { :foo => :bar, :bar => :baz }
        h2 = { :a => :b, 'c' => 12345 }

        expect(@instance).to receive(:_low_card_row_matches_hash?).with(h1).and_return(false)
        expect(@instance).to receive(:_low_card_row_matches_hash?).with(h2).and_return(false)

        @instance._low_card_row_matches_any_hash?([ h1, h2 ]).should_not be
      end

      it "should match blocks by calling them" do
        block = double("block")

        expect(block).to receive(:call).once.with(@instance).and_return(true)
        @instance._low_card_row_matches_block?(block).should be

        expect(block).to receive(:call).once.with(@instance).and_return(false)
        @instance._low_card_row_matches_block?(block).should_not be
      end
    end
  end

  it "should save and return options properly" do
    @test_class.is_low_card_table(:foo => :bar, :baz => :quux)
    @test_class.low_card_options.should == { :foo => :bar, :baz => :quux }

    @test_class.low_card_options = { :a => :b, :c => :d }
    @test_class.low_card_options.should == { :a => :b, :c => :d }
  end

  it "should declare that it's a low-card table" do
    @test_class.is_low_card_table?.should be
  end

  describe "row manager" do
    it "should create a row manager of the right class, by default" do
      rm = @test_class._low_card_row_manager
      @test_class._low_card_row_manager.should be(rm)

      rm.class.should == LowCardTables::LowCardTable::RowManager
      rm.low_card_model.should be(@test_class)
    end

    it "should call through to the row manager on #reset_column_information" do
      mod = Module.new
      mod.module_eval do
        def reset_column_information
          @_reset_column_information_calls ||= 0
          @_reset_column_information_calls += 1
          :reset_column_information_return_value
        end

        def reset_column_information_calls
          @_reset_column_information_calls
        end
      end

      test_class = Class.new
      allow(test_class).to receive(:inheritance_column=).with('_sti_on_low_card_tables_should_never_be_used')
      test_class.send(:extend, mod)
      test_class.send(:include, LowCardTables::LowCardTable::Base)

      rm = double("row_manager")
      allow(test_class).to receive(:_low_card_row_manager).and_return(rm)

      expect(rm).to receive(:column_information_reset!).once

      test_class.reset_column_information.should == :reset_column_information_return_value
      test_class.reset_column_information_calls.should == 1
    end

    context "with a mock row manager" do
      before :each do
        @rm = double("row_manager")
        allow(@test_class).to receive(:_low_card_row_manager).and_return(@rm)
      end

      %w{all_rows row_for_id rows_for_ids rows_matching ids_matching find_ids_for find_or_create_ids_for
find_rows_for find_or_create_rows_for flush_cache! referring_models collapse_rows_and_update_referrers!
value_column_names referred_to_by
ensure_has_unique_index! remove_unique_index!}.each do |method_name|
        it "should delegate to the row manager for #{method_name}" do
          expect(@rm).to receive(method_name).once.with(:foo, :bar).and_return(:baz)
          @test_class.send("low_card_#{method_name}", :foo, :bar).should == :baz
        end
      end
    end
  end

  context "saving" do
    before :each do
      @save_mod = Module.new
      @save_mod.module_eval do
        def save(*args)
          _saves_called << [ :save, args ]
          :save_return_value
        end

        def save!(*args)
          _saves_called << [ :save!, args ]
          :save_return_value!
        end

        def _saves_called
          @_saves_called ||= [ ]
        end
      end

      # We need a new class -- because we need to make sure our module gets in there first
      @test_class = Class.new
      allow(@test_class).to receive(:inheritance_column=).with('_sti_on_low_card_tables_should_never_be_used')
      @test_class.send(:include, @save_mod)
      @test_class.send(:include, LowCardTables::LowCardTable::Base)

      @test_class.is_low_card_table
      @test_class.is_low_card_table # ensure that calling it twice doesn't mess anything up

      @instance = @test_class.new
    end

    it "should refuse to save, by default" do
      lambda { @instance.save }.should raise_error(LowCardTables::Errors::LowCardCannotSaveAssociatedLowCardObjectsError)
      @instance._saves_called.length.should == 0

      lambda { @instance.save! }.should raise_error(LowCardTables::Errors::LowCardCannotSaveAssociatedLowCardObjectsError)
      @instance._saves_called.length.should == 0
    end

    it "should save, if invoked via #save_low_card_row" do
      @instance.save_low_card_row(:foo, :bar).should == :save_return_value
      @instance._saves_called.should == [ [ :save, [ :foo, :bar ] ] ]
    end

    it "should save, if invoked via #save_low_card_row!" do
      @instance.save_low_card_row!(:foo, :bar).should == :save_return_value!
      @instance._saves_called.should == [ [ :save!, [ :foo, :bar ] ] ]
    end

    it "should not accidentally continue allowing saves if save! blows up" do
      @save_mod.module_eval do
        def save!(*args)
          _saves_called << [ :save!, args ]
          raise "kaboom"
        end
      end

      lambda { @instance.save_low_card_row!(:foo, :bar) }.should raise_error(/kaboom/i)
      @instance._saves_called.should == [ [ :save!, [ :foo, :bar ] ] ]

      lambda { @instance.save! }.should raise_error(LowCardTables::Errors::LowCardCannotSaveAssociatedLowCardObjectsError)
    end
  end
end
