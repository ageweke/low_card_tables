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

        # We call this here so that if things are configured incorrectly, you'll get an exception at the moment you
        # try to associate the tables, rather than at runtime when you try to actually use them. Blowing up early is
        # good. :)
        foreign_key_column_name

        low_card_class._low_card_referred_to_by(model_class)
      end

      # Returns a Hash that maps the names of methods that should be added to the referring class to the names of
      # methods they should invoke on the low-card class. This takes into account both the +:delegate+ option (via
      # its internal call to #delegated_method_names) and the +:prefix+ option.
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

      # Returns an Array of names of methods on the low-card table that should be delegated to. This may be different
      # than the names of methods on the referring class, because of the :prefix option.
      def delegated_method_names
        value_column_names = low_card_class.low_card_value_column_names.map(&:to_s)

        if options.has_key?(:delegate) && (! options[:delegate])
          [ ]
        elsif options[:delegate].kind_of?(Array) || options[:delegate].kind_of?(String) || options[:delegate].kind_of?(Symbol)
          out = Array(options[:delegate]).map(&:to_s)
          extra = out - value_column_names

          if extra.length > 0
            raise ArgumentError, "You told us to delegate the following methods to low-card class #{low_card_class}, but that model doesn't have these columns: #{extra.join(", ")}; it has these columns: #{value_column_names.join(", ")}"
          end
          out
        elsif options[:delegate] && options[:delegate].kind_of?(Hash) && options[:delegate].keys.map(&:to_s) == %w{except}
          excluded = (options[:delegate][:except] || options[:delegate]['except']).map(&:to_s)
          extra = excluded - value_column_names

          if extra.length > 0
            raise ArgumentError, "You told us to delegate all but the following methods to low-card class #{low_card_class}, but that model doesn't have these columns: #{extra.join(", ")}; it has these columns: #{value_column_names.join(", ")}"
          end

          value_column_names - excluded
        elsif (! options.has_key?(:delegate)) || options[:delegate] == true
          value_column_names
        else
          raise ArgumentError, "Invalid value for :delegate: #{options[:delegate].inspect}"
        end
      end

      # Given an instance of the referring class, returns an instance of the low-card class that is configured correctly
      # for the current value of the referring column.
      def create_low_card_object_for(model_instance)
        ensure_correct_class!(model_instance)

        id = get_id_from_model(model_instance)

        out = nil
        if id
          template = low_card_class.low_card_row_for_id(id)
          out = template.dup
          out.id = nil
          out
        else
          out = low_card_class.new
        end

        out
      end

      # Computes the correct name of the foreign-key column based on the options passed in.
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
to have a column named that at all. Did you misspell it? Or perhaps something else is wrong?

The model class has these columns: #{model_class.columns.map(&:name).sort.join(", ")}}
          end

          out
        end
      end

      # When a low-card table has a column removed, it will typically have duplicate rows; these duplicate rows are
      # then deleted. But then referring tables need to be updated. This method gets called at that point, with a map
      # of <winner row> => <array of loser rows>, and the +collapsing_update_scheme+ declared by this referring
      # model class. It is responsible for handling whatever collapsing update scheme has been declared properly.
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

      # Updates the foreign key for this association on the given model instance. This is called by
      # LowCardTables::HasLowCardTable::Base#low_card_update_foreign_keys!, which is primarily invoked by a
      # +:before_save+ filter and alternatively can be invoked manually.
      def update_foreign_key!(model_instance)
        hash = { }

        low_card_object = model_instance._low_card_objects_manager.object_for(self)

        low_card_class.low_card_value_column_names.each do |value_column_name|
          hash[value_column_name] = low_card_object[value_column_name]
        end

        new_id = low_card_class.low_card_find_or_create_ids_for(hash)

        unless get_id_from_model(model_instance) == new_id
          set_id_on_model(model_instance, new_id)
        end
      end

      # Figures out what the low-card class this association should use is; this uses convention, with some overrides.
      #
      # By default, for a class User that <tt>has_low_card_table :status</tt>, it looks for a class UserStatus. This
      # is intentionally different from Rails' normal conventions, where it would simply look for a class Status. This
      # is because low-card tables are almost always unique to their owning table -- _i.e._, the case where multiple
      # tables say +has_low_card_table+ to the same low-card table is very rare. (This is just because having multiple
      # tables that have -- <em>and always will have</em> -- the same set of low-card attributes is also quite rare.)
      # Hence, we use a little more default specificity in the naming.
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

      # This is the method that actually updates rows in the referring table when a column is removed from a low-card
      # table (and hence IDs are collapsed). It's called repeatedly, in a loop, from #update_collapsed_rows. One call
      # of this method updates one 'chunk' of rows, where the row-chunk size is whatever was specified by a call to
      # LowCardTables::HasLowCardTable::Base#low_card_value_collapsing_update_scheme. When it's done, it either returns
      # +nil+, if there are no more rows to update, or the ID of the next row that should be updated, if there are.
      #
      # +starting_id+ is the primary-key value that this chunk should start at. (We always update rows in ascending
      # primary-key order, starting with the smallest primary key.) +row_chunk_size+ is the number of rows that should
      # be updated. +collapse_map+ contains only objects of the low-card class, mapping 'winners' to arrays of 'losers'.
      # (That is, we must update all rows containing any ID found in an array of values to the corresponding ID found
      # in the key.)
      #
      # Note that this method goes out of its way to not have a common bug: if you simply update rows from
      # +starting_id+ to <tt>starting_id + row_chunk_size</tt>, then large gaps in the ID space will destroy performance
      # completely. Rather than ever doing math on the primary key, we just tell the database to order rows in primary-
      # key order and do chunks of the appropriate size.
      def update_collapsed_rows_batch(starting_id, row_chunk_size, collapse_map)
        starting_at_starting_id = model_class.where("#{model_class.primary_key} >= :starting_id", :starting_id => starting_id)

        # Databases will return no rows if asked for an offset past the end of the table.
        one_past_ending_row = starting_at_starting_id.order("#{model_class.primary_key} ASC").offset(row_chunk_size).first
        one_past_ending_id = one_past_ending_row.id if one_past_ending_row

        base_scope = starting_at_starting_id
        if one_past_ending_id
          base_scope = base_scope.where("#{model_class.primary_key} < :one_past_ending_id", :one_past_ending_id => one_past_ending_id)
        end

        # Do a series of updates -- one per entry in the +collapse_map+.
        collapse_map.each do |collapse_to, collapse_from_array|
          conditional = base_scope.where([ "#{foreign_key_column_name} IN (:collapse_from)", { :collapse_from => collapse_from_array.map(&:id) } ])
          conditional.update_all([ "#{foreign_key_column_name} = :collapse_to", { :collapse_to => collapse_to.id } ])
        end

        one_past_ending_id
      end

      # Fetches the ID from the referring model, by simply grabbing the value of its foreign-key column.
      def get_id_from_model(model_instance)
        model_instance[foreign_key_column_name]
      end

      # Sets the ID on the referring model, by setting the value of its foreign-key column.
      def set_id_on_model(model_instance, new_id)
        model_instance[foreign_key_column_name] = new_id
      end

      # Ensures that the given +model_instance+ is an instance of the referring model class.
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
