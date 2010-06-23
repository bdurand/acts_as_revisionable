require 'rubygems'
require File.expand_path('../../lib/acts_as_revisionable', __FILE__)
require 'sqlite3'

module ActsAsRevisionable
  module Test
    def self.create_database
      ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => ":memory:")
      ActsAsRevisionable::RevisionRecord.create_table
    end

    def self.delete_database
      ActiveRecord::Base.connection.drop_table(ActsAsRevisionable::RevisionRecord.table_name)
      ActiveRecord::Base.connection.disconnect!
    end
  end
end
