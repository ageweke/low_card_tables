require 'low_card_tables'

describe LowCardTables::ActiveRecord::Base do
  before :each do
    @klass = Class.new
    @klass.send(:include, LowCardTables::ActiveRecord::Base)
    allow(@klass).to receive(:inheritance_column=).with('_sti_on_low_card_tables_should_never_be_used')
  end

  it "should include LowCardTables::LowCardTable::Base appropriately and respond to #is_low_card_table? appropriately" do
    @klass.ancestors.include?(LowCardTables::LowCardTable::Base).should_not be
    @klass.is_low_card_table?.should_not be

    opts = Hash.new

    @klass.is_low_card_table(opts)
    @klass.is_low_card_table?.should be
    @klass.ancestors.include?(LowCardTables::LowCardTable::Base).should be
    @klass.low_card_options.should be(opts)

    # ...and again:
    opts = Hash.new

    @klass.is_low_card_table(opts)
    @klass.is_low_card_table?.should be
    @klass.ancestors.include?(LowCardTables::LowCardTable::Base).should be
    @klass.low_card_options.should be(opts)
  end

  it "should include LowCardTables::HasLowCardTable::Base appropriately and respond to #has_any_low_card_tables? appropriately" do
    @klass.ancestors.include?(LowCardTables::HasLowCardTable::Base).should_not be
    @klass.has_any_low_card_tables?.should_not be

    name = :foo
    opts = Hash.new

    mock_associations_manager = double('LowCardAssociationsManager')
    expect(mock_associations_manager).to receive(:has_low_card_table).with(name, opts).once
    expect(LowCardTables::HasLowCardTable::LowCardAssociationsManager).to receive(:new).and_return(mock_associations_manager)

    @klass.has_low_card_table(name, opts)
    @klass.has_any_low_card_tables?.should be
    @klass.ancestors.include?(LowCardTables::HasLowCardTable::Base).should be

    name = :bar
    opts = Hash.new

    expect(mock_associations_manager).to receive(:has_low_card_table).with(name, opts).once

    @klass.has_low_card_table(name, opts)
    @klass.has_any_low_card_tables?.should be
    @klass.ancestors.include?(LowCardTables::HasLowCardTable::Base).should be
  end
end
