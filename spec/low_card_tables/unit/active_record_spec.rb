require 'low_card_tables'

describe LowCardTables::ActiveRecord::Base do
  before :each do
    @ar_class = Class.new(ActiveRecord::Base)
  end

  context "#is_low_card_table?" do
    it "should expose it as false by default" do
      @ar_class.is_low_card_table?.should_not be
    end

    it "should allow declaring #is_low_card_table, and then it should return true" do
      @ar_class.class_eval do
        is_low_card_table
      end

      @ar_class.is_low_card_table?.should be
    end
  end
end
