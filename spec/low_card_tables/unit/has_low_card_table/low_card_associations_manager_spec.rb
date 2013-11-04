require 'low_card_tables'

describe LowCardTables::HasLowCardTable::LowCardAssociationsManager do
  describe "instantiation" do
    it "should require a Class that descends from ActiveRecord::Base" do
      klass = Class.new(String)

      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociationsManager.new(klass)
      end.should raise_error(ArgumentError)
    end

    it "should require a Class that is not itself a low-card class" do
      klass = Class.new(::ActiveRecord::Base)
      allow(klass).to receive(:is_low_card_table?).and_return(true)

      lambda do
        LowCardTables::HasLowCardTable::LowCardAssociationsManager.new(klass)
      end.should raise_error(ArgumentError)
    end
  end

  context "with a normal model class" do
    before :each do
      @model_class = Class.new
      allow(@model_class).to receive(:superclass).and_return(::ActiveRecord::Base)
      allow(@model_class).to receive(:is_low_card_table?).and_return(false)
      expect(@model_class).to receive(:before_save).once.with(:low_card_update_foreign_keys!)

      @manager = LowCardTables::HasLowCardTable::LowCardAssociationsManager.new(@model_class)
    end

    it "should have no associations by default" do
      @manager.associations.should == [ ]
    end

    it "should have a default :low_card_value_collapsing_update_scheme" do
      @manager.low_card_value_collapsing_update_scheme.should == :default
    end

    describe "#low_card_value_collapsing_update_scheme" do
      it "should return :default by default" do
        @manager.low_card_value_collapsing_update_scheme.should == :default
      end

      it "should be settable to :none or :default" do
        @manager.low_card_value_collapsing_update_scheme :none
        @manager.low_card_value_collapsing_update_scheme.should == :none
        @manager.low_card_value_collapsing_update_scheme :default
        @manager.low_card_value_collapsing_update_scheme.should == :default
      end

      it "should be settable to a positive integer" do
        @manager.low_card_value_collapsing_update_scheme 1
        @manager.low_card_value_collapsing_update_scheme.should == 1
        @manager.low_card_value_collapsing_update_scheme 345
        @manager.low_card_value_collapsing_update_scheme.should == 345

        lambda { @manager.low_card_value_collapsing_update_scheme 0 }.should raise_error(ArgumentError)
        lambda { @manager.low_card_value_collapsing_update_scheme -27 }.should raise_error(ArgumentError)
      end

      it "should be settable to something that responds to :call" do
        callable = double("callable")
        allow(callable).to receive(:call)

        @manager.low_card_value_collapsing_update_scheme callable
        @manager.low_card_value_collapsing_update_scheme.should be(callable)
      end

      it "should not be settable to anything else" do
        lambda { @manager.low_card_value_collapsing_update_scheme "foo" }.should raise_error(ArgumentError)
      end
    end

    describe "#has_low_card_table" do
      it "should require a non-blank association name" do
        lambda { @manager.has_low_card_table(nil) }.should raise_error(ArgumentError)
        lambda { @manager.has_low_card_table("") }.should raise_error(ArgumentError)
        lambda { @manager.has_low_card_table("   ") }.should raise_error(ArgumentError)
      end

      context "with one association" do
        before :each do
          options = { :a => :b, :c => :d }

          @association = double("low_card_association")
          expect(LowCardTables::HasLowCardTable::LowCardAssociation).to receive(:new).once.with(@model_class, 'foo', options).and_return(@association)

          lcdmm = double("low_card_dynamic_method_manager")
          expect(@model_class).to receive(:_low_card_dynamic_method_manager).at_least(:once).and_return(lcdmm)

          expect(lcdmm).to receive(:sync_methods!).at_least(:once)

          @manager.has_low_card_table(:foo, options)
        end

        it "should create a new association and add it to the list" do
          @manager.associations.should == [ @association ]
        end

        it "should remove any previous associations with the same name" do
          new_options = { :x => :y, :z => :a }
          allow(@association).to receive(:association_name).and_return("foo")

          association2 = double("association2")

          expect(LowCardTables::HasLowCardTable::LowCardAssociation).to receive(:new).once.with(@model_class, 'foo', new_options).and_return(association2)

          @manager.has_low_card_table('foo', new_options)
          @manager.associations.should == [ association2 ]
        end

        context "and another association" do
          before :each do
            new_options = { :x => :y, :z => :a }
            allow(@association).to receive(:association_name).and_return("foo")

            @association2 = double("association2")
            allow(@association2).to receive(:association_name).and_return("bar")

            expect(LowCardTables::HasLowCardTable::LowCardAssociation).to receive(:new).once.with(@model_class, 'bar', new_options).and_return(@association2)

            @manager.has_low_card_table('bar', new_options)
            @manager.associations.should == [ @association, @association2 ]
          end

          it "should retrieve them by name" do
            @manager._low_card_association("foo").should == @association
            @manager._low_card_association("bar").should == @association2
            @manager.maybe_low_card_association("foo").should == @association
            @manager.maybe_low_card_association("bar").should == @association2
          end

          it "should do the right thing when they're not found" do
            @manager.maybe_low_card_association("baz").should_not be
            lambda { @manager._low_card_association("baz") }.should raise_error(LowCardTables::Errors::LowCardAssociationNotFoundError, /bar[\s,]+foo/)
          end

          it "should update all foreign keys on #low_card_update_foreign_keys!" do
            model_instance = double("model_instance")
            allow(model_instance).to receive(:kind_of?).with(@model_class).and_return(true)

            @association.should receive(:update_foreign_key!).once.with(model_instance)
            @association2.should receive(:update_foreign_key!).once.with(model_instance)

            @manager.low_card_update_foreign_keys!(model_instance)
          end

          it "should blow up if passed something that isn't of the correct class to #low_card_update_foreign_keys!" do
            model_instance = double("model_instance")
            allow(model_instance).to receive(:kind_of?).with(@model_class).and_return(false)

            lambda { @manager.low_card_update_foreign_keys!(model_instance) }.should raise_error(ArgumentError)
          end

          describe "_low_card_update_collapsed_rows" do
            it "should call #update_collapsed_rows on associations that match the low-card model class passed" do
              @manager.low_card_value_collapsing_update_scheme 345

              low_card_class = double("low_card_class")
              other_low_card_class = double("other_low_card_class")

              collapse_map = double("collapse_map")

              allow(@association).to receive(:low_card_class).and_return(other_low_card_class)
              allow(@association2).to receive(:low_card_class).and_return(low_card_class)

              expect(@association2).to receive(:update_collapsed_rows).with(collapse_map, 345).once

              @manager._low_card_update_collapsed_rows(low_card_class, collapse_map)
            end
          end
        end
      end
    end

    describe "#low_card_column_information_reset!" do
      it "should call through to the model class" do
        low_card_model = double("low_card_model")

        lcdmm = double("low_card_dynamic_method_manager")
        expect(@model_class).to receive(:_low_card_dynamic_method_manager).and_return(lcdmm)
        expect(lcdmm).to receive(:sync_methods!).once

        @manager.low_card_column_information_reset!(low_card_model)
      end
    end
  end
end
