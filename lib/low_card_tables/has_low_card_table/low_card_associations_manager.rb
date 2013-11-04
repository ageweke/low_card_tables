require 'low_card_tables/has_low_card_table/low_card_association'
require 'low_card_tables/errors'

module LowCardTables
  module HasLowCardTable
    # The LowCardAssociationsManager is a relatively simple object; it manages the LowCardAssociation objects for a
    # given model class that refers to at least one low-card table. Conceptually, it does little more than maintain
    # an Array of such associations.
    #
    # (Note that storing this data as an Array is important: part of the contract of the low-card system is that
    # later calls to +has_low_card_table+ supersede earlier calls, so order is key. Yes, Ruby hashes are ordered in
    # recent Ruby versions...but we support 1.8.7, too.)
    class LowCardAssociationsManager
      # Returns an Array of all LowCardAssociation objects for the given +model_class+.
      attr_reader :associations

      # Creates a new instance. You should only ever create one instance per model class.
      def initialize(model_class)
        if (! superclasses(model_class).include?(::ActiveRecord::Base))
          raise ArgumentError, "You must supply an ActiveRecord model, not: #{model_class}"
        elsif model_class.is_low_card_table?
          raise ArgumentError, "A low-card table can't itself have low-card associations: #{model_class}"
        end

        @model_class = model_class
        @associations = [ ]
        @collapsing_update_scheme = :default

        install_methods!
      end

      # Called when +has_low_card_table+ is declared within the model class; this does all the actual work of
      # setting up the association. This removes any previous associations with the same name; again, we have a
      # 'last caller wins' policy.
      def has_low_card_table(association_name, options = { })
        unless association_name.kind_of?(Symbol) || (association_name.kind_of?(String) && association_name.strip.length > 0)
          raise ArgumentError, "You must supply an association name, not: #{association_name.inspect}"
        end

        association_name = association_name.to_s.strip.downcase
        @associations.delete_if { |a| a.association_name.to_s.strip.downcase == association_name }

        @associations << LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, association_name, options)

        @model_class._low_card_dynamic_method_manager.sync_methods!
      end

      # Called when someone has called ::ActiveRecord::Base#reset_column_information on the low-card model in question.
      # This simply tells the LowCardDynamicMethodManager to sync the methods on this model class, thus updating the
      # set of delegated methods to match the new columns.
      def low_card_column_information_reset!(low_card_model)
        @model_class._low_card_dynamic_method_manager.sync_methods!
      end

      # Retrieves the low-card association with the given name. Raises LowCardTables::Errors::LowCardAssociationNotFoundError
      # if not found.
      def _low_card_association(name)
        maybe_low_card_association(name) || (raise LowCardTables::Errors::LowCardAssociationNotFoundError, "There is no low-card association named '#{name}' for #{@model_class.name}; there are associations named: #{@associations.map(&:association_name).sort.join(", ")}.")
      end

      # Just like _low_card_association, but returns nil when an association is not found, rather than raising an error.
      def maybe_low_card_association(name)
        @associations.detect { |a| a.association_name.to_s.strip.downcase == name.to_s.strip.downcase }
      end

      # Updates all foreign keys that the given model_instance has to their correct values, given the set of attributes
      # that are associated with that model instance.
      def low_card_update_foreign_keys!(model_instance)
        ensure_correct_class!(model_instance)

        @associations.each do |association|
          association.update_foreign_key!(model_instance)
        end
      end

      DEFAULT_COLLAPSING_UPDATE_VALUE = 10_000

      # Gets, or sets, the current scheme for updating rows in this table when a low-card table has a column removed and
      # thus needs to have rows collapsed. Passing +nil+ or no arguments retrieves the current scheme; passing anything
      # else sets it. You can set this to:
      #
      # [:default] Rows will be updated in chunks of +DEFAULT_COLLAPSING_UPDATE_VALUE+ rows.
      # [:none] Nothing will be done; you are entirely on your own, and will have dangling foreign keys.
      # [a positive integer] Rows will be updated in chunks of this many rows at once.
      # [something that responds to :call] This object will have #call invoked on it when rows need to be updated; it
      #                                    will be passed the map of 'winners' to 'losers', and is responsible for
      #                                    updating rows any way you want.
      def low_card_value_collapsing_update_scheme(new_scheme = nil)
        if (! new_scheme)
          @collapsing_update_scheme
        elsif new_scheme == :default || new_scheme == :none
          @collapsing_update_scheme = new_scheme
        elsif new_scheme.kind_of?(Integer)
          raise ArgumentError, "You must specify an integer >= 1, not #{new_scheme.inspect}" unless new_scheme >= 1
          @collapsing_update_scheme = new_scheme
        elsif new_scheme.respond_to?(:call)
          @collapsing_update_scheme = new_scheme
        else
          raise ArgumentError, "Invalid collapsing update scheme: #{new_scheme.inspect}"
        end
      end

      # Called when a low-card model has just collapsed rows, presumably because it has had a column removed. This is
      # responsible for updating each foreign-key column, using the proper low_card_value_collapsing_update_scheme.
      def _low_card_update_collapsed_rows(low_card_model, collapse_map)
        update_scheme = @collapsing_update_scheme
        update_scheme = DEFAULT_COLLAPSING_UPDATE_VALUE if update_scheme == :default

        @associations.each do |association|
          if association.low_card_class == low_card_model
            association.update_collapsed_rows(collapse_map, update_scheme)
          end
        end
      end

      private
      # Makes sure that +model_instance+ is an instance of the model class this LowCardAssociationsManager is for.
      def ensure_correct_class!(model_instance)
        unless model_instance.kind_of?(@model_class)
          raise ArgumentError, %{Somehow, you passed #{model_instance}, an instance of #{model_instance.class}, to the LowCardAssociationsManager for #{@model_class}.}
        end
      end

      # Installs any methods we need on the model class -- right now, this is just our +before_save+ hook.
      def install_methods!
        @model_class.send(:before_save, :low_card_update_foreign_keys!)
      end

      # Fetches the entire superclass chain of a Class, up to, but not including, Object.
      def superclasses(c)
        out = [ ]

        c = c.superclass
        while c != Object
          out << c
          c = c.superclass
        end

        out
      end
    end
  end
end
