require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/../init.rb')

describe "ActsAsRevisionable" do
  
  class TestRevisionableModel
    include ActsAsRevisionable
    
    def update
      really_update
    end
    
    def really_update
    end
    
    def self.has_many (name, options)
      @associations ||= {}
      @associations[name] = options
    end
    
    def self.associations
      @associations
    end
    
    acts_as_revisionable :limit => 10, :associations => [:one, {:two => :two_1, :three => [:three_1, :three_2]}, {:four => :four_1}]
  end
  
  it "should be able to inject revisionable behavior onto ActiveRecord::Base" do
    ActiveRecord::Base.included_modules.should include(ActsAsRevisionable)
  end
  
  it "should add as has_many :record_revisions association" do
    TestRevisionableModel.associations[:revision_records].should == {:as => :revisionable, :dependent => :destroy, :order=>"revision DESC"}
  end
  
  it "should parse the revisionable associations" do
    TestRevisionableModel.revisionable_associations.should == {:one => true, :two => {:two_1 => true}, :three => {:three_1 => true, :three_2 => true}, :four => {:four_1 => true}}
  end
  
  it "should be able to create a revision record" do
    record = TestRevisionableModel.new
    revision = mock(:revision)
    RevisionRecord.should_receive(:new).with(record).and_return(revision)
    revision.should_receive(:save!)
    record.create_revision!.should == revision
  end
  
  it "should create a revision entry when a model is updated" do
    record = TestRevisionableModel.new
    record.stub!(:id).and_return(1)
    read_only_record = TestRevisionableModel.new
    TestRevisionableModel.should_receive(:find).with(1, :readonly => true).and_return(read_only_record)
    revision = mock(:revision)
    RevisionRecord.should_receive(:transaction).and_yield
    read_only_record.should_receive(:create_revision!)
    record.should_receive(:truncate_revisions!).with(:limit => 10, :minimum_age => nil)
    record.should_receive(:really_update).and_return(:retval)
    record.update.should == :retval
  end
  
  it "should not create a revision entry if revisioning is disabled" do
    record = TestRevisionableModel.new
    TestRevisionableModel.should_not_receive(:find)
    RevisionRecord.should_not_receive(:transaction)
    record.should_not_receive(:create_revision!)
    record.should_not_receive(:truncate_revisions!)
    record.should_receive(:really_update).and_return(:retval)
    record.disable_revisioning do
      record.update.should == :retval
    end
  end
  
  it "should truncate the revisions" do
    record = TestRevisionableModel.new
    record.stub!(:id).and_return(1)
    RevisionRecord.should_receive(:truncate_revisions).with(TestRevisionableModel, 1, {:limit => 20, :minimum_age => 2.weeks})
    record.truncate_revisions!(:limit => 20, :minimum_age => 2.weeks)
  end
  
  it "should be able to restore a revision by id and revision" do
    revision = mock(:revision)
    record = mock(:record)
    RevisionRecord.should_receive(:find_revision).with(TestRevisionableModel, 1, 5).and_return(revision)
    revision.should_receive(:restore).and_return(record)
    TestRevisionableModel.restore_revision(1, 5).should == record
  end
  
end
