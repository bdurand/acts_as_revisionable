require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/../init.rb')

describe "ActsAsRevisionable" do
  
  class TestRevisionableModel
    include ActsAsRevisionable
    
    attr_accessor :id
    
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
    
    private :update
    
    acts_as_revisionable :limit => 10, :on_update => true, :associations => [:one, {:two => :two_1, :three => [:three_1, :three_2]}, {:four => :four_1}]
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
  
  it "should handle storing revisions in a block" do
    record = TestRevisionableModel.new
    record.id = 1
    record.stub!(:new_record?).and_return(nil)
  end
  
  it "should not store revisions for a new record" do
    record = TestRevisionableModel.new
    record.stub!(:new_record?).and_return(true)
  end
  
  it "should handle storing revisions only if update is called in a block" do
    record = TestRevisionableModel.new
    record.id = 1
    record.stub!(:new_record?).and_return(nil)
    record.stub!(:errors).and_return([])
    read_only_record = TestRevisionableModel.new
    TestRevisionableModel.should_receive(:find).with(1, :readonly => true).and_return(read_only_record)
    revision = mock(:revision)
    RevisionRecord.should_receive(:transaction).and_yield
    read_only_record.should_receive(:create_revision!).and_return(revision)
    record.should_receive(:truncate_revisions!).with()
    record.should_receive(:really_update)
    
    record.store_revision do
      record.send(:update)
    end
  end
  
  it "should delete a revision if the update fails" do
    record = TestRevisionableModel.new
    record.id = 1
    record.stub!(:new_record?).and_return(nil)
    record.stub!(:errors).and_return([])
    read_only_record = TestRevisionableModel.new
    TestRevisionableModel.should_receive(:find).with(1, :readonly => true).and_return(read_only_record)
    revision = mock(:revision)
    RevisionRecord.should_receive(:transaction).and_yield
    read_only_record.should_receive(:create_revision!).and_return(revision)
    record.should_receive(:truncate_revisions!).with()
    record.should_receive(:update).and_raise("update failed")
    revision.should_receive(:destroy)
    
    record.store_revision do
      record.send(:update) rescue nil
    end
  end
  
  it "should not error on deleting a revision if the update fails" do
    record = TestRevisionableModel.new
    record.id = 1
    record.stub!(:new_record?).and_return(nil)
    record.stub!(:errors).and_return([:error])
    read_only_record = TestRevisionableModel.new
    TestRevisionableModel.should_receive(:find).with(1, :readonly => true).and_return(read_only_record)
    revision = mock(:revision)
    RevisionRecord.should_receive(:transaction).and_yield
    read_only_record.should_receive(:create_revision!).and_return(revision)
    record.should_receive(:truncate_revisions!).with()
    record.should_receive(:update).and_raise("update failed")
    revision.should_receive(:destroy).and_raise("destroy failed")
    
    record.store_revision do
      record.send(:update) rescue nil
    end
  end
  
  it "should be able to create a revision record" do
    record = TestRevisionableModel.new
    revision = mock(:revision)
    RevisionRecord.should_receive(:new).with(record).and_return(revision)
    revision.should_receive(:save!)
    record.create_revision!.should == revision
  end
  
  it "should create a revision entry when a model is updated if :on_update is true" do
    record = TestRevisionableModel.new
    record.should_receive(:store_revision).and_yield
    record.should_receive(:really_update).and_return(:retval)
    record.send(:update).should == :retval
  end
  
  it "should not create a revision entry when a model is updated if :on_update is true" do
    record = TestRevisionableModel.new
    TestRevisionableModel.stub!(:acts_as_revisionable_options).and_return({})
    record.should_not_receive(:store_revision)
    record.should_receive(:really_update).and_return(:retval)
    record.send(:update).should == :retval
  end
  
  it "should not create a revision entry if revisioning is disabled" do
    record = TestRevisionableModel.new
    record.stub!(:new_record?).and_return(nil)
    TestRevisionableModel.should_not_receive(:find)
    RevisionRecord.should_not_receive(:transaction)
    record.should_not_receive(:create_revision!)
    record.should_not_receive(:truncate_revisions!)
    record.should_receive(:update)
    
    record.disable_revisioning do
      record.store_revision do
        record.send(:update)
      end
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
  
  it "should be able to restore a revision by id and revision and save it" do
    record = mock(:record)
    TestRevisionableModel.should_receive(:restore_revision).with(1, 5).and_return(record)
    record.should_receive(:store_revision).and_yield
    TestRevisionableModel.should_receive(:save_restorable_associations).with(record, TestRevisionableModel.revisionable_associations)
    TestRevisionableModel.restore_revision!(1, 5).should == record
  end
  
end
