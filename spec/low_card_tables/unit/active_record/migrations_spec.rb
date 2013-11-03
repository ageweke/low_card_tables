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
    record_call(:#{method_name}, args, block)
  end}
    end

    private
    def record_call(name, *args, &block)
      @calls << { :name => name, :args => args, :block => block }
    end

    include LowCardTables::ActiveRecord::Migrations
  end

  before :each do
    @migration = MockMigrationClass.new
  end

  it "should add a unique index on :create_table" do
    opts = Hash.new
    proc = lambda { }

    @migration.create_table(:foo, opts, &proc)
    @migration.create_table_calls.length.should == 1
  end
end
