module LowCardTables
  module Helpers
    class DatabaseHelper
      class InvalidDatabaseConfigurationError < StandardError; end

      class << self
        def maybe_database_gem_name
          begin
            dh = new
            dh.database_gem_name
          rescue InvalidDatabaseConfigurationError => idce
            $stderr.puts idce
            nil
          end
        end
      end

      def initialize
        config # make sure we raise on instantiation if configuration is invalid
      end

      def setup_activerecord!
        require config[:require]
        ::ActiveRecord::Base.establish_connection(config[:config])
      end

      def table_name(name)
        "lctables_spec_#{name}"
      end

      def database_gem_name
        config[:database_gem_name]
      end

      private
      def config
        @config ||= begin
          invalid_config_file! unless File.exist?(config_file_path)
          require config_file_path

          invalid_config_file! unless defined?(LOW_CARD_TABLES_SPEC_DATABASE_CONFIG)
          invalid_config_file! unless LOW_CARD_TABLES_SPEC_DATABASE_CONFIG.kind_of?(Hash)

          LOW_CARD_TABLES_SPEC_DATABASE_CONFIG[:require] || invalid_config_file!
          LOW_CARD_TABLES_SPEC_DATABASE_CONFIG[:database_gem_name] || invalid_config_file!

          LOW_CARD_TABLES_SPEC_DATABASE_CONFIG || invalid_config_file!
        end
      end

      def config_file_path
        @config_file_path ||= File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'spec_database_config.rb'))
      end

      def invalid_config_file!
        raise Errno::ENOENT, %{In order to run specs for LowCardTables, you need to create a file at:

#{config_file_path}

...that defines a top-level LOW_CARD_TABLES_SPEC_DATABASE_CONFIG hash, with members:

  :require => 'name_of_adapter_to_require',
  :database_gem_name => 'name_of_gem_for_adapter',
  :config  => { ...whatever ActiveRecord::Base.establish_connection should be passed... }}
      end
    end
  end
end
