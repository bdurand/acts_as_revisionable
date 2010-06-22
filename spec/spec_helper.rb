require 'rubygems'
require File.expand_path('../../lib/acts_as_revisionable', __FILE__)
require 'sqlite3'

module ActsAsRevisionable
  module Test
    def self.create_database
      db_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'tmp'))
      Dir.mkdir(db_dir) unless File.exist?(db_dir)
      db = File.join(db_dir, 'test.sqlite3')
      ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => db)
      ActsAsRevisionable::RevisionRecord.create_table
    end

    def self.delete_database
      db_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'tmp'))
      db = File.join(db_dir, 'test.sqlite3')
      ActiveRecord::Base.connection.disconnect!
      File.delete(db) if File.exist?(db)
      Dir.delete(db_dir) if File.exist?(db_dir) and Dir.entries(db_dir).reject{|f| f.match(/^\.+$/)}.empty?
    end
  end
end
