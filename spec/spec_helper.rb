require 'rubygems'
require 'logger'
require 'stringio'

if ENV["ACTIVE_RECORD_VERSION"]
  gem 'activerecord', ENV["ACTIVE_RECORD_VERSION"]
else
  gem 'activerecord'
end
require 'active_record'
ActiveRecord::ActiveRecordError

ActiveRecord::Base.logger = Logger.new(StringIO.new)

composite_primary_key_version = nil
if defined?(ActiveRecord::VERSION::MAJOR)
  if ActiveRecord::VERSION::MAJOR >= 3
    composite_primary_key_version = ">=3.0.0"
  else
    composite_primary_key_version = "~>2.3.5"
  end
elsif ENV["ACTIVE_RECORD_VERSION"] && ENV["ACTIVE_RECORD_VERSION"].match(/[^0-9]*2\.2/)
  composite_primary_key_version = "~>2.2.0"
end

gem 'composite_primary_keys', composite_primary_key_version
require 'composite_primary_keys'

require File.expand_path('../../lib/acts_as_revisionable', __FILE__)
require 'sqlite3'

module ActsAsRevisionable
  module Test
    def self.create_database
      ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => ":memory:")
    end

    def self.delete_database
      ActiveRecord::Base.connection.drop_table(ActsAsRevisionable::RevisionRecord.table_name)
      ActiveRecord::Base.connection.disconnect!
    end
  end
end
