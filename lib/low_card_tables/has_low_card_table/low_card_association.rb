module LowCardTables
  module HasLowCardTable
    # A LowCardAssociation represents a single association between a referring model class and a referred-to low-card
    # model class. Note that this represents an association between _classes_, not between _objects_ -- that is, there
    # is one instance of this class for a relationship from one referring class to one referred-to class, no matter
    # how many model objects are instantiated.
    class LowCardAssociation
      # Returns the name of the association -- this will always have been the first arguent to +has_low_card_table+.
      attr_reader :association_name

      # Creates a new instance. model_class is the Class (which must inherit from ActiveRecord::Base) that is the
      # referring model; association_name is the name of the association. options can contain any of the options
      # accepted by LowCardTables::HasLowCardTables::Base#has_low_card_table.
      def initialize(model_class, association_name, options)
        @model_class = model_class
        @association_name = association_name.to_s
        @options = options.with_indifferent_access

        # call a few methods that will raise errors if things are configured incorrectly;
        # we call them here so that you get those errors immediately, at startup, instead of
        # at some undetermined later point
        foreign_key_column_name

        low_card_class._low_card_referred_to_by(model_class)
      end

      def class_method_name_to_low_card_method_name_map
        return { } if options.has_key?(:delegate) && (! options[:delegate])

        out = { }

        delegated_method_names.each do |column_name|
          desired_method_name = case options[:prefix]
          when true then "#{association_name}_#{column_name}"
          when String, Symbol then "#{options[:prefix]}_#{column_name}"
          when nil then column_name
          else raise ArgumentError, "Invalid :prefix option: #{options[:prefix].inspect}"
          end

          out[desired_method_name] = column_name
          out[desired_method_name + "="] = column_name + "="
        end

        out
      end

      def model_constraints_for_query(query_constraints)
        low_card_class.low_card_ids_matching(query_constraints)
      end

      def delegated_method_names
        value_column_names = low_card_class._low_card_value_column_names.map(&:to_s)

        if options.has_key?(:delegate) && (! options[:delegate])
          [ ]
        elsif options[:delegate].kind_of?(Array)
          out = options[:delegate].map(&:to_s)
          extra = out - value_column_names

          if extra.length > 0
            raise ArgumentError, "You told us to delegate the following methods to low-card class #{low_card_class}, but that model doesn't have these columns: #{extra.join(", ")}; it has these columns: #{low_card_class._low_card_value_column_names.join(", ")}"
          end
          out
        elsif options[:delegate] && options[:delegate].kind_of?(Hash) && options[:delegate].keys.map(&:to_s) == %w{except}
          excluded = (options[:delegate][:except] || options[:delegate]['except']).map(&:to_s)
          extra = excluded - value_column_names

          if extra.length > 0
            raise ArgumentError, "You told us to delegate all but the following methods to low-card class #{low_card_class}, but that model doesn't have these columns: #{extra.join(", ")}; it has these columns: #{low_card_class._low_card_value_column_names.join(", ")}"
          end

          value_column_names - excluded
        else
          low_card_class._low_card_value_column_names
        end
      end

      def create_low_card_object_for(model_instance)
        ensure_correct_class!(model_instance)

        id = get_id_from_model(model_instance)

        out = nil
        if id
          template = low_card_class.low_card_row_for_id(get_id_from_model(model_instance))
          out = template.dup
          out.id = nil
          out
        else
          out = low_card_class.new
        end

        out
      end

      def foreign_key_column_name
        @foreign_key_column_name ||= begin
          out = options[:foreign_key]

          unless out
            out = "#{@model_class.name.underscore}_#{association_name}"
            out = $1 if out =~ %r{/[^/]+$}i
            out = out + "_id"
          end

          out = out.to_s if out.kind_of?(Symbol)

          column = model_class.columns.detect { |c| c.name.strip.downcase == out.strip.downcase }
          unless column
            raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name}, and we
