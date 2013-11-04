require 'low_card_tables'

describe LowCardTables::HasLowCardTable::Base do
  before :each do
    @spec_class = Class.new
    @spec_class.class_eval do
      include LowCardTables::HasLowCardTable::Base
    end
  end

  it "should always has_any_low_card_tables?" do
    @spec_class.has_any_low_card_tables?.should == true
  end

  context "with a low-card associations manager" do
    before :each do
      @lcam = double("low_card_associations_manager")
      expect(LowCardTables::HasLowCardTable::LowCardAssociationsManager).to receive(:new).once.with(@spec_class).and_return(@lcam)
    end

    it "should create and maintain one low-card associations manager" do
      @spec_class._low_card_associations_manager.should be(@lcam)
      @spec_class._low_card_associations_manager.should be(@lcam)
    end

    %w{has_low_card_table _low_card_association _low_card_update_collapsed_rows low_card_value_collapsing_update_scheme}.each do |method_name|
      it "should forward ##{method_name} to the LCAM" do
        args = [ :foo, { :bar => :baz } ]
        rv = Object.new
        expect(@lcam).to receive(method_name).once.with(*args).and_return(rv)

        @spec_class.send(method_name, *args).should be(rv)
      end
    end

    it "should forward low_card_update_foreign_keys! to the LCAM" do
      instance = @spec_class.new
      rv = Object.new

      expect(@lcam).to receive(:low_card_update_foreign_keys!).once.with(instance).and_return(rv)

      instance.low_card_update_foreign_keys!.should be(rv)
    end
  end

  it "should create and maintain one low-card dynamic methods manager" do
    @lcdmm = double("low_card_dynamic_methods_manager")
    expect(LowCardTables::HasLowCardTable::LowCardDynamicMethodManager).to receive(:new).once.with(@spec_class).and_return(@lcdmm)

    @spec_class._low_card_dynamic_method_manager.should be(@lcdmm)
    @spec_class._low_card_dynamic_method_manager.should be(@lcdmm)
  end

  it "should create and maintain one low-card dynamic methods module" do
    class HasLowCardTableBaseDynamicMethodsModuleTest
      include LowCardTables::HasLowCardTable::Base
    end

    HasLowCardTableBaseDynamicMethodsModuleTest.ancestors.detect { |a| a.name =~ /LowCardDynamicMethods/i }.should_not be

    mod = HasLowCardTableBaseDynamicMethodsModuleTest._low_card_dynamic_methods_module
    mod.class.should == ::Module
    HasLowCardTableBaseDynamicMethodsModuleTest.ancestors.include?(mod).should be
    HasLowCardTableBaseDynamicMethodsModuleTest.ancestors.detect { |a| a.name =~ /LowCardDynamicMethods/i }.should be

    HasLowCardTableBaseDynamicMethodsModuleTest.const_get(:LowCardDynamicMethods).should be(mod)

    HasLowCardTableBaseDynamicMethodsModuleTest._low_card_dynamic_methods_module.should be(mod)
  end

  it "should create and maintain one low-card objects manager" do
    lcom = double("low_card_objects_manager")
    obj = @spec_class.new
    expect(LowCardTables::HasLowCardTable::LowCardObjectsManager).to receive(:new).once.with(obj).and_return(lcom)

    obj._low_card_objects_manager.should be(lcom)
    obj._low_card_objects_manager.should be(lcom)
  end
end
