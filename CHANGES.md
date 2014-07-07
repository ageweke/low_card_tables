# `low_card_tables` Changelog

## 1.0.1, <pending>

* Fixed an issue where you couldn't migrate a low-card column into existence with a migration &mdash; because if you
declared a low-card column that didn't exist, you'd immediately receive an error. Now this works properly.
