require 'low_card_tables'

describe LowCardTables::LowCardTable::Cache do
  def klass
    LowCardTables::LowCardTable::Cache
  end

  it "should require a low-card table class" do
    mc = double("model_class")

    lambda { klass.new(mc) }.should raise_error(ArgumentError)

    allow(mc).to receive(:is_low_card_table?).and_return(false)

    lambda { klass.new(mc) }.should raise_error(ArgumentError)
  end

  context "with an instance" do
    before :each do
      klass.class_eval do
        class << self
          def override_time=(x)
            @override_time = x
          end

          def override_time
            out = @override_time
            @override_time = nil
            out
          end
        end

        def current_time
          self.class.override_time || Time.now
        end
      end

      @mc = double("model_class")
      allow(@mc).to receive(:is_low_card_table?).and_return(true)
      allow(@mc).to receive(:low_card_ensure_has_unique_index!)
      allow(@mc).to receive(:primary_key).and_return("foobar")
      allow(@mc).to receive(:table_name).and_return("barbaz")

      im1 = double("im1")
      expect(@mc).to receive(:order).once.with("foobar ASC").and_return(im1)
      im2 = double("im2")
      expect(im1).to receive(:limit).once.with(5001).and_return(im2)

      @row1 = double("row1")
      @row2 = double("row2")
      @row3 = double("row3")

      allow(@row1).to receive(:id).and_return(1234)
      allow(@row2).to receive(:id).and_return(1235)
      allow(@row3).to receive(:id).and_return(1238)

      expect(im2).to receive(:to_a).once.and_return([ @row1, @row2, @row3 ])

      @rows_read_at_time = double("rows_read_at_time")
      klass.override_time = @rows_read_at_time

      @cache = klass.new(@mc)
    end

    it "should correctly expose the time rows were read" do
      @cache.loaded_at.should be(@rows_read_at_time)
    end

    it "should return all the rows" do
      @cache.all_rows.sort_by(&:object_id).should == [ @row1, @row2, @row3 ].sort_by(&:object_id)
    end

    describe "#rows_matching" do
      it "should fail if given no hashes" do
        lambda { @cache.rows_matching([ ]) }.should raise_error(ArgumentError)
      end

      it "should fail if given something that isn't a Hash" do
        lambda { @cache.rows_matching([ 12345 ]) }.should raise_error(ArgumentError)
      end

      it "should fail if neither a hash nor a block" do
        lambda { @cache.rows_matching }.should raise_error(ArgumentError)
      end

      it "should fail if given both a hash and a block" do
        lambda { @cache.rows_matching({ :foo => :bar }) { |x| true } }.should raise_error(ArgumentError)
      end

      it "should return a Hash if given an array of Hashes" do
        h1 = { :a => :b, :c => :d }
        h2 = { :foo => :bar }
        h3 = { :bar => :baz }

        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)
        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h2 ]).and_return(true)
        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h3 ]).and_return(false)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h2 ]).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h3 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h2 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h3 ]).and_return(false)

        result = @cache.rows_matching([ h1, h2, h3 ])
        result.class.should == Hash
        result.size.should == 3

        result[h1].length.should == 1
        result[h1][0].should be(@row1)

        result[h2].length.should == 2
        result[h2].sort_by(&:object_id).should == [ @row1, @row2 ].sort_by(&:object_id)

        result[h3].class.should == Array
        result[h3].length.should == 0
      end

      it "should return a Hash if given an array of just one Hash" do
        h1 = { :a => :b, :c => :d }

        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)

        result = @cache.rows_matching([ h1 ])
        result.class.should == Hash
        result.size.should == 1

        result[h1].length.should == 1
        result[h1][0].should be(@row1)
      end

      it "should return an Array if given a Hash" do
        h1 = { :a => :b, :c => :d }

        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)

        result = @cache.rows_matching(h1)
        result.class.should == Array
        result.sort_by(&:object_id).should == [ @row1, @row3 ].sort_by(&:object_id)
      end

      it "should return an Array if given a Block" do
        block = lambda { }

        expect(@row1).to receive(:_low_card_row_matches_block?).once.with(block).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_block?).once.with(block).and_return(true)
        expect(@row3).to receive(:_low_card_row_matches_block?).once.with(block).and_return(false)

        result = @cache.rows_matching(&block)
        result.class.should == Array
        result.sort_by(&:object_id).should == [ @row1, @row2 ].sort_by(&:object_id)
      end
    end

    describe "#ids_matching" do
      it "should fail if given no hashes" do
        lambda { @cache.ids_matching([ ]) }.should raise_error(ArgumentError)
      end

      it "should fail if given something that isn't a Hash" do
        lambda { @cache.ids_matching([ 12345 ]) }.should raise_error(ArgumentError)
      end

      it "should fail if neither a hash nor a block" do
        lambda { @cache.ids_matching }.should raise_error(ArgumentError)
      end

      it "should fail if given both a hash and a block" do
        lambda { @cache.ids_matching({ :foo => :bar }) { |x| true } }.should raise_error(ArgumentError)
      end

      it "should return a Hash if given an array of Hashes" do
        h1 = { :a => :b, :c => :d }
        h2 = { :foo => :bar }
        h3 = { :bar => :baz }

        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)
        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h2 ]).and_return(true)
        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h3 ]).and_return(false)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h2 ]).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h3 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h2 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h3 ]).and_return(false)

        result = @cache.ids_matching([ h1, h2, h3 ])
        result.class.should == Hash
        result.size.should == 3

        result[h1].length.should == 1
        result[h1][0].should == @row1.id

        result[h2].length.should == 2
        result[h2].sort.should == [ @row1.id, @row2.id ].sort

        result[h3].class.should == Array
        result[h3].length.should == 0
      end

      it "should return a Hash if given an array of just one Hash" do
        h1 = { :a => :b, :c => :d }

        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)

        result = @cache.ids_matching([ h1 ])
        result.class.should == Hash
        result.size.should == 1

        result[h1].length.should == 1
        result[h1][0].should == @row1.id
      end

      it "should return an Array if given a Hash" do
        h1 = { :a => :b, :c => :d }

        expect(@row1).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(false)
        expect(@row3).to receive(:_low_card_row_matches_any_hash?).once.with([ h1 ]).and_return(true)

        result = @cache.ids_matching(h1)
        result.class.should == Array
        result.sort.should == [ @row1.id, @row3.id ].sort
      end

      it "should return an Array if given a Block" do
        block = lambda { }

        expect(@row1).to receive(:_low_card_row_matches_block?).once.with(block).and_return(true)
        expect(@row2).to receive(:_low_card_row_matches_block?).once.with(block).and_return(true)
        expect(@row3).to receive(:_low_card_row_matches_block?).once.with(block).and_return(false)

        result = @cache.ids_matching(&block)
        result.class.should == Array
        result.sort.should == [ @row1.id, @row2.id ].sort
      end
    end

    describe "#rows_for_ids" do
      it "should return a single row for a single ID" do
        @cache.rows_for_ids(@row2.id).should be(@row2)
      end

      it "should return a map for multiple IDs" do
        result = @cache.rows_for_ids([ @row1.id, @row2.id ])
        result.class.should == Hash
        result.size.should == 2
        result[@row1.id].should be(@row1)
        result[@row2.id].should be(@row2)
      end

      it "should return a map for a single ID, passed in an array" do
        result = @cache.rows_for_ids([ @row3.id ])
        result.class.should == Hash
        result.size.should == 1
        result[@row3.id].should be(@row3)
      end

      it "should blow up if passed a missing ID" do
        lambda { @cache.rows_for_ids([ @row1.id, 98765, @row3.id ]) }.should raise_error(LowCardTables::Errors::LowCardIdNotFoundError, /98765/)
      end
    end
  end
end
