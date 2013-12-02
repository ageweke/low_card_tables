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

# This is the root 'require' file for +low_card_tables+. It loads a number of dependencies, and sets up some very
# basic infrastructure.

# The only thing that's actually present on the root LowCardTables module is cache-expiration settings -- you can say
# <tt>LowCardTables.low_card_cache_expiration ...</tt> to set the cache expiration for any table that has not explicitly
# had its own cache expiration defined.
module LowCardTables
  include LowCardTables::LowCardTable::CacheExpiration::HasCacheExpiration

  # By default, we use the ExponentialCacheExpirationPolicy with default settings.
  low_card_cache_expiration :exponential
end

# Include into ActiveRecord::Base two modules -- one allows you to declare +is_low_card_table+ or +has_low_card_table+,
# and the other makes sure that you don't define scopes statically. (See LowCardTables::ActiveRecord::Scoping for more
# information on why this is really bad.)
class ActiveRecord::Base
  include LowCardTables::ActiveRecord::Base
  include LowCardTables::ActiveRecord::Scoping
end

# ActiveRecord migration methods (e.g., #create_table, #remove_column, etc.) are actually defined on the connection
# classes used by ActiveRecord. Here, we make sure that we get a chance to patch any connection used in any migration
# properly, so that we can add our migration support to it. See LowCardTables::ActiveRecord::Migrations for more
# information.
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

# This patches in our support for queries (like #where) to all ActiveRecord::Relation objects, so that you can say
# things like <tt>User.where(:deleted => false)</tt> and it'll do exactly the right thing, automatically, even if
# +:deleted+ is actually an attribute on a low-card table associated with +User+.
class ActiveRecord::Relation
  include LowCardTables::ActiveRecord::Relation
end
