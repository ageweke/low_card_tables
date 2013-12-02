module LowCardTables
  # This module contains definitions of all exception classes used by +low_card_tables+. Note that +low_card_tables+
  # does not try to wrap any exception bubbled up by methods it calls as a LowCardError; rather, these are just used
  # to raise exceptions specific to +low_card_tables+.
  #
  # Any errors that are raised due to programming errors -- i.e., defensive detection of things that should never,
  # ever occur in the real world -- are left as ordinary StandardError instances, since you almost certainly don't
  # want to ever catch them.
  module Errors
    # All errors raised by LowCardTables inherit from this error. All errors raised are subclasses of this error, and
    # are never direct instances of this class.
    class LowCardError < StandardError; end

    # The superclass of the two errors below -- errors having to do with the schema of the low-card table.
    class LowCardColumnError < LowCardError; end

    # Raised when the client specifies a column in a low-card table that doesn't actually exist -- for example, when
    # trying to create new rows, or match against existing rows.
    class LowCardColumnNotPresentError < LowCardColumnError; end
    # Raised when the client does not specify a column in a call that requires all columns to be specified -- for
    # example, when trying to find the ID of a row by its attributes.
    class LowCardColumnNotSpecifiedError < LowCardColumnError; end

    # Raised when there is no unique index present on the low-card table across all value columns. This index is
    # required for operation of +low_card_tables+; various facilities in its support for migrations (and an explicit
    # API call) will create or remove it for you at your request, or just maintain it automatically.
    class LowCardNoUniqueIndexError < LowCardError; end

    # Raised when you explicitly ask for a row or rows by ID, and no such ID exists in the database. +ids+ is included
    # as an attribute of the error class, and contains an array of the IDs that were not found.
    class LowCardIdNotFoundError < LowCardError
      def initialize(message, ids)
        super(message)
        @ids = ids
      end

      attr_reader :ids
    end

    # The superclass of the error below -- raised when there's a problem with associations from a referring class to
    # one or more low-card tables.
    class LowCardAssociationError < LowCardError; end
    # Raised internally when asked for an association from a referring class by name, and no such association exists.
    class LowCardAssociationNotFoundError < LowCardAssociationError; end

    # Raised when a client tries to call #save or #save! on an associated low-card row (e.g., my_user.status.save!);
    # this is disallowed because it circumvents the entire purpose/idea of the low-card system.
    class LowCardCannotSaveAssociatedLowCardObjectsError < LowCardError; end

    # Raised when you try to create a low-card row or rows that the database treats as invalid. Typically, this means
    # you violated a database constraint when trying to create those rows.
    class LowCardInvalidLowCardRowsError < LowCardError; end

    # Raised when you try to define a scope involving a low-card table in a static way, rather than dynamic. (e.g., you
    # say, in class User, scope :alive, where(:deleted => false)) These scopes have their 'where' definitions evaluated
    # only once, at class definition time, and, as such, cannot ever pick up any new IDs of low-card rows that later
    # get created that match their definition. As such, we completely disallow their creation, and raise this error if
    # you try.
    #
    # The solution is trivial, and is to define them dynamically --
    # <tt>scope :alive, -> { where(:deleted => false) }</tt>. This is what ActiveRecord >= 4.0 requires, anyway -- the
    # static form is deprecated.
    class LowCardStaticScopeError < LowCardError; end

    # Raised when you try to use +low_card_tables+ with a database that isn't supported. It's very easy to support new
    # databases; you just have to teach the RowManager how to obtain an exclusive table lock on your type of database.
    class LowCardUnsupportedDatabaseError < LowCardError; end

    # Raised when we detect that there are more than (by default) 5,000 rows in a low-card table; this is taken as a
    # sign that you screwed up and added an attribute to your table that isn't actually of low cardinality. You can
    # adjust this threshold, if necessary, using the option +:max_row_count+ on your +is_low_card_table+ definition.
    class LowCardTooManyRowsError < LowCardError; end
  end
end
