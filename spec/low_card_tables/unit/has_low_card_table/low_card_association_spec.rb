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

  describe "instantiation" do
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
          :ModelClassNameAscName => 'Symbol',
          :model_class_name_asc_name => 'Symbol (underscored)',
          'model_class_name_asc_name' => 'String (underscored)'
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
          association = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :foobar, { :class => ModelClassNameAscName, :foreign_key => :model_class_name_asc_name_id })

          association.association_name.should == 'foobar'
          association.foreign_key_column_name.should == 'model_class_name_asc_name_id'
          association.low_card_class.should be(::ModelClassNameAscName)
        end
      end
    end

    it "should fail instantiation if the foreign key specified isn't a column" do
      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :foobar,
          { :class => ModelClassNameAscName, :foreign_key => :bogus_id })
      end.should raise_error(ArgumentError, /bogus_id/i)
    end

    it "should fail instantiation if the foreign key inferred isn't a column" do
      allow(@col3).to receive(:name).and_return("whatever")
      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :foobar,
          { :class => ModelClassNameAscName })
      end.should raise_error(ArgumentError, /model_class_name_foobar_id/i)
    end

    it "should fail instantiation if the class inferred can't be found" do
      allow(@col3).to receive(:name).and_return("model_class_name_yohoho_id")
      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :yohoho, { })
      end.should raise_error(ArgumentError, /ModelClassNameYohoho/i)
    end

    it "should fail instantiation if the class specified can't be found" do
      allow(@col3).to receive(:name).and_return("model_class_name_yohoho_id")
      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :yohoho, { :class => :FooBar })
      end.should raise_error(ArgumentError, /FooBar/i)
    end

    it "should fail instantiation if the class specified isn't a Class" do
      ::Object.const_set(:FooBar1, "hi")

      allow(@col3).to receive(:name).and_return("model_class_name_yohoho_id")
      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :yohoho, { :class => :FooBar1 })
      end.should raise_error(ArgumentError, /\"hi\"/i)
    end

    it "should fail instantiation if the class specified doesn't respond to is_low_card_table" do
      klass = Class.new

      allow(@col3).to receive(:name).and_return("model_class_name_yohoho_id")
      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :yohoho, { :class => klass })
      end.should raise_error(ArgumentError, /is_low_card_table/i)
    end

    it "should fail instantiation if the class specified isn't a low-card table Class" do
      klass = Class.new
      expect(klass).to receive(:is_low_card_table?).and_return(false)

      allow(@col3).to receive(:name).and_return("model_class_name_yohoho_id")
      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :yohoho, { :class => klass })
      end.should raise_error(ArgumentError, /is_low_card_table/i)
    end
  end

  describe "#delegated_method_names" do
    def check_delegated_method_names(options, expected_results)
      expect(ModelClassNameAscName).to receive(:_low_card_referred_to_by).once.with(@model_class)
      expect(ModelClassNameAscName).to receive(:_low_card_value_column_names).and_return(%w{foo bar baz})
      association = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :asc_name, options)
      association.delegated_method_names.sort.should == expected_results.sort
    end

    it "should contain all methods by default" do
      check_delegated_method_names({ }, %w{foo bar baz})
    end

    it "should contain no methods if :delegate => false" do
      check_delegated_method_names({ :delegate => false }, [ ])
    end

    it "should contain only specified methods if specified" do
      check_delegated_method_names({ :delegate => %w{bar baz} }, %w{bar baz})
    end

    it "should contain only a single method if specified (Symbol)" do
      check_delegated_method_names({ :delegate => :bar }, %w{bar})
    end

    it "should contain only a single method if specified (String)" do
      check_delegated_method_names({ :delegate => 'bar' }, %w{bar})
    end

    it "should exclude certain methods if specified" do
      check_delegated_method_names({ :delegate => { :except => %w{bar baz} } }, %w{foo})
    end

    it "should blow up if passed anything else" do
      lambda do
        check_delegated_method_names({ :delegate => { :a => :b } }, %w{foo})
      end.should raise_error(ArgumentError)

      lambda do
        check_delegated_method_names({ :delegate => 123 }, %w{foo})
      end.should raise_error(ArgumentError)
    end
  end

  describe "#class_method_name_to_low_card_method_name_map" do
    def check_class_method_name_to_low_card_method_name_map(options, expected_results)
      expect(ModelClassNameAscName).to receive(:_low_card_referred_to_by).once.with(@model_class)
      expect(ModelClassNameAscName).to receive(:_low_card_value_column_names).and_return(%w{foo bar baz})
      association = LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, :asc_name, options)

      association.class_method_name_to_low_card_method_name_map.should == expected_results
    end

    it "should map all methods to their same names by default" do
      check_class_method_name_to_low_card_method_name_map({ }, {
        'foo' => 'foo', 'foo=' => 'foo=', 'bar' => 'bar', 'bar=' => 'bar=', 'baz' => 'baz', 'baz=' => 'baz=' })
    end

    it "should exclude methods if requested" do
      check_class_method_name_to_low_card_method_name_map({ :delegate => %w{foo bar} }, {
        'foo' => 'foo', 'foo=' => 'foo=', 'bar' => 'bar', 'bar=' => 'bar=' })
    end

    it "should prefix methods if requested" do
      check_class_method_name_to_low_card_method_name_map({ :prefix => true }, {
        'asc_name_foo' => 'foo', 'asc_name_foo=' => 'foo=', 'asc_name_bar' => 'bar', 'asc_name_bar=' => 'bar=',
        'asc_name_baz' => 'baz', 'asc_name_baz=' => 'baz=' })
    end

    it "should prefix methods with a given string if requested" do
      check_class_method_name_to_low_card_method_name_map({ :prefix => :quux }, {
        'quux_foo' => 'foo', 'quux_foo=' => 'foo=', 'quux_bar' => 'bar', 'quux_bar=' => 'bar=',
        'quux_baz' => 'baz', 'quux_baz=' => 'baz=' })
    end
  end
end
