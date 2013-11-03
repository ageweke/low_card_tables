require 'low_card_tables'

describe LowCardTables::HasLowCardTable::LowCardAssociation do
  class ::ModelClassNameAscName; end

  before :each do
    @model_class = Class.new
    allow(@model_class).to receive(:name).and_return('model_class_name')

    col1 = double("column_1")
    allow(col1).to receive(:name).and_return("id")
    col2 = double("column_2")
    allow(col2).to receive(:name).and_return("name")
    @col3 = double("column_3")
    allow(@col3).to receive(:name).and_return("model_class_name_asc_name_id")

    allow(@model_class).to receive(:columns).and_return([ col1, col2, @col3 ])

    allow(ModelClassNameAscName).to receive(:is_low_card_table?).and_return(true)
  end

  context "with a referred-to class" do
    before :each do
      expect(ModelClassNameAscName).to receive(:_low_card_referred_to_by).once.with(@model_class)
    end

    it "should create a new, simple instance correctly, and tell the referred-to class" do
      association = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :asc_name, { })

      association.association_name.should == 'asc_name'
      association.foreign_key_column_name.should == 'model_class_name_asc_name_id'
      association.low_card_class.should be(::ModelClassNameAscName)
    end

    describe "options" do
      {
        ::ModelClassNameAscName => 'Class object',
        'ModelClassNameAscName' => 'String',
        :ModelClassNameAscName => 'Symbol'
      }.each do |input, description|
        it "should allow setting the referred-to class name by #{description}" do
          allow(@col3).to receive(:name).and_return("model_class_name_foobar_id")
          association = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :foobar, { :class => input })

          association.association_name.should == 'foobar'
          association.foreign_key_column_name.should == 'model_class_name_foobar_id'
          association.low_card_class.should be(::ModelClassNameAscName)
        end
      end

      it "should allow setting the foreign key" do
        association = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :foobar, { })

        association.association_name.should == 'foobar'
        association.foreign_key_column_name.should == 'model_class_name_asc_name_id'
        association.low_card_class.should be(::ModelClassNameAscName)
      end
    end
  end
end
