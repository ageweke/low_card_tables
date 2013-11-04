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

    describe "#scope_from_query" do
      before :each do
        @base_scope = double("base_scope")
        @end_scope = double("end_scope")
      end

      it "should pass through non-low-card constraints" do
        expect(@base_scope).to receive(:where).once.with({ :name => 'bonk', :_low_card_direct => true }).and_return(@end_scope)
        @manager.scope_from_query(@base_scope, { :name => 'bonk' }).should be(@end_scope)
      end

      it "should apply low-card constraints" do
        low_card_class_1 = double("low_card_class_1")
        allow(@association1).to receive(:low_card_class).and_return(low_card_class_1)
        expect(low_card_class_1).to receive(:low_card_ids_matching).with({ 'lc1m1' => false }).and_return([ 3, 9, 12 ])

        expect(@base_scope).to receive(:where).once.with("a1fk IN (:ids)", { :ids => [ 3, 9, 12 ] }).and_return(@end_scope)
        @manager.scope_from_query(@base_scope, { :cm1 => false }).should be(@end_scope)
      end

      it "should apply multiple low-card constraints combined with non-low-card constraints" do
        low_card_class_1 = double("low_card_class_1")
        allow(@association1).to receive(:low_card_class).and_return(low_card_class_1)
        expect(low_card_class_1).to receive(:low_card_ids_matching).with({ 'lc1m1' => false }).and_return([ 3, 9, 12 ])

        low_card_class_2 = double("low_card_class_2")
        allow(@association2).to receive(:low_card_class).and_return(low_card_class_2)
        expect(low_card_class_2).to receive(:low_card_ids_matching).with({ 'lc2m2' => [ :a, :b ], 'lc2m1' => 'yohoho' }).and_return([ 4, 6, 8 ])

        mid_scope = double("mid_scope")

        expect(@base_scope).to receive(:where).once.with("a1fk IN (:ids)", { :ids => [ 3, 9, 12 ] }).and_return(mid_scope)
        expect(mid_scope).to receive(:where).once.with("a2fk IN (:ids)", { :ids => [ 4, 6, 8 ] }).and_return(@end_scope)

        @manager.scope_from_query(@base_scope, { :cm1 => false, :cm3 => [ :a, :b ], :bar => { 'lc2m1' => "yohoho" } }).should be(@end_scope)
      end

      it "should apply low-card constraints in combination with direct foreign-key constraints" do
        low_card_class_1 = double("low_card_class_1")
        allow(@association1).to receive(:low_card_class).and_return(low_card_class_1)
        expect(low_card_class_1).to receive(:low_card_ids_matching).with({ 'lc1m1' => false }).and_return([ 3, 9, 12 ])

        mid_scope = double("mid_scope")

        expect(@base_scope).to receive(:where).once.with({ :a2fk => [ 1, 3, 12 ], :_low_card_direct => true }).and_return(mid_scope)
        expect(mid_scope).to receive(:where).once.with("a1fk IN (:ids)", { :ids => [ 3, 9, 12 ] }).and_return(@end_scope)

        @manager.scope_from_query(@base_scope, { :cm1 => false, :a2fk => [ 1, 3, 12] }).should be(@end_scope)
      end
    end

    describe "method delegation and invocation" do
      before :each do
        @invoked_object = double("invoked_object")
        @low_card_object = double("low_card_object")
        @args = double("args")
        @rv = double("rv")

        allow(@invoked_object).to receive(:kind_of?).with(@model_class).and_return(true)
      end

      def check_invocation(method_name, association_name, low_card_method_name)
        expect(@invoked_object).to receive(association_name).and_return(@low_card_object)
        expect(@low_card_object).to receive(low_card_method_name).with(@args).and_return(@rv)

        @methods_module.instance_methods.map(&:to_s).include?(method_name.to_s).should be

        @manager.run_low_card_method(@invoked_object, method_name, @args).should be(@rv)
      end

      context "after changing associations" do
        before :each do
          @manager.sync_methods!

          @association3 = double("association3")
          allow(@association3).to receive(:association_name).and_return("baz")
          allow(@association3).to receive(:foreign_key_column_name).and_return("a3fk")
          allow(@association3).to receive(:class_method_name_to_low_card_method_name_map).and_return({
            'cm2' => 'lc3m1', 'cm4' => 'lc3m2' })

          allow(@lcam).to receive(:associations).and_return([ @association1, @association3 ])

          @manager.sync_methods!
        end

        it "should run the right method for cm1" do
          check_invocation("cm1", "foo", "lc1m1")
        end

        it "should run the right method for cm2" do
          check_invocation("cm2", "baz", "lc3m1")
        end

        it "should run the right method for cm3" do
          @methods_module.instance_methods.map(&:to_s).include?("cm3").should_not be

          lambda { @manager.run_low_card_method(@invoked_object, "cm3", @args) }.should raise_error(NameError, /cm3/)
        end

        it "should run the right method for cm4" do
          check_invocation("cm4", "baz", "lc3m2")
        end
      end

      it "should run the right method for cm1" do
        check_invocation("cm1", "foo", "lc1m1")
      end

      it "should run the right method for cm2" do
        check_invocation("cm2", "bar", "lc2m1")
      end

      it "should run the right method for cm3" do
        check_invocation("cm3", "bar", "lc2m2")
      end

      def check_association(method_name, association)
        lcom = double("low_card_objects_manager")
        expect(@invoked_object).to receive(:_low_card_objects_manager).and_return(lcom)
        expect(lcom).to receive(:object_for).with(association).and_return(@low_card_object)

        @methods_module.instance_methods.map(&:to_s).include?(method_name).should be

        @manager.run_low_card_method(@invoked_object, method_name, [ ]).should be(@low_card_object)
      end

      it "should return the right association for foo" do
        check_association("foo", @association1)
      end

      it "should return the right association for bar" do
        check_association("bar", @association2)
      end

      def check_foreign_key_get(method_name, association)
        lcom = double("low_card_objects_manager")
        expect(@invoked_object).to receive(:_low_card_objects_manager).and_return(lcom)
        expect(lcom).to receive(:foreign_key_for).with(association).and_return(12345)

        @methods_module.instance_methods.map(&:to_s).include?(method_name).should be

        @manager.run_low_card_method(@invoked_object, method_name, [ ]).should == 12345
      end

      it "should return the right foreign key for a1fk" do
        check_foreign_key_get("a1fk", @association1)
      end

      it "should return the right foreign key for a2fk" do
        check_foreign_key_get("a2fk", @association2)
      end

      def check_foreign_key_set(method_name, association)
        args = double("args")
        lcom = double("low_card_objects_manager")
        expect(@invoked_object).to receive(:_low_card_objects_manager).and_return(lcom)
        expect(lcom).to receive(:set_foreign_key_for).with(association, args)

        @methods_module.instance_methods.map(&:to_s).include?(method_name).should be

        @manager.run_low_card_method(@invoked_object, method_name, args)
      end

      it "should set the right foreign key for a1fk" do
        check_foreign_key_set("a1fk=", @association1)
      end

      it "should set the right foreign key for a2fk" do
        check_foreign_key_set("a2fk=", @association2)
      end

      it "should blow up if asked to invoke a method that doesn't exist" do
        lambda do
          @manager.run_low_card_method(@invoked_object, "quux", [ ])
        end.should raise_error(/quux/i)
      end

      it "should blow up if given an object of the wrong class" do
        allow(@invoked_object).to receive(:kind_of?).with(@model_class).and_return(false)

        lambda do
          @manager.run_low_card_method(@invoked_object, "foo", [ ])
        end.should raise_error(ArgumentError)
      end
    end
  end
end
