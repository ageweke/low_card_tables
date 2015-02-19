# `low_card_tables` Changelog

## 1.1.1,

* Fixed an issue where, if you installed another ActiveRecord-related gem installed that defined a method `primary_keys` on a model that returned an empty array, `low_card_tables` would incorrectly behave as if the low-card table had no primary key at all, and expect you to include `id` in the all-columns index.

## 1.1.0, 2015-02-18

* The [single-table inheritance](http://api.rubyonrails.org/classes/ActiveRecord/Base.html#label-Single+table+inheritance) type-discrimination column &mdash; by default called `type` &mdash; can now be part of a low-cardinality table itself. This elegantly allows you to use STI without consuming the very large amounts of space required by Rails' default implementation, where it stores the name of the class in every single row.
* Fixed issues where you couldn't use `low_card_tables` with an ActiveRecord class that was at anything but the leaf of a [single-table inheritance](http://api.rubyonrails.org/classes/ActiveRecord/Base.html#label-Single+table+inheritance) hierarchy.
* Ensured that you can query a column containing a string or symbol with a query that's a string or a symbol, and it all works fine.
* Added support for `WHERE` clauses on a low-card table containing an array (`.where(:my_low_card_column => [ :foo, :bar ])`).
* Added support for ActiveRecord 4.2.x, and bumped versions on the CI configuration.

## 1.0.3, 2014-09-22

* Fixed an issue where, if a table that owned a low-card table was declared a namespace (_e.g._, `module Foo; class Bar < ActiveRecord::Base; has_low_card_table :status; end; end`), the call to `has_low_card_table` would fail with an error (trying to call `+` on `nil`).
* Bumped versions of Rails and JRuby we test against on Travis to the very latest.

## 1.0.2, 2014-07-24

* Fixed an issue where, if someone had defined an `ActiveRecord::Base` subclass with a `nil` `table_name`, migrations
would fail.

## 1.0.1, 2014-07-07

* Fixed an issue where you couldn't migrate a low-card column into existence with a migration &mdash; because if you
declared a low-card column that didn't exist, you'd immediately receive an error. Now this works properly.
