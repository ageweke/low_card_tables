module LowCardTables
  module Helpers
    class QuerySpyHelper
      class << self
        def with_query_spy(*args, &block)
          new(*args).spy(&block)
        end
      end

      def initialize(table_name)
        @table_name = table_name
        @calls = [ ]
      end

      def spy(&block)
        begin
          register!
          block.call(self)
        ensure
          deregister!
        end
      end

      def call_count
        @calls.length
      end

      def call(notification_name, when1, when2, id, data)
        sql = data[:sql]
        if sql && sql.strip.length > 0
          if sql =~ /^\s*SELECT.*FROM\s+['"\`]*\s*#{@table_name}\s*['"\`]*\s+/mi
            @calls << data.merge(:backtrace => caller)
          end
        end
      end

      private
      def register!
        ActiveSupport::Notifications.subscribe("sql.active_record", self)
      end

      def deregister!
        ActiveSupport::Notifications.unsubscribe(self)
      end
    end
  end
end
