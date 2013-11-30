require 'low_card_tables'

describe LowCardTables::LowCardTable::TableUniqueIndex do
  def klass
    LowCardTables::LowCardTable::TableUniqueIndex
  end

  it "should require a low-card model for instantiation" do
    low_card_model = double("low_card_model")
    lambda { klass.new(low_card_model) }.should raise_error(ArgumentError)

    allow(low_card_model).to receive(:is_low_card_table?).and_return(false)
    lambda { klass.new(low_card_model) }.should raise_error(ArgumentError)
  end

  context "with an instance" do
    before :each do
      @low_card_model = double("low_card_model")
      allow(@low_card_model).to receive(:is_low_card_table?).and_return(true)
      allow(@low_card_model).to receive(:table_name).and_return("foobar")
      allow(@low_card_model).to receive(:low_card_value_column_names).and_return(%w{foo bar baz})
      allow(@low_card_model).to receive(:table_exists?).and_return(true)

      @connection = double("connection")
      allow(@low_card_model).to receive(:connection).and_return(@connection)

      @non_unique_index = double("non_unique_index")
      allow(@non_unique_index).to receive(:unique).and_return(false)
      allow(@non_unique_index).to receive(:name).and_return("nui")

      @unique_index_wrong_columns = double("unique_index_wrong_columns")
      allow(@unique_index_wrong_columns).to receive(:unique).and_return(true)
      allow(@unique_index_wrong_columns).to receive(:columns).and_return(%w{foo bar})
      allow(@unique_index_wrong_columns).to receive(:name).and_return("uiwc")

      @unique_index_right_columns = double("unique_index_right_columns")
      allow(@unique_index_right_columns).to receive(:unique).and_return(true)
      allow(@unique_index_right_columns).to receive(:columns).and_return(%w{bar foo baz})
      allow(@unique_index_right_columns).to receive(:name).and_return("uirc")

      @instance = klass.new(@low_card_model)
    end

    describe "#ensure_present!" do
      it "should do nothing if the table doesn't exist" do
        allow(@low_card_model).to receive(:table_exists?).and_return(false)

        @instance.ensure_present!(false)
        @instance.ensure_present!(true)
      end

      it "should do nothing if the index does exist" do
        allow(@connection).to receive(:indexes).with("foobar").and_return([ @non_unique_index, @unique_index_wrong_columns, @unique_index_right_columns ])
        @instance.ensure_present!(false)
        @instance.ensure_present!(true)
      end

      it "should raise if the index doesn't exist, and not told to create it" do
        allow(@connection).to receive(:indexes).with("foobar").and_return([ @non_unique_index, @unique_index_wrong_columns ])
        lambda { @instance.ensure_present!(false) }.should raise_error(LowCardTables::Errors::LowCardNoUniqueIndexError, /uiwc/i)
      end

      it "should create the index if it doesn't exist, and told to" do
        index_return_values = [
          [ @non_unique_index, @unique_index_wrong_columns ],
          [ @non_unique_index, @unique_index_wrong_columns ],
          [ @non_unique_index, @unique_index_wrong_columns, @unique_index_right_columns ]
        ]

        allow(@connection).to receive(:indexes).with("foobar") { index_return_values.shift }

        our_migration_class = Class.new
        allow(Class).to receive(:new).once.with(::ActiveRecord::Migration).and_return(our_migration_class)

        expect(our_migration_class).to receive(:migrate).once.with(:up)

        expect(@low_card_model).to receive(:reset_column_information).once
        expect(::LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.with(@low_card_model)

        @instance.ensure_present!(true)

        expect(our_migration_class).to receive(:remove_index).once.with("foobar", :name => "index_foobar_lc_on_all")
        expect(our_migration_class).to receive(:add_index).once.with("foobar", %w{bar baz foo}, :unique => true, :name => "index_foobar_lc_on_all")
        our_migration_class.up
      end
    end

    describe "#remove!" do
      it "should do nothing if there is no such index" do
        allow(@connection).to receive(:indexes).with("foobar").and_return([ @non_unique_index, @unique_index_wrong_columns ])
        @instance.remove!
      end

      it "should remove the index if there is one" do
        index_return_values = [
          [ @non_unique_index, @unique_index_wrong_columns, @unique_index_right_columns ],
          [ @non_unique_index, @unique_index_wrong_columns ]
        ]

        allow(@connection).to receive(:indexes).with("foobar") { index_return_values.shift }

        our_migration_class = Class.new
        allow(Class).to receive(:new).once.with(::ActiveRecord::Migration).and_return(our_migration_class)

        expect(our_migration_class).to receive(:migrate).once.with(:up)

        expect(@low_card_model).to receive(:reset_column_information).once
        expect(::LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.with(@low_card_model)

        @instance.remove!

        expect(our_migration_class).to receive(:remove_index).once.with("foobar", :name => "uirc")
        our_migration_class.up
      end
    end
  end
end
