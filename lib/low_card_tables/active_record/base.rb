require 'active_record'
require 'active_support/concern'
require 'low_card_tables/low_card_table/base'
require 'low_card_tables/has_low_card_table/base'

module LowCardTables
  module ActiveRecord
    module Base
      extend ActiveSupport::Concern
      include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

      module ClassMethods
        def is_low_card_table(options = { })
          include LowCardTables::LowCardTable::Base
          self.low_card_options = options
          _low_card_disable_save_when_needed!
        end

        def is_low_card_table?
          false
        end

        def has_low_card_table(*args)
          unless @_low_card_has_low_card_table_included
            include LowCardTables::HasLowCardTable::Base
            @_low_card_has_low_card_table_included = true
          end

          has_low_card_table(*args)
        end

        def _low_card_disable_save_when_needed!
          send(:define_method, :save_low_card_row!) do |*args|
            begin
              @_low_card_saves_allowed = true
              save!(*args)
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
      end
    end
  end
end
