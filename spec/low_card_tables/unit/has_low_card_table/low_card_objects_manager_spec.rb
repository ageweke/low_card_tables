require 'low_card_tables'

describe LowCardTables::HasLowCardTable::LowCardObjectsManager do
  before :each do
    @model_instance = double("model_instance")
    @manager = LowCardTables::HasLowCardTable::LowCardObjectsManager.new(@model_instance)

    @model_class = double("model_class")
    allow(@model_instance).to receive(:class).and_return(@model_class)

    @lcam = double("low_card_associations_manager")
    allow(@model_class).to receive(:_low_card_associations_manager).and_return(@lcam)

    @association1 = double("LowCardAssociation")
    allow(@association1).to receive(:association_name).and_return("foo")
    allow(@association1).to receive(:foreign_key_column_name).and_return("blahblah_id")
  end

  describe "#object_for" do
    it "should call through to the association to create the object, and only once" do
      associated_object = double("associated_object")

      expect(@lcam).to receive(:_low_card_association).with("foo").and_return(@association1)
      expect(@association1).to receive(:create_low_card_object_for).once.with(@model_instance).and_return(associated_object)

      @manager.object_for(@association1).should be(associated_object)
      @manager.object_for(@association1).should be(associated_object)
    end

    it "should maintain multiple associcated objects separately" do
      associated_object_1 = double("associated_object_1")
      associated_object_2 = double("associated_object_2")

      @association2 = double("LowCardAssociation2")
      allow(@association2).to receive(:association_name).and_return("bar")

      expect(@lcam).to receive(:_low_card_association).with("foo").and_return(@association1)
      expect(@association1).to receive(:create_low_card_object_for).once.with(@model_instance).and_return(associated_object_1)

      expect(@lcam).to receive(:_low_card_association).with("bar").and_return(@association2)
      expect(@association2).to receive(:create_low_card_object_for).once.with(@model_instance).and_return(associated_object_2)

      @manager.object_for(@association1).should be(associated_object_1)
      @manager.object_for(@association2).should be(associated_object_2)
      @manager.object_for(@association1).should be(associated_object_1)
      @manager.object_for(@association2).should be(associated_object_2)
    end
  end

  describe "foreign-key support" do
    it "should call through to the model instance on get" do
      expect(@model_instance).to receive(:[]).with("blahblah_id").and_return(12345)
      @manager.foreign_key_for(@association1).should == 12345
    end

    it "should call through to the model instance on set, invalidate the object, and return the new value" do
      associated_object_1 = double("associated_object_1")
      expect(@lcam).to receive(:_low_card_association).with("foo").at_least(:once).and_return(@association1)
      expect(@association1).to receive(:create_low_card_object_for).once.with(@model_instance).and_return(associated_object_1)
      @manager.object_for(@association1).should be(associated_object_1)

      expect(@model_instance).to receive(:[]=).with("blahblah_id", 23456)
      @manager.set_foreign_key_for(@association1, 23456).should == 23456

      associated_object_2 = double("associated_object_2")
      expect(@association1).to receive(:create_low_card_object_for).once.with(@model_instance).and_return(associated_object_2)
      @manager.object_for(@association1).should be(associated_object_2)
    end
  end
end