have a foreign-key column name of #{out.inspect}, but #{model_class} doesn't seem
to have a column named that at all. Did you misspell it? Or perhaps something else is wrong?}
          end

          out
        end
      end

      def update_collapsed_rows(collapse_map, collapsing_update_scheme)
        if collapsing_update_scheme.respond_to?(:call)
          collapsing_update_scheme.call(collapse_map)
        elsif collapsing_update_scheme == :none
          # nothing to do
        else
          row_chunk_size = collapsing_update_scheme
          current_id = @model_class.order("#{@model_class.primary_key} ASC").first.id

          while true
            current_id = update_collapsed_rows_batch(current_id, row_chunk_size, collapse_map)
            break if (! current_id)
          end
        end
      end

      def update_value_before_save!(model_instance)
        hash = { }

        low_card_object = model_instance._low_card_objects_manager.object_for(self)

        low_card_class._low_card_value_column_names.each do |value_column_name|
          hash[value_column_name] = low_card_object[value_column_name]
        end

        new_id = low_card_class.low_card_find_or_create_ids_for(hash)

        unless get_id_from_model(model_instance) == new_id
          set_id_on_model(model_instance, new_id)
        end
      end

      def low_card_column_information_reset!
        sync_installed_methods!
      end

      def low_card_class
        @low_card_class ||= begin
          # e.g., class User has_low_card_table :status => UserStatus
          out = options[:class] || "#{model_class.name.underscore.singularize}_#{association_name}"

          out = out.to_s if out.kind_of?(Symbol)
          out = out.camelize if out.kind_of?(String)

          if out.kind_of?(String)
            begin
              out = out.constantize
            rescue NameError => ne
              raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name}, and we have a
:class of #{out.inspect}, but, when we tried to load that class (via #constantize),
we got a NameError. Perhaps you misspelled it, or something else is wrong?

NameError: (#{ne.class.name}): #{ne.message}}
            end
          end

          unless out.kind_of?(Class)
            raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name} with a
:class of #{out.inspect}, but that isn't a String or Symbol that represents a class,
or a valid Class object itself.}
          end

          unless out.respond_to?(:is_low_card_table?) && out.is_low_card_table?
            raise ArgumentError, %{You said that #{model_class} has_low_card_table :#{association_name},
and we have class #{out} for that low-card table (which is a Class), but it
either isn't an ActiveRecord model or, if so, it doesn't think it is a low-card
table itself (#is_low_card_table? returns false).

Perhaps you need to declare 'is_low_card_table' on that class?}
          end

          out
        end
      end

      private
      attr_reader :options, :model_class

      def sync_installed_methods!
        model_class._low_card_dynamic_method_manager.sync_methods!
      end

      def update_collapsed_rows_batch(starting_id, row_chunk_size, collapse_map)
        starting_at_starting_id = model_class.where("#{model_class.primary_key} >= :starting_id", :starting_id => starting_id)

        one_past_ending_row = starting_at_starting_id.order("#{model_class.primary_key} ASC").offset(row_chunk_size).first
        one_past_ending_id = one_past_ending_row.id if one_past_ending_row

        base_scope = starting_at_starting_id
        base_scope = base_scope.where("#{model_class.primary_key} < :one_past_ending_id", :one_past_ending_id => one_past_ending_id) if one_past_ending_id

        collapse_map.each do |collapse_to, collapse_from_array|
          conditional = base_scope.where([ "#{foreign_key_column_name} IN (:collapse_from)", { :collapse_from => collapse_from_array.map(&:id) } ])
          conditional.update_all([ "#{foreign_key_column_name} = :collapse_to", { :collapse_to => collapse_to.id } ])
        end

        one_past_ending_id
      end

      def get_id_from_model(model_instance)
        model_instance[foreign_key_column_name]
      end

      def set_id_on_model(model_instance, new_id)
        model_instance[foreign_key_column_name] = new_id
      end

      def ensure_correct_class!(model_instance)
        unless model_instance.kind_of?(model_class)
          raise %{Whoa! The LowCardAssociation '#{association_name}' for class #{model_class} somehow
was passed a model of class #{model_instance.class} (model: #{model_instance}),
which is not of the correct class.}
        end
      end
    end
  end
end
