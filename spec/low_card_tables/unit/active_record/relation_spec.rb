require 'low_card_tables'

describe LowCardTables::ActiveRecord::Relation do
  before :each do
    module ArRelationBaseSpecModule
      def where(*args)
        where_calls << args
        :where_called
      end

      def where_calls
        @where_calls ||= [ ]
      end
    end

    @obj = Object.new
    class << @obj
      include ArRelationBaseSpecModule
      include LowCardTables::ActiveRecord::Relation
    end
  end

  it "should pass through if has_any_low_card_tables? is false" do
    expect(@obj).to receive(:has_any_low_card_tables?).once.and_return(false)
    @obj.where(:a, :b, :c).should == :where_called
    @obj.where_calls.should == [ [ :a, :b, :c ] ]
  end

  context "with has_any_low_card_tables? == true" do
    before :each do
      expect(@obj).to receive(:has_any_low_card_tables?).once.and_return(true)
    end

    it "should pass through if passed :_low_card_direct => true" do
      @obj.where(:a => :b, :c => :d, :_low_card_direct => true).should == :where_called
      @obj.where_calls.should == [ [ { :a => :b, :c => :d } ] ]
    end

    it "should delegate otherwise" do
      dmm = double('_low_card_dynamic_method_manager')
      expect(@obj).to receive(:_low_card_dynamic_method_manager).once.and_return(dmm)
      expect(dmm).to receive(:scope_from_query).once.with(@obj, :foo => :bar, :bar => :baz).and_return :yo_ho_ho
      @obj.where(:foo => :bar, :bar => :baz).should == :yo_ho_ho
      @obj.where_calls.length.should == 0
    end
  end
end
