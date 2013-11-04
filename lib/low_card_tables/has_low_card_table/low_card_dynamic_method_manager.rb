module LowCardTables
  module HasLowCardTable
    # This object is responsible for maintaining the set of methods that get automatically delegated when you declare
    # +has_low_card_table+ on an ::ActiveRecord model -- it both maintains the set of methods defined on the
    # _low_card_dynamic_methods_module for that class, and directs the calls in the right place at runtime.
    #
    # Secondarily, it also is responsible for transforming query specifications -- #scope_from_query takes the set of
    # constraints you passed, as a Hash, to ::ActiveRecord::Relation#where, and transforms them using low-card
    # information. So:
    #
    #    { :deleted => true, :deceased => false }
    #
    # might become
    #
    #    { :user_status_id => [ 1, 3, 9, 17 ] }
    #
    # While it might seem odd for that functionality to live in this class, it actually makes sense; this is the
    # class that knows what method names in the low-card class those keys map to, after all.
    class LowCardDynamicMethodManager
      def initialize(model_class)
        @model_class = model_class
        @method_delegation_map = { }
      end

      def run_low_card_method(object, method_name, args)
        method_data = @method_delegation_map[method_name.to_s]
        unless method_data
          raise "Whoa -- we're trying to call a delegated low-card method #{method_name.inspect} on #{object}, of class #{object.class}, but somehow the LowCardDynamicMethodManager has no knowledge of that method?!? We know about: #{@method_delegation_map.keys.sort.inspect}"
        end

        (association, association_method_name) = method_data

        if association_method_name == :_low_card_object
          object._low_card_objects_manager.object_for(association)
        elsif association_method_name == :_low_card_foreign_key
          object._low_card_objects_manager.foreign_key_for(association)
        elsif association_method_name == :_low_card_foreign_key=
          object._low_card_objects_manager.set_foreign_key_for(association, *args)
        else
          low_card_object = object.send(association.association_name)
          low_card_object.send(association_method_name, *args)
        end
      end

      def scope_from_query(base_scope, query_hash)
        final_constraints = { }
        low_card_association_to_constraint_map = { }

        query_hash.each do |query_key, query_value|
          low_card_delegation = @method_delegation_map[query_key.to_s]

          if low_card_delegation
            (association, method) = low_card_delegation

            if method == :_low_card_object
              if (! query_value.kind_of?(Hash))
                raise ArgumentError, %{You are trying to constrain on #{@model_class.name}.#{query_key}, which is a low-card association,
but the value you passed, #{query_value.inspect}, is not a Hash. Either pass a Hash,
or constrain on #{association.foreign_key_column_name} explicitly, and find IDs
yourself, using #{association.low_card_class.name}#ids_matching.}
              end

              low_card_association_to_constraint_map[association] ||= { }
              low_card_association_to_constraint_map[association].merge!(query_value)
            elsif method == :_low_card_foreign_key
              final_constraints[query_key] = query_value
            else
              low_card_association_to_constraint_map[association] ||= { }
              low_card_association_to_constraint_map[association][method] = query_value
            end
          else
            final_constraints[query_key] = query_value
          end
        end

        out = base_scope
        out = base_scope.where(final_constraints.merge(:_low_card_direct => true)) if final_constraints.size > 0

        # This is gross. In ActiveRecord v3, doing something like this:
        #
        #    Model.where(:x => [ 1, 2, 3 ]).where(:x => [ 3, 4, 5 ])
        #
        # ...results in "... WHERE x IN (3, 4, 5)" -- i.e., it's last-clause wins, and the first one is totally
        # ignored. While this sucks in general (in my opinion), it's genuinely a problem for our system; we need to
        # be able to say Model.where(:deleted => false).where(:deceased => false) and only get back non-deleted, alive
        # users -- and, underneath, both those queries transform to conditions on :user_status_id.
        #
        # Our workaround is to instead use text-based queries for these conditions, because:
        #
        #    Model.where("x IN :ids", :ids => [ 1, 2, 3 ]).where("x IN :ids", :ids => [ 3, 4, 5 ])
        #
        # ...results in "... WHERE x IN (1, 2, 3) AND x IN (3, 4, 5)", which gives us the right value. (ActiveRecord
        # doesn't ever parse SQL you hand to it, so it has no way of knowing these are conditions on the same column --
        # so it keeps both clauses.)
        #
        # ActiveRecord 4 does the right thing here (IMHO) and behaves identically whether you pass in a Hash or a text
        # clause. However, our hack works fine with both versions, so we'll keep it for now.
        low_card_association_to_constraint_map.each do |association, constraints|
          ids = association.low_card_class.low_card_ids_matching(constraints)
          out = out.where("#{association.foreign_key_column_name} IN (:ids)", :ids => ids)
        end


        out
      end

      def sync_methods!
        currently_delegated_methods = @method_delegation_map.keys

        @method_delegation_map = { }

        associations.each do |association|
          @method_delegation_map[association.association_name.to_s] = [ association, :_low_card_object ]
          @method_delegation_map[association.foreign_key_column_name.to_s] = [ association, :_low_card_foreign_key ]
          @method_delegation_map[association.foreign_key_column_name.to_s + "="] = [ association, :_low_card_foreign_key= ]

          association.class_method_name_to_low_card_method_name_map.each do |desired_name, association_method_name|
            desired_name = desired_name.to_s
            @method_delegation_map[desired_name] = [ association, association_method_name ]
          end
        end

        remove_delegated_methods!(currently_delegated_methods - @method_delegation_map.keys)
        add_delegated_methods!(@method_delegation_map.keys - currently_delegated_methods)
      end

      private
      def associations
        @model_class._low_card_associations_manager.associations
      end

      def assocation(name)
        @model_class._low_card_associations_manager.maybe_low_card_association(name)
      end

      def remove_delegated_methods!(method_names)
        mod = @model_class._low_card_dynamic_methods_module

        method_names.each do |method_name|
          mod.module_eval("remove_method :#{method_name}")
        end
      end

      def add_delegated_methods!(method_names)
        mod = @model_class._low_card_dynamic_methods_module

        method_names.each do |delegated_method|
          mod.module_eval(%{
  def #{delegated_method}(*args)
    self.class._low_card_dynamic_method_manager.run_low_card_method(self, :#{delegated_method}, args)
  end})
        end
      end
    end
  end
end
