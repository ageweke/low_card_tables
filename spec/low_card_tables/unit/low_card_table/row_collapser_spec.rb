require 'low_card_tables'

describe LowCardTables::LowCardTable::RowCollapser do
  def klass
    LowCardTables::LowCardTable::RowCollapser
  end

  it "should require a low-card table to be created" do
    low_card_model = double("low_card_model")

    lambda { klass.new(low_card_model, { }) }.should raise_error(ArgumentError)

    allow(low_card_model).to receive(:is_low_card_table?).and_return(false)
    lambda { klass.new(low_card_model, { }) }.should raise_error(ArgumentError)
  end

  context "with an instance" do
    before :each do
      @low_card_model = double("low_card_model")
      allow(@low_card_model).to receive(:is_low_card_table?).and_return(true)

      allow(@low_card_model).to receive(:low_card_value_column_names).and_return(%w{foo bar})

      @referring_model_1 = double("referring_model_1")
      @referring_model_2 = double("referring_model_2")

      allow(@low_card_model).to receive(:low_card_referring_models).and_return([ @referring_model_1, @referring_model_2 ])

      @row1 = double("row_1")
      @row2 = double("row_2")
      @row3 = double("row_3")
      @row4 = double("row_4")
      @row5 = double("row_5")
      @row6 = double("row_6")

      allow(@row1).to receive(:attributes).and_return({ 'foo' => "a", 'bar' => 1, 'irrelevant' => 'yo1' })
      allow(@row2).to receive(:attributes).and_return({ 'foo' => "a", 'bar' => 1, 'irrelevant' => 'yo2' })
      allow(@row3).to receive(:attributes).and_return({ 'foo' => "a", 'bar' => 1, 'irrelevant' => 'yo3' })
      allow(@row4).to receive(:attributes).and_return({ 'foo' => "b", 'bar' => 1, 'irrelevant' => 'yo4' })
      allow(@row5).to receive(:attributes).and_return({ 'foo' => "b", 'bar' => 1, 'irrelevant' => 'yo5' })
      allow(@row6).to receive(:attributes).and_return({ 'foo' => "b", 'bar' => 1, 'irrelevant' => 'yo6' })

      allow(@row1).to receive(:id).and_return(1)
      allow(@row2).to receive(:id).and_return(2)
      allow(@row3).to receive(:id).and_return(3)
      allow(@row4).to receive(:id).and_return(4)
      allow(@row5).to receive(:id).and_return(5)
      allow(@row6).to receive(:id).and_return(6)
    end

    def use(options)
      @instance = klass.new(@low_card_model, options)
    end

    describe "#collapse!" do
      it "should do nothing if :low_card_collapse_rows => false" do
        use(:low_card_collapse_rows => false)

        @instance.collapse!
      end

      it "should do nothing if there are no duplicate rows" do
        use({ })
        expect(@low_card_model).to receive(:all).and_return([ @row1, @row4 ])

        @instance.collapse!
      end

      context "actual collapsing" do
        before :each do
          expect(@low_card_model).to receive(:all).and_return([ @row1, @row2, @row3, @row4, @row5, @row6 ])
          expect(@low_card_model).to receive(:delete_all).once.with([ "id IN (:ids)", { :ids => [ 2, 3, 5, 6 ]} ])

          @expected_collapse_map = { @row1 => [ @row2, @row3 ], @row4 => [ @row5, @row6 ]}
        end

        it "should skip updating referring models if asked to" do
          use({ :low_card_update_referring_models => false })
          @instance.collapse!.should == @expected_collapse_map
        end

        context "with referring models updated" do
          before :each do
            expect(@low_card_model).to receive(:transaction).once { |*args, &block| block.call }
            expect(@referring_model_1).to receive(:transaction).once { |*args, &block| block.call }
            expect(@referring_model_2).to receive(:transaction).once { |*args, &block| block.call }

            expect(@referring_model_1).to receive(:_low_card_update_collapsed_rows).once.with(@low_card_model, @expected_collapse_map)
            expect(@referring_model_2).to receive(:_low_card_update_collapsed_rows).once.with(@low_card_model, @expected_collapse_map)
          end

          it "should collapse duplicate rows properly" do
            use({ })
            @instance.collapse!.should == @expected_collapse_map
          end

          it "should add additional referring models if asked to" do
            additional_referring_model = double("additional_referring_model")
            expect(additional_referring_model).to receive(:transaction).once { |*args, &block| block.call }
            expect(additional_referring_model).to receive(:_low_card_update_collapsed_rows).once.with(@low_card_model, @expected_collapse_map)

            use({ :low_card_referrers => [ @referring_model_1, additional_referring_model ]})
            @instance.collapse!.should == @expected_collapse_map
          end
        end
      end
    end
  end
end
