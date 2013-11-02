require 'low_card_tables/version_support'

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
            nil
          end
        end
      end

      def initialize
        config # make sure we raise on instantiation if configuration is invalid
      end

      def setup_activerecord!
        require 'active_record'
        require config[:require]
        ::ActiveRecord::Base.establish_connection(config[:config])

        require 'logger'
        require 'stringio'
        @logs = StringIO.new
        ::ActiveRecord::Base.logger = Logger.new(@logs)

        if config[:config][:adapter] == 'sqlite3'
          sqlite_version = ::ActiveRecord::Base.connection.send(:sqlite_version).instance_variable_get("@version").inspect rescue "unknown"
          $stderr.puts "SQLite Version: #{sqlite_version}"
        end
      end

      def table_name(name)
        "lctables_spec_#{name}"
      end

      def database_gem_name
        config[:database_gem_name]
      end

      private
      def config
        config_from_config_file || travis_ci_config_from_environment || invalid_config_file!
      end

      def config_from_config_file
        return nil unless File.exist?(config_file_path)
        require config_file_path

        return nil unless defined?(LOW_CARD_TABLES_SPEC_DATABASE_CONFIG)
        return nil unless LOW_CARD_TABLES_SPEC_DATABASE_CONFIG.kind_of?(Hash)

        return nil unless LOW_CARD_TABLES_SPEC_DATABASE_CONFIG[:require]
        return nil unless LOW_CARD_TABLES_SPEC_DATABASE_CONFIG[:database_gem_name]

        return nil unless LOW_CARD_TABLES_SPEC_DATABASE_CONFIG
        LOW_CARD_TABLES_SPEC_DATABASE_CONFIG
      end

      def travis_ci_config_from_environment
        dbtype = (ENV['LOW_CARD_TABLES_TRAVIS_CI_DATABASE_TYPE'] || '').strip.downcase
        case dbtype
        when 'postgres', 'postgresql'
          {
            :require => 'pg',
            :database_gem_name => 'pg',
            :config => {
              :adapter => 'postgresql',
              :database => 'myapp_test',
              :username => 'postgres',
              :min_messages => 'WARNING'
            }
          }
        when 'mysql'
          {
            :require => 'mysql2',
            :database_gem_name => 'mysql2',
            :config => {
              :adapter => 'mysql2',
              :database => 'myapp_test',
              :username => 'travis',
              :encoding => 'utf8'
            }
          }
        when 'sqlite'
          {
            :require => 'sqlite3',
            :database_gem_name => 'sqlite3',
            :config => {
              :adapter => 'sqlite3',
              :database => ':memory:',
              :timeout => 500
            }
          }
        when '', nil then nil
        else
          raise "Unknown Travis CI database type: #{dbtype.inspect}"
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
  :config  => { ...whatever ActiveRecord::Base.establish_connection should be passed... }

Alternatively, if you're running under Travis CI, you can set the environment variable
LOW_CARD_TABLES_TRAVIS_CI_DATABASE_TYPE to 'postgres', 'mysql', or 'sqlite', and it will
use the correct configuration for testing on Travis CI.}
      end
    end
  end
end
