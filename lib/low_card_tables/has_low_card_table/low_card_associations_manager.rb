require 'low_card_tables/has_low_card_table/low_card_association'
require 'low_card_tables/errors'

module LowCardTables
  module HasLowCardTable
    class LowCardAssociationsManager
      attr_reader :associations

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

      def has_low_card_table(association_name, options = { })
        unless association_name.kind_of?(Symbol) || (association_name.kind_of?(String) && association_name.strip.length > 0)
          raise ArgumentError, "You must supply an association name, not: #{association_name.inspect}"
        end

        association_name = association_name.to_s.strip.downcase
        @associations.delete_if { |a| a.association_name.to_s.strip.downcase == association_name }

        @associations << LowCardTables::HasLowCardTable::LowCardAssociation.new(@model_class, association_name, options)

        @model_class._low_card_dynamic_method_manager.sync_methods!
      end

      def low_card_column_information_reset!(low_card_model)
        @associations.each do |association|
          association.low_card_column_information_reset! if association.low_card_class == low_card_model
        end
      end

      def _low_card_association(name)
        out = @associations.detect { |a| a.association_name.to_s.strip.downcase == name.to_s.strip.downcase }
        out || (raise LowCardTables::Errors::LowCardAssociationNotFoundError, "There is no low-card association named '#{name}' for #{@model_class.name}; there are associations named: #{@associations.map(&:association_name).sort.join(", ")}.")
      end

      def low_card_update_foreign_keys!(model_instance)
        @associations.each do |association|
          association.update_value_before_save!(model_instance)
        end
      end

      DEFAULT_COLLAPSING_UPDATE_VALUE = 10_000

      def low_card_value_collapsing_update_scheme(new_scheme)
        if (! new_scheme)
          @collapsing_update_scheme
        elsif new_scheme == :default
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
      def install_methods!
        @model_class.send(:before_save, :low_card_update_foreign_keys!)
      end

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
