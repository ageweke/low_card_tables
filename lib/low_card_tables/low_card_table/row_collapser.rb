module LowCardTables
  module LowCardTable
    # The RowCollapser is an object that exists solely to contain the code required to collapse rows when someone
    # removes a column from a low-card table in a migration. It's not a particularly well-defined object and resulted
    # from an extraction from RowManager; however, it's still nicer to have this code in a separate object rather than
    # making the RowManager even bigger than it already is.
    #
    # What are we trying to accomplish here? Well, imagine you have this:
    #
    #     user_statuses
    #     id  deleted  donation_level  gender
    #      1   false    3              female
    #      2   false    5              female
    #      3   false    7              female
    #      4   false    3              male
    #      5   false    5              male
    #      6   false    7              male
    #
    # ...and now imagine we decide to remove the +deceased+ column. If we do nothing, we'll end up with this:
    #
    #     user_statuses
    #     id  deleted  gender
    #      1   false   female
    #      2   false   female
    #      3   false   female
    #      4   false   male
    #      5   false   male
    #      6   false   male
    #
    # ...but this violates the principle of low-card tables that they have only one row for each unique combination of
    # values. What we need to do is reduce it to this...
    #
    #     user_statuses
    #     id  deleted  gender
    #      1   false   female
    #      4   false   male
    #
    # ...and then update all columns in all tables that have a +user_status_id+ like so:
    #
    #     UPDATE users SET user_status_id = 1 WHERE user_status_id IN (2, 3)
    #     UPDATE users SET user_status_id = 4 WHERE user_status_id IN (5, 6)
    #
    # That's the job of this class. LowCardTables::HasLowCardTable::LowCardAssociation is responsible for updating the
    # referring tables themselves; however, this class is responsible for the fundamental operation.
    #
    # In this class, we often refer to the "collapse map"; in the above example, this would be:
    #
    #     #<UserStatus id: 1> => [ #<UserStatus id: 2>, #<UserStatus id: 3> ]
    #     #<UserStatus id: 4> => [ #<UserStatus id: 5>, #<UserStatus id: 6> ]
    #
    # The keys are the rows of the table that have been collapsed _to_; the values are arrays of rows that have been
    # collapsed _from_.
    class RowCollapser
      # Creates a new instance. +low_card_model+ is the ActiveRecord model class of the low-card table itself;
      # +low_card_options+ is the set of options passed to whatever migration method (e.g., +remove_column+) was
      # invoked to cause the need for a collapse. Options that we pay attention to are:
      #
      # [:low_card_collapse_rows] If present but +false+ or +nil+, then no row collapsing will happen due to the
      #                           migration command; you'll be left with an invalid low-card table with no unique
      #                           index, and will need to fix this problem yourself before you can use the table.
      # [:low_card_referrers] Adds one or more models as "referring models" that will have any references to this
      #                       model updated when the collapsing is done. Generally speaking, it should not be necessary
      #                       to do this -- this code is aggressive about eagerly loading all models, and ensuring that
      #                       any that refer to this table are used. But this is available in case you need it.
      # [:low_card_update_referring_models] If present but +false+ or +nil+, then row collapsing will occur as normal,
      #                                     but no referring columns will be updated. You'll thus have dangling foreign
      #                                     keys in any referring models; you'll have to update them yourself.
      def initialize(low_card_model, low_card_options)
        unless low_card_model.respond_to?(:is_low_card_table?) && low_card_model.is_low_card_table?
          raise ArgumentError, "You must supply a low-card AR model class, not: #{low_card_model.inspect}"
        end

        @low_card_model = low_card_model
        @low_card_options = low_card_options
      end

      # This should be called after any migration operation on the table that may have caused it to now have
      # duplicate rows. This method looks at the table, detects duplicate rows, picks out winners (and the
      # corresponding losers), and updates rows and referring rows, contingent upon the +low_card_options+ passed
      # in the constructor.
      #
      # Notably, you don't need to tell this method _what_ you did to the table; it simply looks at the current state
      # of the table and deals with duplicate rows. It also means this method is perfectly safe to call on a table that
      # has had no changes, or a table that has had migrations performed on it that don't result in duplicate rows;
      # it will simply see that there are no duplicate rows in the table, and do nothing.
      #
      # This method returns the "collapse map"; see the comment on this class overall for more information. This allows
      # you to do anything you want with the calculated collapse. Normally, you don't _have_ to do anything with it and
      # can ignore it, but it can also be useful if you pass <tt>:low_card_update_referring_models => false</tt> in
      # the +low_card_options+.
      def collapse!
        # :low_card_collapse_rows tells this method to do nothing at all.
        return if low_card_options.has_key?(:low_card_collapse_rows) && (! low_card_options[:low_card_collapse_rows])

        additional_referring_models = low_card_options[:low_card_referrers]

        # First, we build a map. The keys are Hashes representing each unique combination of attributes found for
        # the table; the value is an Array of all rows (model objects) for that key. (In a normal state, each value
        # would have exactly one element in the array; however, because we may just have migrated the table into a
        # state where we need to collapse the rows, this may not be true at the moment.)
        attributes_to_rows_map = { }
        low_card_model.all.sort_by(&:id).each do |row|
          attributes = value_attributes(row)

          attributes_to_rows_map[attributes] ||= [ ]
          attributes_to_rows_map[attributes] << row
        end

        return { } if (! attributes_to_rows_map.values.detect { |a| a.length > 1 })

        # Now we build the collapse_map, which is very similar to the attributes_to_rows_map, above. We pick the first
        # of the values to be the winner in each case, which, because we've sorted the rows by ID, should be the
        # duplicate row with the lowest ID -- this is as reasonable a way to pick winners as any.
        collapse_map = { }
        attributes_to_rows_map.each do |attributes, rows|
          if rows.length > 1
            winner = rows.shift
            losers = rows

            collapse_map[winner] = losers
          end
        end

        # Figure out which rows we need to delete; this is just all the losers.
        ids_to_delete = collapse_map.values.map { |row_array| row_array.map(&:id) }.flatten.sort
        low_card_model.delete_all([ "id IN (:ids)", { :ids => ids_to_delete } ])

        # Figure out what referring models we need to update.
        all_referring_models = low_card_model.low_card_referring_models | (additional_referring_models || [ ])

        # Run transactions on all of these, plus the low-card model as well.
        #
        # Why do we do this? Isn't just one transaction enough? Well, in default Rails configuration, yes, because all
        # models live on the same database. However, it's so common to use gems (for example, +db_charmer_) that allow
        # different models to live on different databases that we make sure to run transactions on all of them;
        # running nested transactions on the same database is harmless.
        transaction_models = all_referring_models + [ low_card_model ]

        unless low_card_options.has_key?(:low_card_update_referring_models) && (! low_card_options[:low_card_update_referring_models])
          transactions_on(transaction_models) do
            all_referring_models.each do |referring_model|
              referring_model._low_card_update_collapsed_rows(low_card_model, collapse_map)
            end
          end
        end

        # Return the collapse_map.
        collapse_map
      end

      private
      attr_reader :low_card_options, :low_card_model

      # Given a model object, extracts a Hash that maps each of the value-column names to the value this model object
      # has for that value column.
      def value_attributes(row)
        attributes = row.attributes
        out = { }
        low_card_model.low_card_value_column_names.each { |n| out[n] = attributes[n] }
        out
      end

      # Runs transactions on all of the specified models. Because of ActiveRecord's semantics for transactions (which
      # for almost all other use cases are excellent), this has to be a recursive call.
      def transactions_on(transaction_models, &block)
        if transaction_models.length == 0
          block.call
        else
          model = transaction_models.shift
          model.transaction { transactions_on(transaction_models, &block) }
        end
      end
    end
  end
end
