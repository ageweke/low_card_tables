require 'active_record'
require "low_card_tables/version"
require 'low_card_tables/active_record/base'

module LowCardTables
  # Your code goes here...
end

class ActiveRecord::Base
  include LowCardTables::ActiveRecord::Base
end
