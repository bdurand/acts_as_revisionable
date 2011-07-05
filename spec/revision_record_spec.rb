require 'spec_helper'
require 'zlib'

describe ActsAsRevisionable::RevisionRecord do

  before :all do
    ActsAsRevisionable::Test.create_database
    ActsAsRevisionable::RevisionRecord.create_table
    
    class TestRevisionableAssociationLegacyRecord < ActiveRecord::Base
      connection.create_table(table_name, :id => false) do |t|
        t.column :legacy_id, :integer
        t.column :name, :string
        t.column :value, :integer
        t.column :test_revisionable_record_id, :integer
      end unless table_exists?
      self.primary_key = "legacy_id"
    end
    
    class TestRevisionableOneAssociationRecord < ActiveRecord::Base
      connection.create_table(table_name, :id => false) do |t|
        t.column :name, :string
        t.column :value, :integer
        t.column :test_revisionable_record_id, :integer
      end unless table_exists?
    end
    
    class TestRevisionableAssociationComposite < ActiveRecord::Base
      connection.create_table(table_name, :id => false) do |t|
        t.column :first_id, :integer
        t.column :second_id, :integer
        t.column :name, :string
        t.column :value, :integer
      end unless table_exists?
      set_primary_keys "first_id", "second_id"
    end

    class TestRevisionableAssociationRecord < ActiveRecord::Base
      connection.create_table(table_name) do |t|
        t.column :name, :string
        t.column :value, :integer
        t.column :test_revisionable_record_id, :integer
      end unless table_exists?
      
      has_one :sub_association, :class_name => 'TestRevisionableSubAssociationRecord'
    end

    class OtherRevisionableRecordsTestRevisionableRecords < ActiveRecord::Base
      connection.create_table(table_name, :id => false) do |t|
        t.column :test_revisionable_record_id, :integer
        t.column :other_revisionable_record_id, :integer
      end unless table_exists?
    end

    class TestRevisionableSubAssociationRecord < ActiveRecord::Base
      connection.create_table(table_name) do |t|
        t.column :name, :string
        t.column :value, :integer
        t.column :test_revisionable_association_record_id, :integer
      end unless table_exists?
    end

    module ActsAsRevisionable
      class TestModuleRecord < ActiveRecord::Base
        connection.create_table(table_name) do |t|
          t.column :name, :string
          t.column :value, :integer
        end unless table_exists?
      end
    end

    class TestRevisionableRecord < ActiveRecord::Base
      connection.create_table(table_name) do |t|
        t.column :name, :string
        t.column :value, :integer
        t.column :test_revisionable_one_association_record_id, :integer
      end unless table_exists?
      
      has_many :associations, :class_name => 'TestRevisionableAssociationRecord'
      has_many :legacy_associations, :class_name => 'TestRevisionableAssociationLegacyRecord'
      has_many :composit_associations, :class_name => 'TestRevisionableAssociationComposite', :foreign_key => :first_id
      has_and_belongs_to_many :other_revisionable_records
      has_one :one_association, :class_name => 'TestRevisionableOneAssociationRecord'
      
      acts_as_revisionable :associations => [{:associations => :sub_association}, :one_association, :other_revisionable_records]
    end
    
    class OtherRevisionableRecord < ActiveRecord::Base
      connection.create_table(table_name) do |t|
        t.column :name, :string
        t.column :value, :integer
        t.column :type, :string
      end unless table_exists?
    end
    
    class TestInheritanceRecord < OtherRevisionableRecord
      def self.base_class
        OtherRevisionableRecord
      end
    end
  end

  after :all do
    ActsAsRevisionable::Test.delete_database
  end

  before :each do
    ActsAsRevisionable::RevisionRecord.delete_all
    TestRevisionableRecord.delete_all
    TestRevisionableAssociationLegacyRecord.delete_all
    TestRevisionableAssociationRecord.delete_all
    TestRevisionableSubAssociationRecord.delete_all
    ActsAsRevisionable::TestModuleRecord.delete_all
    OtherRevisionableRecord.delete_all
    TestInheritanceRecord.delete_all
    OtherRevisionableRecordsTestRevisionableRecords.delete_all
    TestRevisionableOneAssociationRecord.delete_all
  end

  it "should set the revision number before it creates the record" do
    record = TestRevisionableRecord.create(:name => "test")
    revision1 = ActsAsRevisionable::RevisionRecord.new(record)
    revision1.save!
    revision2 = ActsAsRevisionable::RevisionRecord.new(record)
    revision2.save!
    revision1.revision.should == 1
    revision2.revision.should == 2
    revision2.revision = 20
    revision2.save!
    revision3 = ActsAsRevisionable::RevisionRecord.new(record)
    revision3.save!
    revision3.revision.should == 21
  end

  it "should serialize all the attributes of the original model" do
    original = TestRevisionableRecord.new('name' => 'revision', 'value' => 5)
    original.id = 1
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revisionable_id.should == 1
    revision.revisionable_type.should == "TestRevisionableRecord"
    revision.revision_attributes['name'].should == 'revision'
    revision.revision_attributes['value'].should == 5
  end

  it "should serialize all the attributes of revisionable has_many associations" do
    original = TestRevisionableRecord.new(:name => 'revision', :value => 1)
    association_1 = original.associations.build(:name => 'association 1', :value => 2)
    association_2 = original.associations.build(:name => 'association 2', :value => 3)
    original.save!
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes['associations'].should == [
      {
        "id" => association_1.id,
        "name" => "association 1",
        "value" => 2,
        "test_revisionable_record_id" => original.id,
        "sub_association" => nil
      },
      {
        "id" => association_2.id,
        "name" => "association 2",
        "value" => 3,
        "test_revisionable_record_id" => original.id,
        "sub_association" => nil
      }
    ]
  end

  it "should serialize all the attributes of revisionable has_one associations" do
    original = TestRevisionableRecord.new(:name => 'revision', :value => 1)
    one = original.build_one_association(:name => 'one', :value => 2)
    original.save!
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes['one_association'].should == {
      "name"=>"one", "value"=>2, "test_revisionable_record_id"=>original.id
    }
  end

  it "should serialize all revisionable has_many_and_belongs_to_many associations" do
    original = TestRevisionableRecord.new(:name => 'revision', :value => 1)
    other_1 = OtherRevisionableRecord.create(:name => "other 1")
    other_2 = OtherRevisionableRecord.create(:name => "other 2")
    other_3 = OtherRevisionableRecord.create(:name => "other 3")
    original.other_revisionable_records << other_1
    original.other_revisionable_records << other_2
    original.other_revisionable_records << other_3
    original.save!
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes['other_revisionable_records'].sort.should == [other_1.id, other_2.id, other_3.id]
  end

  it "should serialize revisionable associations of revisionable associations" do
    original = TestRevisionableRecord.new(:name => 'revision', :value => 1)
    association_1 = original.associations.build(:name => 'association 1', :value => 2)
    association_2 = original.associations.build(:name => 'association 2', :value => 3)
    sub_association = association_1.build_sub_association(:name => 'sub', :value => 4)
    original.save!
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes.should == {
      "id" => original.id,
      "name" => "revision",
      "value" => 1,
      "associations" => [
        {
          "id" => association_1.id,
          "name" => "association 1",
          "value" => 2,
          "test_revisionable_record_id" => original.id,
          "sub_association" => {
            "id" => sub_association.id,
            "name" => "sub",
            "value" => 4,
            "test_revisionable_association_record_id" => association_1.id
          }
        },
        {
          "id" => association_2.id,
          "name" => "association 2",
          "value" => 3,
          "test_revisionable_record_id" => original.id,
          "sub_association" => nil
        }
      ],
      "test_revisionable_one_association_record_id" => nil,
      "other_revisionable_records" => [],
      "one_association" => nil
    }
  end

  it "should be able to restore the original model using Ruby serialization" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5, 'test_revisionable_one_association_record_id' => nil}
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(attributes), :ruby)
    revision.data = Zlib::Deflate.deflate(Marshal.dump(attributes))
    restored = revision.restore
    restored.class.should == TestRevisionableRecord
    restored.id.should == 1
    restored.attributes.should == attributes
  end

  it "should be able to restore the original model using YAML serialization" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5, 'test_revisionable_one_association_record_id' => nil}
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(attributes), :yaml)
    revision.data = Zlib::Deflate.deflate(YAML.dump(attributes))
    restored = revision.restore
    restored.class.should == TestRevisionableRecord
    restored.id.should == 1
    restored.attributes.should == attributes
  end

  it "should be able to restore the original model using XML serialization" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5, 'test_revisionable_one_association_record_id' => nil}
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(attributes), :xml)
    revision.data = Zlib::Deflate.deflate(YAML.dump(attributes))
    restored = revision.restore
    restored.class.should == TestRevisionableRecord
    restored.id.should == 1
    restored.attributes.should == attributes
  end

  it "should be able to restore associations" do
    restored = TestRevisionableRecord.new
    attributes = {'id' => 1, 'name' => 'revision', 'value' => Time.now, :associations => {'id' => 2, 'value' => 'val'}}
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    revision.data = Zlib::Deflate.deflate(Marshal.dump(attributes))
    TestRevisionableRecord.should_receive(:new).and_return(restored)
    revision.should_receive(:restore_association).with(restored, :associations, {'id' => 2, 'value' => 'val'})
    restored = revision.restore
  end

  it "should be able to restore the has_many associations" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    revision.send(:restore_association, record, :associations, {'id' => 1, 'name' => 'assoc', 'value' => 10})
    record.associations.size.should == 1
    associated_record = record.associations.first
    associated_record.id.should == 1
    associated_record.name.should == 'assoc'
    associated_record.value.should == 10
  end

  it "should be able to restore the has_many associations with a legacy primary key" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    revision.send(:restore_association, record, :legacy_associations, {'legacy_id' => 1, 'name' => 'legacy', 'value' => 10})
    record.legacy_associations.size.should == 1
    associated_record = record.legacy_associations.first
    associated_record.id.should == 1
    associated_record.name.should == 'legacy'
    associated_record.value.should == 10
  end

  it "should be able to restore the has_many associations with composite primary keys" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    revision.send(:restore_association, record, :composit_associations, {'first_id' => 1, 'second_id' => 2, 'name' => 'composit', 'value' => 10})
    record.composit_associations.size.should == 1
    associated_record = record.composit_associations.first
    associated_record.first_id.should == 1
    associated_record.second_id.should == 2
    associated_record.name.should == 'composit'
    associated_record.value.should == 10
  end

  it "should be able to restore the has_one associations" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    revision.send(:restore_association, record, :one_association, {'id' => 1, 'name' => 'one', 'value' => 1})
    record.one_association.id.should == 1
    record.one_association.name.should == 'one'
    record.one_association.value.should == 1
  end

  it "should be able to restore the has_and_belongs_to_many associations" do
    other_1 = OtherRevisionableRecord.create(:name => "other 1")
    other_2 = OtherRevisionableRecord.create(:name => "other 2")
    other_3 = OtherRevisionableRecord.create(:name => "other 3")
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    revision.send(:restore_association, record, :other_revisionable_records, [other_1.id, other_2.id, other_3.id])
    record.other_revisionable_records.collect{|r| r.id}.sort.should == [other_1.id, other_2.id, other_3.id]
  end

  it "should be able to restore associations of associations" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    revision.send(:restore_association, record, :associations, {'id' => 1, 'name' => 'assoc', 'value' => 10, :sub_association => {'id' => 2, 'name' => 'sub', 'value' => 1000}})
    record.associations.size.should == 1
    associated_record = record.associations.first
    associated_record.id.should == 1
    associated_record.name.should == 'assoc'
    associated_record.value.should == 10
    sub_associated_record = associated_record.sub_association
    sub_associated_record.id.should == 2
    sub_associated_record.name.should == 'sub'
    sub_associated_record.value.should == 1000
  end

  it "should be able to restore a record for a model that has changed and add errors to the restored record" do
    restored = TestRevisionableRecord.new
    attributes = {'id' => 1, 'name' => 'revision', 'value' => Time.now, 'deleted_attribute' => 'abc', :bad_association => {'id' => 3, 'value' => :val}, :associations => {'id' => 2, 'value' => 'val', 'other' => 'val2'}}
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    revision.data = Zlib::Deflate.deflate(Marshal.dump(attributes))
    TestRevisionableRecord.should_receive(:new).and_return(restored)

    associations = mock(:associations)
    restored.should_receive(:associations).and_return(associations)
    associated_record = TestRevisionableAssociationRecord.new
    associations.should_receive(:build).and_return(associated_record)

    restored = revision.restore
    
    restored.errors[:deleted_attribute].should include("could not be restored to \"abc\"")
    restored.errors[:bad_association].should include("could not be restored to {\"id\"=>3, \"value\"=>:val}")
    restored.errors[:associations].should include("could not be restored from the revision")
    associated_record.errors[:other].should include("could not be restored to \"val2\"")
  end

  it "should be able to truncate the revisions for a record" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(:name => 'name'))
    revision.revision = 20
    ActsAsRevisionable::RevisionRecord.should_receive(:find).with(:first, :conditions => ['revisionable_type = ? AND revisionable_id = ?', 'TestRevisionableRecord', 1], :offset => 15, :order => 'revision DESC').and_return(revision)
    ActsAsRevisionable::RevisionRecord.should_receive(:delete_all).with(['revisionable_type = ? AND revisionable_id = ? AND revision <= ?', 'TestRevisionableRecord', 1, 20])
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, 1, :limit => 15)
  end

  it "should be able to truncate the revisions for a record by age" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(:name => 'name'))
    revision.revision = 20
    time = 2.weeks.ago
    minimum_age = stub(:integer, :ago => time, :to_i => 1)
    Time.stub!(:now).and_return(minimum_age)
    ActsAsRevisionable::RevisionRecord.should_receive(:find).with(:first, :conditions => ['revisionable_type = ? AND revisionable_id = ? AND created_at <= ?', 'TestRevisionableRecord', 1, time], :offset => nil, :order => 'revision DESC').and_return(revision)
    ActsAsRevisionable::RevisionRecord.should_receive(:delete_all).with(['revisionable_type = ? AND revisionable_id = ? AND revision <= ?', 'TestRevisionableRecord', 1, 20])
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, 1, :minimum_age => minimum_age)
  end

  it "should not truncate the revisions for a record if it doesn't have enough" do
    ActsAsRevisionable::RevisionRecord.should_receive(:find).with(:first, :conditions => ['revisionable_type = ? AND revisionable_id = ?', 'TestRevisionableRecord', 1], :offset => 15, :order => 'revision DESC').and_return(nil)
    ActsAsRevisionable::RevisionRecord.should_not_receive(:delete_all)
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, 1, :limit => 15)
  end

  it "should not truncate the revisions for a record if no limit or minimum_age is set" do
    ActsAsRevisionable::RevisionRecord.should_not_receive(:find)
    ActsAsRevisionable::RevisionRecord.should_not_receive(:delete_all)
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, 1, :limit => nil, :minimum_age => nil)
  end

  it "should be able to find a record by revisioned type and id" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(:name => 'name'))
    ActsAsRevisionable::RevisionRecord.should_receive(:find).with(:first, :conditions => {:revisionable_type => 'TestRevisionableRecord', :revisionable_id => 1, :revision => 2}).and_return(revision)
    ActsAsRevisionable::RevisionRecord.find_revision(TestRevisionableRecord, 1, 2).should == revision
  end
  
  it "should find the last revision" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(:name => 'name'))
    ActsAsRevisionable::RevisionRecord.should_receive(:find).with(:first, :conditions => {:revisionable_type => 'TestRevisionableRecord', :revisionable_id => 1}, :order => "revision DESC").and_return(revision)
    ActsAsRevisionable::RevisionRecord.last_revision(TestRevisionableRecord, 1).should == revision
  end

  it "should handle module namespaces" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5}
    revision = ActsAsRevisionable::RevisionRecord.new(ActsAsRevisionable::TestModuleRecord.new(attributes))
    revision.data = Zlib::Deflate.deflate(Marshal.dump(attributes))
    restored = revision.restore
    restored.class.should == ActsAsRevisionable::TestModuleRecord
  end

  it "should handle single table inheritance" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5}
    record = TestInheritanceRecord.new(attributes)
    revision = ActsAsRevisionable::RevisionRecord.new(record)
    revision.data = Zlib::Deflate.deflate(Marshal.dump(record.attributes))
    restored = revision.restore
    restored.class.should == TestInheritanceRecord
  end

  it "should really save the revision records to the database and restore without any mocking" do
    ActsAsRevisionable::RevisionRecord.count.should == 0

    original = TestRevisionableRecord.create(:name => 'revision 1', :value => 100)
    ActsAsRevisionable::RevisionRecord.new(original).save!
    first_revision = ActsAsRevisionable::RevisionRecord.first
    original.name = 'revision 2'
    ActsAsRevisionable::RevisionRecord.new(original).save!
    original.name = 'revision 3'
    ActsAsRevisionable::RevisionRecord.new(original).save!
    ActsAsRevisionable::RevisionRecord.count.should == 3

    record = ActsAsRevisionable::RevisionRecord.find_revision(TestRevisionableRecord, original.id, 1).restore
    record.class.should == TestRevisionableRecord
    record.id.should == original.id
    record.name.should == 'revision 1'
    record.value.should == 100

    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, original.id, :limit => 2)
    ActsAsRevisionable::RevisionRecord.count.should == 2
    ActsAsRevisionable::RevisionRecord.find_by_id(first_revision.id).should == nil
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, original.id, :limit => 0, :minimum_age => 1.week)
    ActsAsRevisionable::RevisionRecord.count.should == 2
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, original.id, :limit => 0)
    ActsAsRevisionable::RevisionRecord.count.should == 0
  end
  
  it "should delete revisions for models in a class that no longer exist if they are older than a specified number of seconds" do
    record_1 = TestRevisionableRecord.create(:name => 'record_1')
    record_2 = TestRevisionableAssociationLegacyRecord.create!(:name => 'record_2')
    record_2.id = record_1.id
    record_2.save!
    revision_0 = ActsAsRevisionable::RevisionRecord.create(record_1)
    revision_1 = ActsAsRevisionable::RevisionRecord.create(record_1)
    revision_1.trash!
    revision_2 = ActsAsRevisionable::RevisionRecord.create(record_2)
    revision_2.trash!
    revision_3 = ActsAsRevisionable::RevisionRecord.create(TestRevisionableRecord.create(:name => 'record_3'))
    now = Time.now
    Time.stub(:now => now + 60)
    revision_4 = ActsAsRevisionable::RevisionRecord.create(TestRevisionableRecord.create(:name => 'record_4'))
    revision_4.trash!
    ActsAsRevisionable::RevisionRecord.count.should == 5
    ActsAsRevisionable::RevisionRecord.empty_trash(TestRevisionableRecord, 30)
    ActsAsRevisionable::RevisionRecord.count.should == 3
    ActsAsRevisionable::RevisionRecord.all.collect{|r| r.id}.sort.should == [revision_2.id, revision_3.id, revision_4.id]
  end
end
