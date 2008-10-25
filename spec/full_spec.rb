require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "ActsAsRevisionable Full Test" do
  
  before(:all) do
    ActiveRecord::Migration.suppress_messages do
      class RevisionableTestSubThing < ActiveRecord::Base
        ActiveRecord::Migration.create_table(:revisionable_test_sub_things) do |t|
          t.column :name, :string
          t.column :revisionable_test_many_thing_id, :integer
        end unless table_exists?
      end
  
      class RevisionableTestManyThing < ActiveRecord::Base
        ActiveRecord::Migration.create_table(:revisionable_test_many_things) do |t|
          t.column :name, :string
          t.column :revisionable_test_model_id, :integer
        end unless table_exists?
      
        has_many :sub_things, :class_name => 'RevisionableTestSubThing'
      end
  
      class RevisionableTestManyOtherThing < ActiveRecord::Base
        ActiveRecord::Migration.create_table(:revisionable_test_many_other_things) do |t|
          t.column :name, :string
          t.column :revisionable_test_model_id, :integer
        end unless table_exists?
      end
  
      class RevisionableTestOneThing < ActiveRecord::Base
        ActiveRecord::Migration.create_table(:revisionable_test_one_things) do |t|
          t.column :name, :string
          t.column :revisionable_test_model_id, :integer
        end unless table_exists?
      end
  
      class NonRevisionableTestModel < ActiveRecord::Base
        ActiveRecord::Migration.create_table(:non_revisionable_test_models) do |t|
          t.column :name, :string
        end unless table_exists?
      end
      
      class NonRevisionableTestModelsRevisionableTestModel < ActiveRecord::Base
        ActiveRecord::Migration.create_table(:non_revisionable_test_models_revisionable_test_models, :id => false) do |t|
          t.column :non_revisionable_test_model_id, :integer
          t.column :revisionable_test_model_id, :integer
        end unless table_exists?
      end
  
      class RevisionableTestModel < ActiveRecord::Base
        ActiveRecord::Migration.create_table(:revisionable_test_models) do |t|
          t.column :name, :string
          t.column :secret, :integer
        end unless table_exists?
      
        has_many :many_things, :class_name => 'RevisionableTestManyThing', :dependent => :destroy
        has_many :many_other_things, :class_name => 'RevisionableTestManyOtherThing', :dependent => :destroy
        has_one :one_thing, :class_name => 'RevisionableTestOneThing'
        has_and_belongs_to_many :non_revisionable_test_models
    
        attr_protected :secret
        
        acts_as_revisionable :limit => 3, :associations => [:one_thing, :non_revisionable_test_models, {:many_things => :sub_things}]
        
        def set_secret (val)
          self.secret = val
        end
        
        private
        
        def secret= (val)
          self[:secret] = val
        end
      end

      module ActsAsRevisionable
        class RevisionableNamespaceModel < ActiveRecord::Base
          ActiveRecord::Migration.create_table(:revisionable_namespace_models) do |t|
            t.column :name, :string
            t.column :type_name, :string
          end unless table_exists?
          
          set_inheritance_column :type_name
          acts_as_revisionable :dependent => :keep, :encoding => :xml
        end
        
        class RevisionableSubclassModel < RevisionableNamespaceModel
        end
      end
    end
  end
  
  after(:all) do
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Migration.drop_table(:revisionable_test_models) if RevisionableTestModel.table_exists?
      ActiveRecord::Migration.drop_table(:revisionable_test_many_things) if RevisionableTestManyThing.table_exists?
      ActiveRecord::Migration.drop_table(:revisionable_test_many_other_things) if RevisionableTestManyOtherThing.table_exists?
      ActiveRecord::Migration.drop_table(:revisionable_test_sub_things) if RevisionableTestSubThing.table_exists?
      ActiveRecord::Migration.drop_table(:revisionable_test_one_things) if RevisionableTestOneThing.table_exists?
      ActiveRecord::Migration.drop_table(:non_revisionable_test_models_revisionable_test_models) if NonRevisionableTestModelsRevisionableTestModel.table_exists?
      ActiveRecord::Migration.drop_table(:non_revisionable_test_models) if NonRevisionableTestModel.table_exists?
      ActiveRecord::Migration.drop_table(:revisionable_namespace_models) if ActsAsRevisionable::RevisionableNamespaceModel.table_exists?
    end
  end
  
  before(:each) do
    RevisionableTestModel.delete_all
    RevisionableTestManyThing.delete_all
    RevisionableTestManyOtherThing.delete_all
    RevisionableTestSubThing.delete_all
    RevisionableTestOneThing.delete_all
    NonRevisionableTestModelsRevisionableTestModel.delete_all
    NonRevisionableTestModel.delete_all
    RevisionRecord.delete_all
    ActsAsRevisionable::RevisionableNamespaceModel.delete_all
  end
  
  it "should only store revisions in a store revision block if :on_update is not true" do
    model = RevisionableTestModel.new(:name => 'test')
    model.set_secret(1234)
    model.save!
    RevisionRecord.count.should == 0
    model.name = 'new_name'
    model.save!
    RevisionRecord.count.should == 0
  end
  
  it "should not save a revision if an update raises an exception" do
    model = RevisionableTestModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    
    model.should_receive(:update).and_raise("update failed")
    model.name = 'new_name'
    begin
      model.store_revision do
        RevisionRecord.count.should == 1
        model.update
      end
    rescue
    end
    RevisionRecord.count.should == 0
  end
  
  it "should not save a revision if an update fails with errors" do
    model = RevisionableTestModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    
    model.name = 'new_name'
    model.store_revision do
      RevisionRecord.count.should == 1
      model.save!
      model.errors.add(:name, "isn't right")
    end
    RevisionRecord.count.should == 0
  end
  
  it "should restore a record without associations" do
    model = RevisionableTestModel.new(:name => 'test')
    model.set_secret(1234)
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    
    model.name = 'new_name'
    model.set_secret(5678)
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    model.secret.should == 5678
    
    restored = model.restore_revision(1)
    restored.name.should == 'test'
    restored.secret.should == 1234
    restored.id.should == model.id
    
    restored.store_revision do
      restored.save!
    end
    RevisionableTestModel.count.should == 1
    RevisionRecord.count.should == 2
    restored_model = RevisionableTestModel.find(model.id)
    restored_model.name.should == restored.name
    restored_model.secret.should == restored.secret
  end
  
  it "should restore a record with has_many associations" do
    many_thing_1 = RevisionableTestManyThing.new(:name => 'many_thing_1')
    many_thing_1.sub_things.build(:name => 'sub_thing_1')
    many_thing_1.sub_things.build(:name => 'sub_thing_2')
    
    model = RevisionableTestModel.new(:name => 'test')
    model.many_things << many_thing_1
    model.many_things.build(:name => 'many_thing_2')
    model.many_other_things.build(:name => 'many_other_thing_1')
    model.many_other_things.build(:name => 'many_other_thing_2')
    model.save!
    model.reload
    RevisionableTestManyThing.count.should == 2
    RevisionableTestSubThing.count.should == 2
    RevisionableTestManyOtherThing.count.should == 2
    RevisionRecord.count.should == 0
    
    model.store_revision do
      model.name = 'new_name'
      many_thing_1 = model.many_things.detect{|t| t.name == 'many_thing_1'}
      many_thing_1.name = 'new_many_thing_1'
      sub_thing_1 = many_thing_1.sub_things.detect{|t| t.name == 'sub_thing_1'}
      sub_thing_1.name = 'new_sub_thing_1'
      sub_thing_2 = many_thing_1.sub_things.detect{|t| t.name == 'sub_thing_2'}
      many_thing_1.sub_things.build(:name => 'sub_thing_3')
      many_thing_1.sub_things.delete(sub_thing_2)
      many_thing_2 = model.many_things.detect{|t| t.name == 'many_thing_2'}
      model.many_things.delete(many_thing_2)
      model.many_things.build(:name => 'many_thing_3')
      many_other_thing_1 = model.many_other_things.detect{|t| t.name == 'many_other_thing_1'}
      many_other_thing_1.name = 'new_many_other_thing_1'
      many_other_thing_2 = model.many_other_things.detect{|t| t.name == 'many_other_thing_2'}
      model.many_other_things.delete(many_other_thing_2)
      model.many_other_things.build(:name => 'many_other_thing_3')
      model.save!
      many_thing_1.save!
      sub_thing_1.save!
      many_other_thing_1.save!
    end
    
    model.reload
    RevisionRecord.count.should == 1
    RevisionableTestManyThing.count.should == 2
    RevisionableTestSubThing.count.should == 3
    RevisionableTestManyOtherThing.count.should == 2
    model.name.should == 'new_name'
    model.many_things.collect{|t| t.name}.sort.should == ['many_thing_3', 'new_many_thing_1']
    model.many_things.detect{|t| t.name == 'new_many_thing_1'}.sub_things.collect{|t| t.name}.sort.should == ['new_sub_thing_1', 'sub_thing_3']
    model.many_other_things.collect{|t| t.name}.sort.should == ['many_other_thing_3', 'new_many_other_thing_1']
    
    # restore to memory
    restored = model.restore_revision(1)
    restored.name.should == 'test'
    restored.id.should == model.id
    restored.many_things.collect{|t| t.name}.sort.should == ['many_thing_1', 'many_thing_2']
    restored.many_things.detect{|t| t.name == 'many_thing_1'}.sub_things.collect{|t| t.name}.sort.should == ['sub_thing_1', 'sub_thing_2']
    restored.many_other_things.collect{|t| t.name}.sort.should == ['many_other_thing_3', 'new_many_other_thing_1']
    restored.valid?.should == true
    
    # make the restore to memory didn't affect the database
    model.reload
    model.name.should == 'new_name'
    model.many_things.collect{|t| t.name}.sort.should == ['many_thing_3', 'new_many_thing_1']
    model.many_things.detect{|t| t.name == 'new_many_thing_1'}.sub_things.collect{|t| t.name}.sort.should == ['new_sub_thing_1', 'sub_thing_3']
    model.many_other_things.collect{|t| t.name}.sort.should == ['many_other_thing_3', 'new_many_other_thing_1']
    
    model.restore_revision!(1)
    RevisionableTestModel.count.should == 1
    RevisionableTestManyThing.count.should == 2
    RevisionableTestSubThing.count.should == 3
    RevisionableTestManyOtherThing.count.should == 2
    RevisionRecord.count.should == 2
    restored_model = RevisionableTestModel.find(model.id)
    restored_model.name.should == 'test'
    restored.many_things.collect{|t| t.name}.sort.should == ['many_thing_1', 'many_thing_2']
    restored.many_things.detect{|t| t.name == 'many_thing_1'}.sub_things.collect{|t| t.name}.sort.should == ['sub_thing_1', 'sub_thing_2']
    restored.many_things.detect{|t| t.name == 'many_thing_2'}.sub_things.collect{|t| t.name}.sort.should == []
    restored.many_other_things.collect{|t| t.name}.sort.should == ['many_other_thing_3', 'new_many_other_thing_1']
  end
  
  it "should restore a record with has_one associations" do
    model = RevisionableTestModel.new(:name => 'test')
    model.build_one_thing(:name => 'other')
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    RevisionableTestOneThing.count.should == 1
    
    model.name = 'new_name'
    model.one_thing.name = 'new_other'
    model.store_revision do
      model.one_thing.save!
      model.save!
    end
    
    model.reload
    RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    model.one_thing.name.should == 'new_other'
    
    # restore to memory
    restored = model.restore_revision(1)
    restored.name.should == 'test'
    restored.one_thing.name.should == 'other'
    restored.one_thing.id.should == model.one_thing.id
    
    # make sure restore to memory didn't affect the database
    model.reload
    RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    model.one_thing.name.should == 'new_other'
    
    model.restore_revision!(1)
    RevisionableTestModel.count.should == 1
    RevisionableTestOneThing.count.should == 1
    RevisionRecord.count.should == 2
    restored_model = RevisionableTestModel.find(model.id)
    restored_model.name.should == 'test'
    restored_model.one_thing.name.should == 'other'
    restored_model.one_thing.id.should == model.one_thing.id
  end
  
  it "should restore a record with has_and_belongs_to_many associations" do
    other_1 = NonRevisionableTestModel.create(:name => 'one')
    other_2 = NonRevisionableTestModel.create(:name => 'two')
    model = RevisionableTestModel.new(:name => 'test')
    model.non_revisionable_test_models = [other_1, other_2]
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    NonRevisionableTestModel.count.should == 2
    
    model.name = 'new_name'
    other_1.name = '111'
    other_3 = NonRevisionableTestModel.create(:name => '333')
    model.store_revision do
      model.non_revisionable_test_models = [other_1, other_3]
      other_1.save!
      model.save!
    end
    
    model.reload
    RevisionRecord.count.should == 1
    NonRevisionableTestModel.count.should == 3
    model.name.should == 'new_name'
    model.non_revisionable_test_models.collect{|r| r.name}.sort.should == ['111', '333']
    
    # restore to memory
    restored = model.restore_revision(1)
    restored.name.should == 'test'
    restored.non_revisionable_test_models.collect{|r| r.name}.sort.should == ['111', 'two']
    
    # make sure the restore to memory didn't affect the database
    model.reload
    model.name.should == 'new_name'
    model.non_revisionable_test_models.collect{|r| r.name}.sort.should == ['111', '333']
    
    model.restore_revision!(1)
    NonRevisionableTestModelsRevisionableTestModel.count.should == 2
    RevisionableTestModel.count.should == 1
    NonRevisionableTestModel.count.should == 3
    RevisionRecord.count.should == 2
    restored_model = RevisionableTestModel.find(model.id)
    restored_model.name.should == 'test'
    restored_model.non_revisionable_test_models.collect{|r| r.name}.sort.should == ['111', 'two']
  end
  
  it "should handle namespaces and single table inheritance" do
    model = ActsAsRevisionable::RevisionableNamespaceModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    
    restored = model.restore_revision(1)
    restored.class.should == ActsAsRevisionable::RevisionableNamespaceModel
    restored.name.should == 'test'
    restored.id.should == model.id
  end
  
  it "should handle single table inheritance" do
    model = ActsAsRevisionable::RevisionableSubclassModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    
    restored = model.restore_revision(1)
    restored.class.should == ActsAsRevisionable::RevisionableSubclassModel
    restored.name.should == 'test'
    restored.id.should == model.id
    restored.type_name.should == 'RevisionableSubclassModel'
  end
  
  it "should destroy revisions if :dependent => :keep was not specified" do
    model = RevisionableTestModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    
    model.destroy
    RevisionRecord.count.should == 0
  end
  
  it "should not destroy revisions if :dependent => :keep was specified" do
    model = ActsAsRevisionable::RevisionableSubclassModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 0
    
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    
    model.destroy
    RevisionRecord.count.should == 1
  end
  
end
