require 'low_card_tables'

describe LowCardTables::HasLowCardTable::LowCardDynamicMethodManager do
  before :each do
    @model_class = double("model_class")
    @lcam = double("low_card_associations_manager")
    allow(@model_class).to receive(:_low_card_associations_manager).and_return(@lcam)

    @methods_module = Module.new
    allow(@model_class).to receive(:_low_card_dynamic_methods_module).and_return(@methods_module)

    @manager = LowCardTables::HasLowCardTable::LowCardDynamicMethodManager.new(@model_class)
  end

  context "with two associations and installed methods" do
    before :each do
      @association1 = double("association1")
      allow(@association1).to receive(:association_name).and_return("foo")
      allow(@association1).to receive(:foreign_key_column_name).and_return("a1fk")
      allow(@association1).to receive(:class_method_name_to_low_card_method_name_map).and_return({
        'cm1' => 'lc1m1', 'cm2' => 'lc1m2' })

      @association2 = double("association2")
      allow(@association2).to receive(:association_name).and_return("bar")
      allow(@association2).to receive(:foreign_key_column_name).and_return("a2fk")
      allow(@association2).to receive(:class_method_name_to_low_card_method_name_map).and_return({
        'cm2' => 'lc2m1', 'cm3' => 'lc2m2' })

      allow(@lcam).to receive(:associations).and_return([ @association1, @association2 ])

      @manager.sync_methods!
    end

    describe "method invocation" do
      before :each do
        @invoked_object = double("invoked_object")
        @low_card_object = double("low_card_object")
        @args = double("args")
        @rv = double("rv")
      end

      def check_invocation(method_name, association_name, low_card_method_name)
        expect(@invoked_object).to receive(association_name).and_return(@low_card_object)
        expect(@low_card_object).to receive(low_card_method_name).with(@args).and_return(@rv)

        @manager.run_low_card_method(@invoked_object, method_name, @args).should be(@rv)
      end

      it "should run the right method for cm1" do
        check_invocation("cm1", "foo", "lc1m1")
      end

      it "should run the right method for cm2" do
        check_invocation("cm2", "bar", "lc2m1")
        # check_invocation("cm2", "foo", "lc1m2")
      end

      it "should run the right method for cm3" do
        check_invocation("cm3", "bar", "lc2m2")
      end
    end
  end
end
