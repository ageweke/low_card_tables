module LowCardTables
  module Errors
    class LowCardError < StandardError; end

    class LowCardColumnError < LowCardError; end
    class LowCardColumnNotPresentError < LowCardColumnError; end
    class LowCardColumnNotSpecifiedError < LowCardColumnError; end
    class LowCardIdNotFoundError < LowCardError; end

    class LowCardAssociationError < LowCardError; end
    class LowCardAssociationAlreadyExistsError < LowCardAssociationError; end
    class LowCardAssociationNotFoundError < LowCardAssociationError; end

    class LowCardCannotSaveAssociatedLowCardObjectsError < LowCardError; end

    class LowCardInvalidLowCardRowsError < LowCardError; end
  end
end
