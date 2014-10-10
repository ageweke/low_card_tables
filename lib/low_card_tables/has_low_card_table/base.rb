require 'active_support/concern'
require 'low_card_tables/has_low_card_table/low_card_associations_manager'
require 'low_card_tables/has_low_card_table/low_card_objects_manager'
require 'low_card_tables/has_low_card_table/low_card_dynamic_method_manager'

module LowCardTables
  module HasLowCardTable
    # This module gets included (once) into any class that has declared a reference to at least one low-card table,
    # using #has_low_card_table. It is just a holder for several related objects that do all the actual work of
    # implementing the referring side of the low-card system.
    module Base
      # Documentation for class methods that get included via the ClassMethods module (which ActiveSupport::Concern
      # picks up).

      ##
      # :singleton-method: has_low_card_table
      # :call-seq:
      #   has_low_card_table(association_name, options = nil)
      #
      # Declares that this model class has a reference to a low-card table. +association_name+ is the name of the
      # association to create. +options+ can contain:
      #
      # [:delegate] If nil, no methods will be created in this class that delegate to the low-card table at all.
      #             If an Array, only methods matching those strings/symbols will be created.
      #             If a Hash, must contain a single key, +:except+, which maps to an Array; all methods except those
      #             methods will be created.
      #             Not specifying +:delegate+ causes it to delegate all methods in the low-card table.
      # [:prefix] If true, then delegated methods will be named with a prefix of the association name -- for example,
      #           +status_deleted+, +status_donation_level+, and so on.
      #           If a String or Symbol, then delegated methods will be named with that prefix -- for example,
      #           +foo_deleted+, +foo_donation_level+, and so on.
      #           Not specifying +:prefix+ is the same as saying +:prefix+ => +nil+, which causes methods not to be
      #           prefixed with anything.
      # [:foreign_key] Specifies the column in the referring table that contains the foreign key to the low-card table,
      #                just as in ActiveRecord associations. If not specified, it defaults to
      #                #{self.name.underscore}_#{association_name}_id -- for example, +user_status_id+.
      # [:class] Specifies the model class of the low-card table, as a String, Symbol, or Class object. If not
      #          specified, defaults to ("#{self.name.underscore.singularize}_#{association_name}".camelize.constantize)
      #          -- for example, +UserStatus+.

      ##
      # :singleton-method: low_card_value_collapsing_update_scheme
      # :call-seq:
      #    low_card_value_collapsing_update_scheme(scheme)
      #
      # Tells the low-card tables system what to do when a low-card table we refer to removes a column, which causes
      # it to collapse rows and thus necessitiates updating the referring column.
      #
      # * If called with no arguments, returns the current scheme.
      # * If passed an integer >= 1, automatically updates referring columns in this table, in chunks of that many
      #   rows. This is the default, with a value of 10,000.
      # * If passed an object that responds to #call, then, when columns need to be updated, the passed object is called
      #   with a Hash. This Hash has, as keys, instances of the low-card model class; these are the rows that will be
      #   preserved. Each key maps to an Array of one or more instances of the low-card model class; these are the
      #   rows that are to be replaced with the key. The passed object is then responsible for updating any values that
      #   correspond to rows in a value Array with the corresponding key value.
      # * If passed +:none+, then no updating is performed at all. You're on your own -- and you will have dangling
      #   foreign keys if you do nothing.

      extend ActiveSupport::Concern


      def ensure_proper_type
        if (assn = self.class.association_for_inheritance_column)
          superclass = self.class.superclass
          unless (superclass == ::ActiveRecord::Base) || (superclass.abstract_class?)
            lco = send(assn.association_name)
            lco.send(:write_attribute, self.class.inheritance_column, self.class.sti_name)
          end
        else
          super
        end
      end

      module ClassMethods
        # Several methods go straight to the LowCardAssociationsManager.
        delegate :has_low_card_table, :_low_card_association, :_low_card_update_collapsed_rows, :low_card_value_collapsing_update_scheme, :to => :_low_card_associations_manager

        # This overrides the implementation in LowCardTables::ActiveRecord::Base -- the only way we get included in
        # a class is if that class has declared has_low_card_table to at least one table.
        def has_any_low_card_tables?
          true
        end

        def association_for_inheritance_column
          _low_card_associations_manager.association_containing_method_named(inheritance_column)
        end

        def descends_from_active_record?
          out = super

          if out && (self != ::ActiveRecord::Base) && (! superclass.abstract_class?) && (superclass != ::ActiveRecord::Base)
            out = false if association_for_inheritance_column
          end

          out
        end

        def type_condition(table = arel_table)
          if (association = association_for_inheritance_column)
            sti_names  = ([self] + descendants).map { |model| model.sti_name }

            ids = association.low_card_class.low_card_ids_matching(inheritance_column => sti_names).to_a
            table[association.foreign_key_column_name].in(ids)
          else
            super
          end
        end

        def discriminate_class_for_record(record, call_super = true)
          if (! record[inheritance_column])
            if (association = association_for_inheritance_column)
              foreign_key = record[association.foreign_key_column_name]
              low_card_row = association.low_card_class.low_card_row_for_id(foreign_key)
              type = low_card_row.send(inheritance_column)

              return _low_card_find_sti_class(type) if type
            end
          end

          super(record) if call_super
        end

        if ::LowCardTables::VersionSupport.sti_uses_discriminate_class_for_record?
          def _low_card_find_sti_class(type)
            find_sti_class(type)
          end
        else
          def _low_card_find_sti_class(type_name)
            return self if type_name.blank?

            begin
              if store_full_sti_class
                ActiveSupport::Dependencies.constantize(type_name)
              else
                compute_type(type_name)
              end
            rescue NameError
              raise ::ActiveRecord::SubclassNotFound,
                "The single-table inheritance mechanism failed to locate the subclass: '#{type_name}'. " +
                "This error is raised because the column '#{inheritance_column}' is reserved for storing the class in case of inheritance. " +
                "Please rename this column if you didn't intend it to be used for storing the inheritance class " +
                "or overwrite #{name}.inheritance_column to use another column for that information."
            end
          end

          def instantiate(record)
            sti_class = discriminate_class_for_record(record, false)
            if sti_class
              record_id = sti_class.primary_key && record[sti_class.primary_key]

              if ::ActiveRecord::IdentityMap.enabled? && record_id
                instance = use_identity_map(sti_class, record_id, record)
              else
                instance = sti_class.allocate.init_with('attributes' => record)
              end

              instance
            else
              super
            end
          end
        end

        # The LowCardAssociationsManager keeps track of which low-card tables this table refers to; see its
        # documentation for more information.
        def _low_card_associations_manager
          @_low_card_associations_manager ||= LowCardTables::HasLowCardTable::LowCardAssociationsManager.new(self)
        end

        # The LowCardDynamicMethodManager is responsible for maintaining the right delegated method names in the
        # _low_card_dynamic_methods_module; see its documentation for more information.
        def _low_card_dynamic_method_manager
          @_low_card_dynamic_method_manager ||= LowCardTables::HasLowCardTable::LowCardDynamicMethodManager.new(self)
        end

        # This maintains a single module that gets included into this class; it is the place where we add all
        # delegated methods. We use a module rather than defining them directly on this class so that users can still
        # override them and use #super to call our implementation, if desired.
        def _low_card_dynamic_methods_module
          @_low_card_dynamic_methods_module ||= begin
            out = Module.new
            self.const_set(:LowCardDynamicMethods, out)
            include out
            out
          end
        end
      end

      # Updates the current values of all low-card reference columns according to the current attributes. This is
      # automatically called in a #before_save hook; you can also call it yourself at any time. Note that this can
      # cause new low-card rows to be created, if the current combination of attributes for a given low-card table
      # has not been used before.
      def low_card_update_foreign_keys!
        self.class._low_card_associations_manager.low_card_update_foreign_keys!(self)
      end

      # Returns the LowCardObjectsManager, which is responsible for maintaining the set of low-card objects accessed
      # by this model object -- the instances of the low-card class that are "owned" by this object. See that class's
      # documentation for more information.
      def _low_card_objects_manager
        @_low_card_objects_manager ||= LowCardTables::HasLowCardTable::LowCardObjectsManager.new(self)
      end
    end
  end
end
