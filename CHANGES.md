# `low_card_tables` Changelog

## 1.0.3, 2014-09-22

* Fixed an issue where, if a table that owned a low-card table was declared a namespace (_e.g._, `module Foo; class Bar < ActiveRecord::Base; has_low_card_table :status; end; end`), the call to `has_low_card_table` would fail with an error (trying to call `+` on `nil`).
* Bumped versions of Rails and JRuby we test against on Travis to the very latest.

## 1.0.2, 2014-07-24

* Fixed an issue where, if someone had defined an `ActiveRecord::Base` subclass with a `nil` `table_name`, migrations
would fail.

## 1.0.1, 2014-07-07

* Fixed an issue where you couldn't migrate a low-card column into existence with a migration &mdash; because if you
declared a low-card column that didn't exist, you'd immediately receive an error. Now this works properly.
