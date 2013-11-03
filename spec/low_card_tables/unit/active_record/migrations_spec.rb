require 'low_card_tables'

describe LowCardTables::ActiveRecord::Migrations do
  class MockMigrationClass
    attr_reader :calls

    def initialize
      @calls = [ ]
    end

    %w{create_table add_column remove_column change_table}.each do |method_name|
      class_eval %{
  def #{method_name}(*args, &block)
    record_call(:#{method_name}, args, &block)
  end}
    end

    private
    def record_call(name, args, &block)
      @calls << { :name => name, :args => args, :block => block }
    end

    include LowCardTables::ActiveRecord::Migrations
  end

  before :each do
    @migration = MockMigrationClass.new
    @opts = Hash.new
    @proc = lambda { }
  end

  it "should pass through correctly for :create_table" do
    @migration.create_table(:foo, @opts, &@proc)
    @migration.calls.should == [ { :name => :create_table, :args => [ :foo, @opts ], :block => @proc } ]
  end

  context "with mock ::Rails" do
    before :each do
      rails_class = Object.new
      Object.const_set(:Rails, rails_class)

      application = Object.new

      expect(rails_class).to receive(:application).once.and_return(application)
      expect(application).to receive(:eager_load!).once
    end

    it "should call #eager_load, pick up an AR descendant properly, and enforce the index" do
      class1 = Object.new
      class2 = Object.new

      expect(class1).to receive(:table_name).and_return('bar')
      expect(class2).to receive(:table_name).and_return('foo')

      expect(class2).to receive(:is_low_card_table?).and_return(true)
      expect(class2).to receive(:name).at_least(:once).and_return('Whatever')

      expect(::ActiveRecord::Base).to receive(:descendants).and_return([ class1, class2 ])

      expect(class2).to receive(:_low_card_remove_unique_index!).once.ordered

      expect(class2).to receive(:reset_column_information).exactly(3).times.ordered
      expect(class2).to receive(:_low_card_value_column_names).twice.ordered.and_return([ 'x', 'y' ])

      expect(LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.ordered.with(class2)

      expect(class2).to receive(:_low_card_ensure_has_unique_index!).once.with(true).ordered

      @migration.create_table(:foo, @opts, &@proc)
      @migration.calls.should == [ { :name => :create_table, :args => [ :foo, @opts ], :block => @proc } ]
    end
  end
end
