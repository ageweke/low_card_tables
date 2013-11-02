require 'active_record'
require 'active_support'
require 'active_record/migration'
require "low_card_tables/version"
require "low_card_tables/version_support"
require 'low_card_tables/active_record/base'
require 'low_card_tables/active_record/migrations'
require 'low_card_tables/active_record/relation'
require 'low_card_tables/active_record/scoping'
require 'low_card_tables/low_card_table/cache_expiration/has_cache_expiration'

module LowCardTables
  include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

  low_card_cache_expiration :exponential
end

class ActiveRecord::Base
  include LowCardTables::ActiveRecord::Base
  include LowCardTables::ActiveRecord::Scoping
end

class ActiveRecord::Migration
  if LowCardTables::VersionSupport.migrate_is_a_class_method?
    class << self
      def migrate_with_low_card_connection_patching(*args, &block)
        _low_card_patch_connection_class_if_necessary(connection.class)
        migrate_without_low_card_connection_patching(*args, &block)
      end

      alias_method_chain :migrate, :low_card_connection_patching
    end
  else
    def migrate_with_low_card_connection_patching(*args, &block)
      self.class._low_card_patch_connection_class_if_necessary(connection.class)
      migrate_without_low_card_connection_patching(*args, &block)
    end

    alias_method_chain :migrate, :low_card_connection_patching
  end

  class << self
    def _low_card_patch_connection_class_if_necessary(connection_class)
      @_low_card_patched_connection_classes = { }
      @_low_card_patched_connection_classes[connection_class] ||= begin
        connection_class.send(:include, ::LowCardTables::ActiveRecord::Migrations)
        true
      end
    end
  end
end

class ActiveRecord::Relation
  include LowCardTables::ActiveRecord::Relation
end
