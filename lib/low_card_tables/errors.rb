module LowCardTables
  module Errors
    class LowCardError < StandardError; end

    class LowCardColumnError < LowCardError; end

    # Raised when the client specifies a column in a low-card table that doesn't actually exist -- for example, when
    # trying to create new rows, or match against existing rows.
    class LowCardColumnNotPresentError < LowCardColumnError; end
    class LowCardColumnNotSpecifiedError < LowCardColumnError; end

    class LowCardNoUniqueIndexError < LowCardError; end

    class LowCardIdNotFoundError < LowCardError
      def initialize(message, ids)
        super(message)
        @ids = ids
      end

      attr_reader :ids
    end

    class LowCardAssociationError < LowCardError; end
    class LowCardAssociationAlreadyExistsError < LowCardAssociationError; end
    class LowCardAssociationNotFoundError < LowCardAssociationError; end

    class LowCardCannotSaveAssociatedLowCardObjectsError < LowCardError; end

    class LowCardInvalidLowCardRowsError < LowCardError; end

    class LowCardStaticScopeError < LowCardError; end

    class LowCardUnsupportedDatabaseError < LowCardError; end

    class LowCardTooManyRowsError < LowCardError; end
  end
end
