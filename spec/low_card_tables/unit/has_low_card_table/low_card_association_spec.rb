require 'low_card_tables'

describe LowCardTables::HasLowCardTable::LowCardAssociation do
  before :each do
    @model_class = Class.new
    allow(@model_class).to receive(:name).and_return('model_class_name')

    col1 = double("column_1")
    allow(col1).to receive(:name).and_return("id")
    col2 = double("column_2")
    allow(col2).to receive(:name).and_return("name")
    col3 = double("column_3")
    allow(col3).to receive(:name).and_return("model_class_name_asc_name_id")

    allow(@model_class).to receive(:columns).and_return([ col1, col2, col3 ])

    class ::ModelClassNameAscName; end
    allow(ModelClassNameAscName).to receive(:is_low_card_table?).and_return(true)
  end

  it "should create a new, simple instance correctly" do
    expect(ModelClassNameAscName).to receive(:_low_card_referred_to_by).once.with(@model_class)
    association = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :asc_name, { })

    association.foreign_key_column_name.should == 'model_class_name_asc_name_id'
    association.low_card_class.should be(::ModelClassNameAscName)
  end
end
