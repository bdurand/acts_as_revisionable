require 'rubygems'
require 'logger'
require 'stringio'

if ENV["ACTIVE_RECORD_VERSION"]
  gem 'activesupport', ENV["ACTIVE_RECORD_VERSION"]
  gem 'activerecord', ENV["ACTIVE_RECORD_VERSION"]
else
  gem 'activerecord'
end
require 'active_record'
ActiveRecord::ActiveRecordError

ActiveRecord::Base.logger = Logger.new(StringIO.new)
puts "Testing with ActiveRecord #{ActiveRecord::VERSION::STRING}"

composite_primary_key_version = nil
if ActiveRecord::VERSION::MAJOR >= 3
  if ActiveRecord::VERSION::MINOR == 0
    composite_primary_key_version = "~>3.1.0"
  else
    composite_primary_key_version = "~>4.0.0.a"
  end
else
  composite_primary_key_version = "~>2.3.5"
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
