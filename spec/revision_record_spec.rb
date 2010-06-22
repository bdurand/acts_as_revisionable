require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'zlib'

describe ActsAsRevisionable::RevisionRecord do
  
  before :all do
    ActsAsRevisionable::Test.create_database
  end
  
  after :all do
    ActsAsRevisionable::Test.delete_database
  end

  class TestRevisionableRecord
    attr_accessor :attributes
    
    def self.base_class
      self
    end
    
    def self.inheritance_column
      'type'
    end
    
    def self.store_full_sti_class
      true
    end
    
    def initialize (attributes = {})
      @attributes = attributes
    end
    
    def self.reflections
      @reflections || {}
    end
    
    def self.reflections= (vals)
      @reflections = vals
    end
  
    def id
      attributes['id']
    end
    
    def id= (val)
      attributes['id'] = val
    end
    
    def name= (val)
      attributes['name'] = val
    end
    
    def value= (val)
      attributes['value'] = val
    end
    
    def self.revisionable_associations
      nil
    end
    
    def self.type_name_with_module (type_name)
      type_name
    end
  end
  
  class TestRevisionableAssociationRecord < TestRevisionableRecord
    def self.reflections
      @reflections || {}
    end
    
    def self.reflections= (vals)
      @reflections = vals
    end
  end
  
  class TestRevisionableSubAssociationRecord < TestRevisionableRecord
    def self.reflections
      @reflections || {}
    end
    
    def self.reflections= (vals)
      @reflections = vals
    end
  end
  
  module ActsAsRevisionable
    class TestModuleRecord < TestRevisionableRecord
    end
  end
  
  class TestInheritanceRecord < TestRevisionableRecord
    def self.base_class
      TestRevisionableRecord
    end
    
    def initialize (attributes = {})
      super({'type' => 'TestInheritanceRecord'}.merge(attributes))
    end
    
    def type= (val)
      attributes['type'] = val
    end
  end
  
  before(:each) do
    TestRevisionableRecord.reflections = nil
    TestRevisionableAssociationRecord.reflections = nil
    TestRevisionableSubAssociationRecord.reflections = nil
  end
  
  it "should set the revision number before it creates the record" do
    ActsAsRevisionable::RevisionRecord.delete_all
    revision1 = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new('id' => 1))
    revision1.save!
    revision2 = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new('id' => 1))
    revision2.save!
    revision1.revision.should == 1
    revision2.revision.should == 2
    revision2.revision = 20
    revision2.save!
    revision3 = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new('id' => 1))
    revision3.save!
    revision3.revision.should == 21
    ActsAsRevisionable::RevisionRecord.delete_all
  end
  
  it "should serialize all the attributes of the original model" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5}
    original = TestRevisionableRecord.new(attributes)
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revisionable_id.should == 1
    revision.revisionable_type.should == "TestRevisionableRecord"
    revision.revision_attributes.should == attributes
  end
  
  it "should serialize all the attributes of revisionable has_many associations" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => Time.now}
    association_attributes_1 = {'id' => 2, 'name' => 'association_1'}
    association_attributes_2 = {'id' => 3, 'name' => 'association_2'}
    original = TestRevisionableRecord.new(attributes)
    revisionable_associations = [TestRevisionableAssociationRecord.new(association_attributes_1), TestRevisionableAssociationRecord.new(association_attributes_2)]
    revisionable_associations_reflection = stub(:association, :name => :revisionable_associations, :macro => :has_many, :options => {:dependent => :destroy})
    non_revisionable_associations_reflection = stub(:association, :name => :non_revisionable_associations, :macro => :has_many, :options => {})
    
    TestRevisionableRecord.should_receive(:revisionable_associations).and_return(:revisionable_associations => true)
    TestRevisionableRecord.reflections = {:revisionable_associations => revisionable_associations_reflection, :non_revisionable_associations => non_revisionable_associations_reflection}
    original.should_not_receive(:non_revisionable_associations)
    original.should_receive(:revisionable_associations).and_return(revisionable_associations)
    
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes.should == attributes.merge('revisionable_associations' => [association_attributes_1, association_attributes_2])
  end
  
  it "should serialize all the attributes of revisionable has_one associations" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => Date.today}
    association_attributes = {'id' => 2, 'name' => 'association_1'}
    original = TestRevisionableRecord.new(attributes)
    revisionable_association = TestRevisionableAssociationRecord.new(association_attributes)
    revisionable_association_reflection = stub(:association, :name => :revisionable_association, :macro => :has_one, :options => {:dependent => :destroy})
    non_revisionable_association_reflection = stub(:association, :name => :non_revisionable_association, :macro => :has_one, :options => {})
    
    TestRevisionableRecord.should_receive(:revisionable_associations).and_return(:revisionable_association => true)
    TestRevisionableRecord.reflections = {:revisionable_association => revisionable_association_reflection, :non_revisionable_association => non_revisionable_association_reflection}
    original.should_not_receive(:non_revisionable_association)
    original.should_receive(:revisionable_association).and_return(revisionable_association)
    
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes.should == attributes.merge('revisionable_association' => association_attributes)
  end
  
  it "should serialize all revisionable has_many_and_belongs_to_many associations" do
    attributes = {'id' => 1, 'name' => 'revision'}
    original = TestRevisionableRecord.new(attributes)
    revisionable_associations_reflection = stub(:association, :name => :revisionable_associations, :macro => :has_and_belongs_to_many, :options => {:dependent => :destroy})
    non_revisionable_associations_reflection = stub(:association, :name => :non_revisionable_associations, :macro => :has_and_belongs_to_many, :options => {})
    
    TestRevisionableRecord.should_receive(:revisionable_associations).and_return(:revisionable_associations => true)
    TestRevisionableRecord.reflections = {:revisionable_associations => revisionable_associations_reflection, :non_revisionable_associations => non_revisionable_associations_reflection}
    original.should_receive(:revisionable_association_ids).and_return([2, 3, 4])
    
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes.should == attributes.merge('revisionable_associations' => [2, 3, 4])
  end
  
  it "should serialize revisionable associations of revisionable associations with :dependent => :destroy" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => Time.now}
    association_attributes_1 = {'id' => 2, 'name' => 'association_1'}
    association_attributes_2 = {'id' => 3, 'name' => 'association_2'}
    original = TestRevisionableRecord.new(attributes)
    association_1 = TestRevisionableAssociationRecord.new(association_attributes_1)
    association_2 = TestRevisionableAssociationRecord.new(association_attributes_2)
    revisionable_associations = [association_1, association_2]
    revisionable_associations_reflection = stub(:association, :name => :revisionable_associations, :macro => :has_many, :options => {:dependent => :destroy})
    sub_association_attributes = {'id' => 4, 'name' => 'sub_association_1'}
    sub_association = TestRevisionableSubAssociationRecord.new(sub_association_attributes)
    sub_association_reflection = stub(:sub_association, :name => :sub_association, :macro => :has_one, :options => {:dependent => :destroy})
    
    TestRevisionableRecord.should_receive(:revisionable_associations).and_return(:revisionable_associations => {:sub_association => true})
    TestRevisionableRecord.reflections = {:revisionable_associations => revisionable_associations_reflection}
    TestRevisionableAssociationRecord.reflections = {:sub_association => sub_association_reflection}
    original.should_receive(:revisionable_associations).and_return(revisionable_associations)
    association_1.should_receive(:sub_association).and_return(sub_association)
    association_2.should_receive(:sub_association).and_return(nil)
    
    revision = ActsAsRevisionable::RevisionRecord.new(original)
    revision.revision_attributes.should == attributes.merge('revisionable_associations' => [association_attributes_1.merge('sub_association' => sub_association_attributes), association_attributes_2.merge('sub_association' => nil)])
  end
  
  it "should be able to restore the original model using Ruby serialization" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5}
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(attributes), :ruby)
    revision.data = Zlib::Deflate.deflate(Marshal.dump(attributes))
    restored = revision.restore
    restored.class.should == TestRevisionableRecord
    restored.id.should == 1
    restored.attributes.should == attributes
  end
  
  it "should be able to restore the original model using YAML serialization" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5}
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new(attributes), :yaml)
    revision.data = Zlib::Deflate.deflate(YAML.dump(attributes))
    restored = revision.restore
    restored.class.should == TestRevisionableRecord
    restored.id.should == 1
    restored.attributes.should == attributes
  end
    
  it "should be able to restore the original model using XML serialization" do
    attributes = {'id' => 1, 'name' => 'revision', 'value' => 5}
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
    associations_reflection = stub(:associations, :name => :associations, :macro => :has_many, :options => {:dependent => :destroy})
    TestRevisionableRecord.reflections = {:associations => associations_reflection}
    TestRevisionableRecord.should_receive(:new).and_return(restored)
    revision.should_receive(:restore_association).with(restored, :associations, {'id' => 2, 'value' => 'val'})
    restored = revision.restore
  end
  
  it "should be able to restore the has_many associations" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    
    associations_reflection = stub(:associations, :name => :associations, :macro => :has_many, :options => {:dependent => :destroy})
    TestRevisionableRecord.reflections = {:associations => associations_reflection}
    associations = mock(:associations)
    record.should_receive(:associations).and_return(associations)
    associated_record = TestRevisionableAssociationRecord.new
    associations.should_receive(:build).and_return(associated_record)
    
    revision.send(:restore_association, record, :associations, {'id' => 1, 'value' => 'val'})
    associated_record.id.should == 1
    associated_record.attributes.should == {'id' => 1, 'value' => 'val'}
  end
  
  it "should be able to restore the has_one associations" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    
    association_reflection = stub(:associations, :name => :association, :macro => :has_one, :klass => TestRevisionableAssociationRecord, :options => {:dependent => :destroy})
    TestRevisionableRecord.reflections = {:association => association_reflection}
    associated_record = TestRevisionableAssociationRecord.new
    TestRevisionableAssociationRecord.should_receive(:new).and_return(associated_record)
    record.should_receive(:association=).with(associated_record)
    
    revision.send(:restore_association, record, :association, {'id' => 1, 'value' => 'val'})
    associated_record.id.should == 1
    associated_record.attributes.should == {'id' => 1, 'value' => 'val'}
  end
  
  it "should be able to restore the has_and_belongs_to_many associations" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    
    associations_reflection = stub(:associations, :name => :associations, :macro => :has_and_belongs_to_many, :options => {})
    TestRevisionableRecord.reflections = {:associations => associations_reflection}
    record.should_receive(:association_ids=).with([2, 3, 4])
    
    revision.send(:restore_association, record, :associations, [2, 3, 4])
  end
  
  it "should be able to restore associations of associations" do
    revision = ActsAsRevisionable::RevisionRecord.new(TestRevisionableRecord.new)
    record = TestRevisionableRecord.new
    
    associations_reflection = stub(:associations, :name => :associations, :macro => :has_many, :options => {:dependent => :destroy})
    TestRevisionableRecord.reflections = {:associations => associations_reflection}
    associations = mock(:associations)
    record.should_receive(:associations).and_return(associations)
    associated_record = TestRevisionableAssociationRecord.new
    associations.should_receive(:build).and_return(associated_record)

    sub_associated_record = TestRevisionableSubAssociationRecord.new
    TestRevisionableAssociationRecord.should_receive(:new).and_return(sub_associated_record)
    sub_association_reflection = stub(:sub_association, :name => :sub_association, :macro => :has_one, :klass => TestRevisionableAssociationRecord, :options => {:dependent => :destroy})
    TestRevisionableAssociationRecord.reflections = {:sub_association => sub_association_reflection}
    associated_record.should_receive(:sub_association=).with(sub_associated_record)
    
    revision.send(:restore_association, record, :associations, {'id' => 1, 'value' => 'val', :sub_association => {'id' => 2, 'value' => 'sub'}})
    associated_record.id.should == 1
    associated_record.attributes.should == {'id' => 1, 'value' => 'val'}
    sub_associated_record.id.should == 2
    sub_associated_record.attributes.should == {'id' => 2, 'value' => 'sub'}
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
    
    mock_record_errors = {}
    restored.stub!(:errors).and_return(mock_record_errors)
    mock_record_errors.should_receive(:add).with(:bad_association, "could not be restored to {\"id\"=>3, \"value\"=>:val}")
    mock_record_errors.should_receive(:add).with(:deleted_attribute, 'could not be restored to "abc"')
    mock_record_errors.should_receive(:add).with(:associations, 'could not be restored from the revision')
    
    mock_association_errors = mock(:errors)
    associated_record.stub!(:errors).and_return(mock_association_errors)
    mock_association_errors.should_receive(:add).with(:other, 'could not be restored to "val2"')
    
    associations_reflection = stub(:associations, :name => :associations, :macro => :has_many, :options => {:dependent => :destroy})
    TestRevisionableRecord.reflections = {:associations => associations_reflection}
    
    restored = revision.restore
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
    ActsAsRevisionable::RevisionRecord.delete_all
    ActsAsRevisionable::RevisionRecord.count.should == 0
    
    attributes = {'id' => 1, 'value' => rand(1000000)}
    original = TestRevisionableRecord.new(attributes)
    original.attributes['name'] = 'revision 1'
    ActsAsRevisionable::RevisionRecord.new(original).save!
    first_revision = ActsAsRevisionable::RevisionRecord.find(:first)
    original.attributes['name'] = 'revision 2'
    ActsAsRevisionable::RevisionRecord.new(original).save!
    original.attributes['name'] = 'revision 3'
    ActsAsRevisionable::RevisionRecord.new(original).save!
    ActsAsRevisionable::RevisionRecord.count.should == 3
    
    record = ActsAsRevisionable::RevisionRecord.find_revision(TestRevisionableRecord, 1, 1).restore
    record.class.should == TestRevisionableRecord
    record.id.should == 1
    record.attributes.should == attributes.merge('name' => 'revision 1')
    
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, 1, :limit => 2)
    ActsAsRevisionable::RevisionRecord.count.should == 2
    ActsAsRevisionable::RevisionRecord.find_by_id(first_revision.id).should == nil
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, 1, :limit => 0, :minimum_age => 1.week)
    ActsAsRevisionable::RevisionRecord.count.should == 2
    ActsAsRevisionable::RevisionRecord.truncate_revisions(TestRevisionableRecord, 1, :limit => 0)
    ActsAsRevisionable::RevisionRecord.count.should == 0
  end
  
end
