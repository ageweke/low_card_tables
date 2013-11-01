require 'active_support/concern'

module LowCardTables
  module ActiveRecord
    module Scoping
      extend ActiveSupport::Concern

      module ClassMethods
        def scope(name, scope_options = {}, &block)
          out = super(name, scope_options, &block)

          return out if block
          return out if (! self.has_any_low_card_tables?)
          return out unless scope_options.kind_of?(::ActiveRecord::Relation)

          used_associations = scope_options.where_values.map do |where_value|
            sql = if where_value.respond_to?(:to_sql)
              where_value.to_sql
            elsif where_value.kind_of?(String)
              where_value
            end

            self._low_card_associations_manager.associations.select do |association|
              foreign_key = association.foreign_key_column_name
              sql =~ /#{foreign_key}/i
            end
          end.flatten

          if used_associations.length > 0
            raise LowCardTables::Errors::LowCardStaticScopeError, %{You defined a named scope, #{name.inspect}, on model #{self.name}. This scope
appears to constrain on the following foreign keys, which point to low-card tables.
Because this scope is defined statically (e.g., 'scope :foo, where(...)' rather than
'scope :foo { where(...) }'), these conditions will only be evaluated a single time,
at startup.

This means that if additional low-card rows get created that match the criteria for
this scope, they will never be picked up no matter what (as the WHERE clause is
frozen in time forever), and you will miss critical data.

The fix for this is simple: define this scope dynamically (i.e., enclose the
call to #where in a block). This will cause the conditions to be evaluated every
time you use it, thus updating the set of IDs used on every call, properly.

The foreign keys you appear to be constraining on are:

#{used_associations.map(&:foreign_key_column_name).sort.join(", ")}}
          end

          out
        end
      end
    end
  end
end
