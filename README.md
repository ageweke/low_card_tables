# low_card_tables

Greatly improve scalability and maintainability of your database tables by breaking out columns containing few distinct values (e.g., booleans and other flags) into a separate table that's transparently referenced and used. Supports Rails 3.0.x, 3.1.x, 3.2.x, and 4.0.x, running on Ruby 1.8.7, 1.9.3, 2.0.0, and JRuby 1.7.4, with MySQL, PostgreSQL, and Sqlite. (And adding support for other databases is trivial!)

`low_card_tables` is short for "low-cardinality tables". Cardinality, when applied to a database column, is the measure of the number of distinct values that column can hold. This Gem is meant to be used for columns that hold few distinct values throughout the table &mdash; hence, they have low cardinality.

Current build status: ![Current Build Status](https://api.travis-ci.org/ageweke/low_card_tables.png?branch=master)

## What? Why?

Imagine you grow to, say, 25,000,000 users.

### Before:

    Table 'users' (25,000,000 rows)

    +--------------+-----------------------------------------------------------------+
    | first_name   | last_name        | deleted | deceased | gender | payment_status |
    +--------------+------------------+---------+----------+--------+----------------+
    | Jennifer     | Whitney          | 0       | 0        | f      | 1              |
    | Milton       | Zimmerman        | 1       | 0        | m      | 0              |
    | Emily        | Friedman         | 0       | 0        | f      | 1              |
    | John         | Wong             | 0       | 0        | m      | 3              |
    |      ......................................................................    |

* You're spending 100 _megabytes_ of database buffer cache just caching these four status flags. (MySQL and PostgreSQL both use a full byte at minimum for any column value.)
* Do you want to add, say, a `donated` column to the table? With MySQL, be prepared to take your site down for hours as it copies all 25,000,000 rows to a new table, just to add the column.
* Is one of these columns no longer used? Ditto &mdash; be prepared to take your site down if you want to remove that column.
* Indexes on these columns are probably either useless or rarely used. If you're using MySQL, since it can only effectively use one index per query, the only way an index on those columns will ever be used is if it's a composite index on whatever other columns you're querying on that happens to also include exactly the flags you're constraining on, in the right order. (That's going to be really rare.)
* Are these columns not entirely independent? (For example, you may always mark someone as `deleted` if they are `deceased`.) Better hope your validations work well, because the database isn't going to enforce that.
* You also have a less-readable database, because `payment_status` &mdash; which, presumably, is conceptually an `enum` &mdash; is represented using various integers that you just have to remember (or look at the code every time). (If I had a nickel for every time I went around selecting user names to try to figure out which gender is `0` and which gender is `1`...)

You _actually_ may have only, say, 27 combinations of the above values. This is small enough that you can represent it using a single byte (or even just 5 bits). Why are we going through all of the above pain?

### After:

	Table 'users' (25,000,000 rows)
	
	+--------------+-----------------------------------+
    | first_name   | last_name        | user_status_id |
    +--------------+------------------+----------------+
    | Jennifer     | Whitney          | 2              |
    | Milton       | Zimmerman        | 7              |
    | Emily        | Friedman         | 2              |
    | John         | Wong             | 4              |
    |      ........................................    |
    
    Table 'user_statuses' (27 rows)
    
    +--------------------------+----------+--------+----------------+
    | user_status_id | deleted | deceased | gender | payment_status |
    +----------------+---------+----------+--------+----------------+
    | 1              | 0       | 0        | male   | none           |
    | 2              | 0       | 0        | female | one-time       |
    | 3              | 0       | 0        | female | none           |
    | 4              | 0       | 0        | male   | annual         |
    | 5              | 1       | 0        | female | none           |
    | 6              | 0       | 1        | male   | monthly        |
    | 7              | 1       | 0        | male   | none           |
    |       ..............................................          |

* You just got 75 megabytes of precious database buffer cache back.
* Wait, but now you have to join to `user_statuses`, right? __No__, you don’t &mdash; `low_card_tables` caches that entire (small!) table in memory, refreshing it automatically, so that SELECT, INSERT, UPDATE, and DELETE on `users` require, on average, zero queries to `user_statuses`.
* Adding enum-style columns is now instantaneous, because you're migrating a table with 27 rows, not 25 million.
* Removing these columns is now instantaneous, too.
* Adding an index on `user_status_id`, or adding it to another, compound index, will allow you to efficiently search all those columns at once. (This is especially useful with PostgreSQL's partial-index feature.)
* You can now use strings that are as long and verbose as needed for your columns &mdash; because you're only storing them a few dozen times, not 25,000,000.
* Because `low_card_tables` generates new rows lazily, on demand, if your columns aren't entirely independent, you'll only end up with rows for the combinations that actually exist. (And if you screw up, it's immediately obvious in the low-card table &mdash; and it's trivial to select the offending rows out of the parent table.)

### OK &mdash; but now everybody has to know about this new format, right?

Nope. All you have to do is this:

	# in Gemfile
	gem 'low_card_tables'
	
	# app/models/user_status.rb
	class UserStatus < ActiveRecord::Base
	  is_low_card_table
	end
	
	# app/models/user.rb
	class User < ActiveRecord::Base
	  has_low_card_table :status
	end

...and then the following all works exactly as you'd expect:

	# Basic usage
    my_user.deleted?          # => true, false
    my_user.gender            # => male, female, other, ...
    my_user.deleted = true    # changes the user_status_id on save automatically
    
    # Querying
    # (these methods automatically generate queries like WHERE user_status_id IN (2, 4, ...))
    User.where(:deleted => true)                           # simple queries
    User.where(:deleted => true).where(:deceased => true)  # chained queries
    
    # Explicit access (if you want it, it's there)
    my_user.user_status                  # => UserStatus model
    my_user.user_status.deleted?
    my_user.user_status.deleted = true
    my_user.user_status_id               # => 3
    my_user.user_status_id = 17
    
    # Class methods
    class User < ActiveRecord::Base
      # Write validations on the owning table
      validates :gender, :inclusion => { :in => %w{male female other} }
    
      # default scopes
      default_scope { where(:deleted => false) }
      
      # named scopes
      scope :undead { where(:deleted => false, :deceased => true) }
      
      # class-method scopes
      def self.unpaid_men
        where(:gender => 'male').where(:payment_status => 'none')
      end
    end
    
    class UserStatus < ActiveRecord::Base
      # ...or write validations on the low-card table
      validates :donation_level, :numericality => { :greater_than_or_equal_to => 0 }
    end
    
    # Migrations
    
    # default values
    add_column :user_statuses, :donated, :boolean, :default => false, :null => false
    
    # removing columns -- this even auto-compacts the table and cleans up references!
    remove_column :user_statuses, :payment_status

Other things that are supported:

* __Customization__ &mdash; like a good Rails citizen, there are handy defaults for all the names involved, but `:foreign_key` and `:class` let you declare the association however you want. A `:delegate` option lets you control which methods are delegated, and a `:prefix` option lets you prefix them with the association name, or any string you want.
* __Bulk access__ &mdash; fetch rows or IDs of rows in the low-card table, or fetch-or-create them, in a constant number of queries.
* __Out-of-band support__ &mdash; it is safe to store `user_status_id` values in memcached, Redis, or any other tool; the internal cache will behave appropriately at all times.
* __Overriding__ &mdash; you can override, say, `User#deleted` or `User#deceased=`, call `super`, and it will all work exactly as it should.
* __Multiple Relationships__ &mdash; a table can refer to as many low-card tables as it wants (_e.g._, you can have `user_status_id`, `user_payment_status_id`, `user_profile_status_id`, or whatever); many tables can refer to a single low-card table if you have flags shared among many tables; and one table can even have multiple references to the same low-card table (_e.g._, `user_status_id`, `previous_user_status_id`, etc.).

# Installing low_card_tables

	# Gemfile
	gem 'low_card_tables'

# Getting Started

We'll first discuss adding entirely new tables, and then talk about how you can migrate existing tables.

## Creating the Database Structure

Create the table structure you need in your database:

	class MyMigration < ActiveRecord::Migration
	  def up
	    create_table :users do |t|
	      t.string :first_name, :null => false
	      t.string :last_name, :null => false
	      ...
	      t.integer :user_status_id, :null => false, :limit => 2
	      ...
	    end
	    
	    create_table :user_statuses, :low_card => true do |t|
	      t.boolean :deleted, :null => false
	      t.boolean :deceased, :null => false
	      t.string :gender, :null => false, :limit => 20
	      t.string :payment_status, :null => false, :limit => 30
	    end
	  end
	end

In the migration, we simply create the table structure in the most straightforward way possible, with one exception: we add `:low_card => true` to the `create_table` command on the low-card table itself. The only thing this does is that, once the table has been created, it automatically adds a unique index across all columns in the table &mdash; this is very important, since it allows the database to enforce the key property of the low-card system: that there is exactly one row for each unique combination of values in the low-card columns.

## Creating the Models

Create the models:

	# app/models/user_status.rb
	class UserStatus < ActiveRecord::Base
	  is_low_card_table
	end
	
	# app/models/user.rb
	class User < ActiveRecord::Base
	  has_low_card_table :status
	end

And boom, you're done. Any columns present on `user_statuses` will appear as virtual columns on `User` &mdash; for reading and writing, for queries, for scopes, for validations, and so on.

# Migrating Existing Tables

Say we have a `users` table with 25,000,000 rows as above, and we want to migrate it to a low-card structure. This is not a trivial undertaking, although the benefits when you're done will be huge. This is the path I would take:

1. Add, and run, a migration that creates the `user_statuses` table as above. This will obviously be basically instantaneous.
1. Add, and run, a migration that adds a `user_status_id` column to `users`. This will be painfully bad (if you're using MySQL) or slow but not painful (if you're using PostgreSQL) &mdash; but you only have to do this once, ever, and there's no way around it.
1. Define the models as above, but, in the `User` model, say `has_low_card_table :status, :delegate => false`. The low-card system will generally not overwrite real attributes (your `users.deleted`, `users.gender`, etc. columns) with its pseudo-attributes anyway, but this forces it not to, to be extra-safe.
1. In your `User` model, override `deleted=`, `gender=`, and so on to set both the old and the new data &mdash; _e.g._, `def deleted=(x); self[:deleted] = x; self.status.deleted = x; end`. This will keep your data in sync while the migration process is ongoing. Deploy this code.
1. (The simple version) Write a script that iterates through your users, and, for each one, does something like: `u.status.deleted = u.deleted; u.status.deceased = u.deceased; u.status.gender = u.gender; u.status.payment_status = u.payment_status; u.save!`. This will copy over the existing values to the new low-card status values.
1. (The complex version) Do the same, but in bulk: load in a thousand (or 10,000) `User` models at once &mdash; or even just Hashes, using `User.connection.select_all`, because that's much faster than using ActiveRecord models. Extract from all of them a Hash containing these four attributes, and `uniq` that list. Now, call `UserStatus.low_card_find_or_create_ids_for`, and pass in that array of `Hash`es. You'll get back a `Hash` mapping each of those `Hash`es to the correct low-card status ID (which will be created for you). Now, use the `activerecord-import` gem (which you now have, since it's a dependency of `low_card_tables` anyway) to update just that one column, in bulk, using its `:on_duplicate_key_update` functionality. This is considerably more complex than the previous step, but is probably several orders of magnitude faster.
1. Once this is complete, change your overrides of `User.deleted=` (and so on) to only change the new data &mdash; _e.g._, `def deleted=(x); self.status.deleted = x; end`. You still need these present because `low_card_tables` will not override real columns on the `User` model with its own pseudo-columns.
1. Run another migration that drops all the old columns. This will also be painful.
1. Finally, remove your overrides of `deleted=`, and so on. 

While this transformation process will be difficult, once you're done, adding, removing, and changing further low-card columns becomes trivial.

A special bonus note: if you're using MySQL, which still (in 2013?!?) can't add columns without locking tables for hours or days (because it copies the entire damn table over), it can be useful to add several reserved columns when you create a table, for future use. Each low-cardinality ID column can refer to a low-card table that may have a thousand rows or more, so a single low-card ID column can represent as many as 10-12 boolean attributes.