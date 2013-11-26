require 'low_card_tables'

describe LowCardTables::ActiveRecord::Migrations do
  class MockMigrationClass
    attr_reader :calls

    def initialize
      @calls = [ ]
    end

    %w{add_column remove_column}.each do |method_name|
      class_eval %{
  def #{method_name}(*args)
    record_call(:#{method_name}, args)
  end}
    end

    %w{create_table change_table}.each do |method_name|
      class_eval %{
  def #{method_name}(*args, &block)
    record_call(:#{method_name}, args, &block)
    instance_eval(&block)
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
    @opts = { }
    @proc = lambda { |*args| }
  end

  it "should pass through correctly for :create_table" do
    @migration.create_table(:foo, @opts, &@proc)
    @migration.calls.should == [ { :name => :create_table, :args => [ :foo, @opts ], :block => @proc } ]
  end

  context "with mock ::Rails" do
    before :each do
      rails_class = Object.new
      Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
      Object.const_set(:Rails, rails_class)

      application = Object.new

      expect(rails_class).to receive(:application).at_least(:once).and_return(application)
      expect(application).to receive(:eager_load!).once
    end

    context "without mock low-card model" do
      it "should create a temporary low-card model if :low_card => true" do
        @opts[:low_card] = true

        temp_class = Class.new
        expect(Class).to receive(:new).once.with(::ActiveRecord::Base).and_return(temp_class).ordered
        expect(temp_class).to receive(:table_name=).once.with(:foo).ordered
        expect(temp_class).to receive(:is_low_card_table).once.with().ordered
        expect(temp_class).to receive(:reset_column_information).once.ordered

        expect(temp_class).to receive(:_low_card_remove_unique_index!).once.ordered

        expect(temp_class).to receive(:reset_column_information).at_least(2).times.ordered
        expect(temp_class).to receive(:low_card_value_column_names).twice.ordered.and_return([ 'x', 'y' ])

        expect(LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.ordered.with(temp_class)

        expect(temp_class).to receive(:_low_card_ensure_has_unique_index!).once.with(true).ordered

        @migration.create_table(:foo, @opts, &@proc)
        @migration.calls.should == [ { :name => :create_table, :args => [ :foo, { } ], :block => @proc } ]
      end
    end

    context "with mock low-card model" do
      before :each do
        non_low_card_class = Object.new
        @low_card_class = Object.new

        expect(non_low_card_class).to receive(:table_name).and_return('bar')
        expect(@low_card_class).to receive(:table_name).and_return('foo')

        expect(@low_card_class).to receive(:is_low_card_table?).and_return(true)
        expect(@low_card_class).to receive(:name).at_least(:once).and_return('Whatever')

        expect(::ActiveRecord::Base).to receive(:descendants).and_return([ non_low_card_class, @low_card_class ])
      end

      %w{add_column remove_column create_table change_table}.each do |method_name|
        context "#{method_name}" do
          before :each do
            @method = method_name.to_sym
            @args = case @method
            when :create_table then [ :foo, { :bar => :baz } ]
            when :change_table then [ :foo ]
            when :add_column then [ :foo, :bar, :integer, { :null => false } ]
            when :remove_column then [ :foo, :bar ]
            else raise "unknown method_name #{method_name.inspect}"
            end

            @proc = case @method
            when :create_table, :change_table then lambda { |*args| }
            else nil
            end
          end

          def add_option(args, hash)
            if args[-1].kind_of?(Hash)
              args[-1].merge!(hash)
            else
              args << hash
            end
          end

          def remove_low_card_options(args)
            out = args.dup
            if out[-1].kind_of?(Hash)
              out[-1].delete_if { |k,v| k.to_s =~ /^low_card/ }
              out.pop if out[-1].size == 0
            end
            out
          end

          it "should call #eager_load, pick up an AR descendant properly, and enforce the index" do
            expect(@low_card_class).to receive(:_low_card_remove_unique_index!).once.ordered

            expect(@low_card_class).to receive(:reset_column_information).at_least(2).times.ordered
            expect(@low_card_class).to receive(:low_card_value_column_names).twice.ordered.and_return([ 'x', 'y' ])

            expect(LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.ordered.with(@low_card_class)

            expect(@low_card_class).to receive(:_low_card_ensure_has_unique_index!).once.with(true).ordered

            @migration.send(@method, *@args, &@proc)
            @migration.calls.should == [ { :name => @method, :args => @args, :block => @proc } ]
          end

          it "should not reinstitute the index if :low_card_collapse_rows => true" do
            add_option(@args, :low_card_collapse_rows => false)

            expect(@low_card_class).to receive(:_low_card_remove_unique_index!).once.ordered

            expect(@low_card_class).to receive(:reset_column_information).at_least(2).times.ordered
            expect(@low_card_class).to receive(:low_card_value_column_names).twice.ordered.and_return([ 'x', 'y' ])

            expect(LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.ordered.with(@low_card_class)

            @migration.send(@method, *@args, &@proc)

            expected_args = remove_low_card_options(@args)
            @migration.calls.should == [ { :name => @method, :args => expected_args, :block => @proc } ]
          end

          it "should detect removed columns" do
            add_option(@args, :low_card_foo => :bar)

            expect(@low_card_class).to receive(:_low_card_remove_unique_index!).once.ordered

            expect(@low_card_class).to receive(:reset_column_information).at_least(2).times.ordered
            expect(@low_card_class).to receive(:low_card_value_column_names).once.ordered.and_return([ 'x', 'y' ])

            expect(LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.ordered.with(@low_card_class)

            expect(@low_card_class).to receive(:low_card_value_column_names).once.ordered.and_return([ 'y' ])
            expect(@low_card_class).to receive(:low_card_collapse_rows_and_update_referrers!).once.ordered.with(:low_card_foo => :bar)

            expect(@low_card_class).to receive(:_low_card_ensure_has_unique_index!).once.with(true).ordered

            @migration.send(@method, *@args, &@proc)
            expected_args = remove_low_card_options(@args)
            @migration.calls.should == [ { :name => @method, :args => expected_args, :block => @proc } ]
          end
        end
      end

      it "should not do anything twice if calls are nested" do
        @opts[:foo] = :bar

        expect(@low_card_class).to receive(:_low_card_remove_unique_index!).once.ordered

        expect(@low_card_class).to receive(:reset_column_information).at_least(2).times.ordered
        expect(@low_card_class).to receive(:low_card_value_column_names).twice.ordered.and_return([ 'x', 'y' ])

        expect(LowCardTables::VersionSupport).to receive(:clear_schema_cache!).once.ordered.with(@low_card_class)

        expect(@low_card_class).to receive(:_low_card_ensure_has_unique_index!).once.with(true).ordered

        inner_opts = { :a => :b, :low_card_foo => :bar }
        @proc = lambda do |*args|
          remove_column :bar, :baz, inner_opts
        end

        @migration.create_table(:foo, @opts, &@proc)
        @migration.calls.should == [
          { :name => :create_table, :args => [ :foo, { :foo => :bar } ], :block => @proc },
          { :name => :remove_column, :args => [ :bar, :baz, { :a => :b } ], :block => nil }
        ]
      end
    end
  end
end
