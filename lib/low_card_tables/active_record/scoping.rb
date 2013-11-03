require 'active_support/concern'

module LowCardTables
  module ActiveRecord
    # This module gets included into ::ActiveRecord::Scoping. It overrides #scope to do one thing, and one thing only:
    # it checks to see if you're defining a scope that constrains on low-card columns, statically. ('Statically' here
    # means the deprecated-in-Rails-4.0+ style of 'scope :foo, where(...)' rather than 'scope :foo { where(...) }'.)
    # If it finds that you're trying to define such a scope, it throws an error.
    #
    # Why does it do this? Statically-defined scopes have their #where calls evaluated only once, at class-load time.
    # But part of the design of the low-card system is that new low-card rows can be added at runtime, and new rows
    # may well fit whatever constraint you're applying in this scope. The low-card system translates calls such as this:
    #
    #     where(:deleted => false)
    #
    # into clauses like this:
    #
    #     WHERE user_status_id IN (1, 3, 4, 5, 8, 9, 12)
    #
    # Because new rows can be added at any time, the list of status IDs needs to be able to be computed dynamically.
    # Static scopes prevent this, so we detect this condition here and raise an exception when it occurs.
    #
    # This sort of problem, by the way, is one of the reasons why static scope definitions are deprecated in Rails
    # 4.x.
    module Scoping
      extend ActiveSupport::Concern

      module ClassMethods
        # Overrides #scope to check for statically-defined scopes against low-card attributes, as discussed in the
        # comment for LowCardTables::ActiveRecord::Scoping.
        def scope(name, scope_options = {}, &block)
          # First, go invoke the superclass method.
          out = super(name, scope_options, &block)

          # We're safe if it's not a statically-defined scope.
          return out if block
          # We're also safe if this class doesn't refer to any low-card tables, because then it could not possibly
          # have been constraining on any low-card columns.
          return out if (! self.has_any_low_card_tables?)
          # If you defined a scope that isn't an actual ::ActiveRecord::Relation, you're fine.
          return out unless scope_options.kind_of?(::ActiveRecord::Relation)

          # ::ActiveRecord::Relation#where_values gets you a list of the 'where clauses' applied in the relation.
          used_associations = scope_options.where_values.map do |where_value|
            # Let's grab the SQL...
            sql = if where_value.respond_to?(:to_sql)
              where_value.to_sql
            elsif where_value.kind_of?(String)
              where_value
            end

            # ...and just search it for the foreign-key name. Is this foolproof? No; it's possible that you'll get some
            # false positives. Is this a big deal? No -- because changing a static scope to dynamic really has no
            # drawbacks at all, so there's a trivial fix for any false positives.
            self._low_card_associations_manager.associations.select do |association|
              foreign_key = association.foreign_key_column_name
              sql =~ /#{foreign_key}/i
            end
          end.flatten

          # Here's where we check for our problem and blow up if it's there.
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
