require 'low_card_tables'
require 'active_support'

describe LowCardTables::ActiveRecord::Scoping do
  before :each do
    module ArScopingBaseSpecModule
      extend ActiveSupport::Concern

      module ClassMethods
        def scope(*args, &block)
          scope_calls << { :args => args, :block => block }
          :scope_called
        end

        def scope_calls
          @scope_calls ||= [ ]
        end

        def reset!
          @scope_calls = [ ]
        end
      end
    end

    class ArScopingTestClass
      include ArScopingBaseSpecModule
      include LowCardTables::ActiveRecord::Scoping
    end

    ArScopingTestClass.reset!
  end

  it "should pass through if given a block" do
    proc = lambda { }
    ArScopingTestClass.scope(:foo, :bar => :baz, &proc).should == :scope_called
    ArScopingTestClass.scope_calls.should == [ { :args => [ :foo, { :bar => :baz } ], :block => proc } ]
  end

  it "should pass through if there are no low-card tables" do
    expect(ArScopingTestClass).to receive(:has_any_low_card_tables?).and_return(false)
    ArScopingTestClass.scope(:foo, :bar => :baz).should == :scope_called
    ArScopingTestClass.scope_calls.should == [ { :args => [ :foo, { :bar => :baz } ], :block => nil } ]
  end

  it "should pass through if it isn't handed a Relation" do
    expect(ArScopingTestClass).to receive(:has_any_low_card_tables?).and_return(true)
    ArScopingTestClass.scope(:foo, :bar => :baz).should == :scope_called
    ArScopingTestClass.scope_calls.should == [ { :args => [ :foo, { :bar => :baz } ], :block => nil } ]
  end

  context "with low-card tables and a Relation" do
    before :each do
      expect(ArScopingTestClass).to receive(:has_any_low_card_tables?).and_return(true)
      @relation = Object.new
      expect(@relation).to receive(:kind_of?).with(::ActiveRecord::Relation).and_return(true)

      @associations = [ Object.new, Object.new ]
      expect(@associations[0]).to receive(:foreign_key_column_name).at_least(:once).and_return("fk1")
      expect(@associations[1]).to receive(:foreign_key_column_name).at_least(:once).and_return("fk2")

      @lcam = double('low_card_associations_manager')
      expect(ArScopingTestClass).to receive(:_low_card_associations_manager).at_least(:once).and_return(@lcam)
      expect(@lcam).to receive(:associations).at_least(:once).and_return(@associations)
    end

    it "should be fine as long as you don't use any of the foreign keys" do
      where_values = [ "foo=a", "bar=b" ]
      expect(@relation).to receive(:where_values).and_return(where_values)

      ArScopingTestClass.scope(:foo, @relation).should == :scope_called
      ArScopingTestClass.scope_calls.should == [ { :args => [ :foo, @relation ], :block => nil } ]
    end

    it "should blow up if you do use any of the foreign keys" do
      where_values = [ "foo=a", "fk2=b" ]
      expect(@relation).to receive(:where_values).and_return(where_values)

      lambda { ArScopingTestClass.scope(:foo, @relation) }.should raise_error(LowCardTables::Errors::LowCardStaticScopeError, /fk2/i)
      ArScopingTestClass.scope_calls.should == [ { :args => [ :foo, @relation ], :block => nil } ]
    end

    it "should blow up if you do use any of the foreign keys, with #to_sql necessary" do
      wv2 = Object.new
      expect(wv2).to receive(:to_sql).at_least(:once).and_return("fk2=b")
      where_values = [ "foo=a", wv2 ]
      expect(@relation).to receive(:where_values).and_return(where_values)

      lambda { ArScopingTestClass.scope(:foo, @relation) }.should raise_error(LowCardTables::Errors::LowCardStaticScopeError, /fk2/i)
      ArScopingTestClass.scope_calls.should == [ { :args => [ :foo, @relation ], :block => nil } ]
    end

    it "should skip where values that aren't a String and don't respond to :to_sql" do
      wv2 = Object.new
      where_values = [ "foo=a", wv2 ]
      expect(@relation).to receive(:where_values).and_return(where_values)

      ArScopingTestClass.scope(:foo, @relation).should == :scope_called
      ArScopingTestClass.scope_calls.should == [ { :args => [ :foo, @relation ], :block => nil } ]
    end
  end
end
