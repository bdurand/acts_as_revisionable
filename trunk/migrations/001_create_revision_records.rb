class CreateRevisionRecords < ActiveRecord::Migration
  
  def self.up
    create_table :revision_records do |t|
      t.column :revisionable_type, :string, :limit => 100
      t.column :revisionable_id, :integer
      t.column :revision, :integer
      t.column :data, :binary, :limit => 5.megabytes
      t.column :created_at, :timestamp
    end
    
    add_index :revision_records, [:revisionable_type, :revisionable_id, :revision], :name => :revisionable, :unique => true
  end
  
  def self.down
    drop_table :revision_records
  end

end
