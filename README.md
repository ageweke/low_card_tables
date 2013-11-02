# low_card_tables

Greatly improve scalability and maintainability of your database tables by breaking out columns containing few distinct values (e.g., booleans and other flags) into a separate table that's transparently referenced and used. Supports Rails 3.0.x, 3.1.x, 3.2.x, and 4.0.x, running on Ruby 1.8.7, 1.9.3, and 2.0.0 with MySQL, PostgreSQL, and Sqlite. (JRuby is supported, but only with MySQL, because `low_card_tables` depends on the `activerecord-import` gem, and it currently does not have JRuby support for anything but MySQL.) Adding support for other databases is trivial!

`low_card_tables` is the successor to similar, but more primitive, systems that have been in place at very large commercial websites serving tens of millions of pages a day, and in database tables with hundreds of millions of rows. The predecessor systems were extremely successful and reliable &mdash; hence the desire to evolve this into an open-source gem.

`low_card_tables` is short for "low-cardinality tables". Cardinality, when applied to a database column, is the measure of the number of distinct values that column can hold. This Gem is meant to be used for columns that hold few distinct values throughout the table &mdash; hence, they have low cardinality.

Current build status: ![Current Build Status](https://api.travis-ci.org/ageweke/low_card_tables.png?branch=master)

===
# Documentation is on [the Wiki](https://github.com/ageweke/low_card_tables/wiki)!

This file would be incredibly long if it contained all the information present there. A quickstart guide is below;
see the Wiki for everything else.

===

### Installing low_card_tables

	# Gemfile
	gem 'low_card_tables'

### Getting Started

We'll first discuss adding entirely new tables, and then talk about how you can migrate existing tables.

#### Creating the Database Structure

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

#### Creating the Models

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

Please see [the Wiki](https://github.com/ageweke/low_card_tables/wiki) for further documentation!
