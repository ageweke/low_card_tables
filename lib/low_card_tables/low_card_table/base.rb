require 'active_support/concern'
require 'low_card_tables/low_card_table/cache_expiration/has_cache_expiration'
require 'low_card_tables/low_card_table/row_manager'

module LowCardTables
  module LowCardTable
    # LowCardTables::LowCardTable::Base is the module that's included into any ActiveRecord model that you declare
    # +is_low_card_table+ on. As such, it defines the API that's available on low-card tables. (The standard
    # ActiveRecord API does, of course, still remain available, so you can also use that if you want.)
    #
    # Be careful of the distinction between the ClassMethods and instance methods here. ClassMethods are available on
    # the low-card table as a whole; instance methods apply, of course, to each row individually.
    module Base
      extend ActiveSupport::Concern

      # All low-card tables can have their cache-expiration policy set individually.
      include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

      # Set up cache-policy inheritance -- see HasCacheExpiration for more details.
      included do
        low_card_cache_policy_inherits_from ::LowCardTables
        self.inheritance_column = '_sti_on_low_card_tables_should_never_be_used'
      end

      # This method is a critical entry point from the rest of the low-card system. For example, given our usual
      # User/UserStatus example -- when you save a User object, the low-card system grabs the associated UserStatus
      # object and creates a hash, mapping all of the columns in UserStatus to their corresponding values. Next, it
      # iterates through its in-memory cache, using this method to determine which of the rows in the cache matches
      # the hash it extracted -- and, when it finds one, that's the row it uses to get the low-card ID to assign
      # in the associated table.
      #
      # *IMPORTANT*: this is not the _only_ context in which this method is used, but merely one example.
      #
      # It's possible to override this method to alter behavior; for example, you could use this to translate symbols
      # to integers, pin values, or otherwise transform data. But be extremely careful when you do this, as you're
      # playing with a very low-level part of the low-card system.
      #
      # Note that the hashes supplied can be partial or complete; that is, they may specify any subset of the values
      # in this table, or all of them. This method must work accordingly -- if the hashes are partial, then, if this
      # row's values for the keys that are specified match, then it should return true.
      #
      # This is the highest-level, most 'bulk' method -- it asks whether this row matches _any_ of the hashes in the
      # supplied array.
      def _low_card_row_matches_any_hash?(hashes)
        hashes.detect { |hash| _low_card_row_matches_hash?(hash) }
      end

      # This is called by #_low_card_row_matches_any_hash?, in a loop; it asks whether this row matches the hash
      # provided. See #_low_card_row_matches_any_hash? for more details. You can override this method instead of that
      # one, if its semantics work better for your purposes, since its behavior will affect that of
      # #_low_card_row_matches_any_hash?.
      def _low_card_row_matches_hash?(hash)
        hash.keys.all? { |key| _low_card_column_matches?(key, hash[key]) }
      end

      # This is called by _low_card_row_matches_hash?, in a loop; it asks whether the given column (+key+) matches
      # the given value (+value+). See #_low_card_row_matches_any_hash? for more details. You can override this method
      # instead of #_low_card_row_matches_any_hash? or #_low_card_row_matches_hash?, if its semantics work better for
      # your purposes, since its behavior will affect those methods as well.
      def _low_card_column_matches?(key, value)
        my_value = self[key.to_s]

        if value.kind_of?(Array)
          if my_value && my_value.kind_of?(Symbol)
            my_value = my_value.to_s
          end

          value = value.map { |m| if m.kind_of?(Symbol) then m.to_s else m end }
          value.include?(my_value)
        else
          value_sym = value.kind_of?(Symbol)
          my_value_sym = my_value.kind_of?(Symbol)

          if (value_sym != my_value_sym) && value && my_value
            my_value.to_s.eql?(value.to_s)
          else
            my_value.eql?(value)
          end
        end
      end

      # This method is called from methods like #low_card_rows_matching, when passed a block -- its job is simply to
      # see if this row is matched by the given block. It's hard to imagine a different implementation than this one,
      # but it's here in case you want to override it.
      def _low_card_row_matches_block?(block)
        block.call(self)
      end

      module ClassMethods
        # Declares that this is a low-card table. This should only ever be used on tables that are,
        # in fact, low-card tables.
        #
        # options can contain:
        #
        # [:exclude_column_names] Excludes the specified Array of column names from being treated
        #                         as low-card columns; this happens by default to created_at and
        #                         updated_at. These columns will not be touched by the low-card
        #                         code, meaning they have to be nullable or have defaults.
        # [:max_row_count] The low-card system has a check built in to start raising errors if you
        #                  appear to be storing data in a low-card table that is, in fact, not actually
        #                  of low cardinality. The effect that doing this has is to explode the number
        #                  of rows in the low-card table, so the check simply tests the total number
        #                  of rows in the table. This defaults to 5,000
        #                  (in LowCardTables::LowCardTable::Cache::DEFAULT_MAX_ROW_COUNT). If you really
        #                  do have a valid low-card table with more than this number of rows, you can
        #                  override that limit here.
        def is_low_card_table(options = { })
          self.low_card_options = options
          _low_card_disable_save_when_needed!
        end

        # See LowCardTables::HasLowCardTable::LowCardObjectsManager for more details. In short, you should never be
        # saving low-card objects directly; you should rather let the low-card Gem create such rows for you
        # automatically, based on the attributes you assign to the model.
        #
        # This method is invoked only once, when #is_low_card_table is called.
        def _low_card_disable_save_when_needed!
          send(:define_method, :save_low_card_row!) do |*args|
            begin
              @_low_card_saves_allowed = true
              save!(*args)
            ensure
              @_low_card_saves_allowed = false
            end
          end

          send(:define_method, :save_low_card_row) do |*args|
            begin
              @_low_card_saves_allowed = true
              save(*args)
            ensure
              @_low_card_saves_allowed = false
            end
          end

          %w{save save!}.each do |method_name|
            send(:define_method, method_name) do |*args|
              if @_low_card_saves_allowed
                super(*args)
              else
                raise LowCardTables::Errors::LowCardCannotSaveAssociatedLowCardObjectsError, %{You just tried to save a model that represents a row in a low-card table.
You can't do this, because the entire low-card system relies on the fact that low-card rows
are immutable once created. Changing this row would therefore change the logical state of
many, many rows that are associated with this one, and that is almost certainly not what
you want.

Instead, simply modify the low-card attributes directly -- typically on the associated object
(e.g., my_user.deleted = true), or on the low-card object (my_user.status.deleted = true),
and then save the associated object instead (my_user.save!). This will trigger the low-card
system to recompute which low-card row the object should be associated with, and update it
as needed, which is almost certainly what you actually want.

If you are absolutely certain you know what you're doing, you can call #save_low_card_row!
on this object, and it will save, but make sure you understand ALL the implications first.}
              end
            end
          end
        end

        # Is this a low-card table? Since this module has been included into the class in question (which happens via
        # #is_low_card_table), then the answer is always, 'yes'.
        def is_low_card_table?
          true
        end

        # This is a method provided by ActiveRecord::Base. When the set of columns on a low-card table has changed, we
        # need to tell the row manager, so that it can flush its caches.
        def reset_column_information
          out = super
          _low_card_row_manager.column_information_reset!
          out
        end

        # This returns the set of low-card options specified for this class in #is_low_card_table.
        def low_card_options
          @_low_card_options ||= { }
        end

        # This sets the set of low-card options.
        def low_card_options=(options)
          @_low_card_options = options
        end

        # Returns the associated LowCardTables::LowCardTable::RowManager object for this class, which is where an awful
        # lot of the real work happens.
        def _low_card_row_manager
          @_low_card_row_manager ||= LowCardTables::LowCardTable::RowManager.new(self)
        end

        # All of these methods get delegated to the LowCardRowManager, which does most of the actual work. We prefix
        # them all with +low_card_+ in order to ensure that we can't possibly collide with methods provided by other
        # Gems or by client code, since many of the names are pretty generic (e.g., +all_rows+).
        [ :all_rows, :row_for_id, :rows_for_ids, :rows_matching, :ids_matching, :find_ids_for, :find_or_create_ids_for,
          :find_rows_for, :find_or_create_rows_for, :flush_cache!, :referring_models, :value_column_names, :referred_to_by,
          :collapse_rows_and_update_referrers!, :ensure_has_unique_index!, :remove_unique_index! ].each do |delegated_method_name|
          define_method("low_card_#{delegated_method_name}") do |*args|
            _low_card_row_manager.send(delegated_method_name, *args)
          end
        end
      end
    end
  end
end
