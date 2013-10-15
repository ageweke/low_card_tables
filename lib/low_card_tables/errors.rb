module LowCardTables
  module Errors
    class LowCardError < StandardError; end

    class LowCardColumnNotPresentError < LowCardError; end
  end
end
