module LowCardTables
  module Errors
    class LowCardError < StandardError; end

    class LowCardColumnError < LowCardError; end
    class LowCardColumnNotPresentError < LowCardColumnError; end
    class LowCardColumnNotSpecifiedError < LowCardColumnError; end
    class LowCardIdNotFoundError < LowCardError; end
  end
end
