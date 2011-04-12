require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "ActsAsRevisionable Full Test" do

  before(:all) do
    ActsAsRevisionable::Test.create_database

    ActiveRecord::Base.store_full_sti_class = true

    class RevisionableTestSubThing < ActiveRecord::Base
      connection.create_table(:revisionable_test_sub_things) do |t|
        t.column :name, :string
        t.column :revisionable_test_many_thing_id, :integer
      end unless table_exists?
    end

    class RevisionableTestManyThing < ActiveRecord::Base
      connection.create_table(:revisionable_test_many_things) do |t|
        t.column :name, :string
        t.column :revisionable_test_model_id, :integer
      end unless table_exists?

      has_many :sub_things, :class_name => 'RevisionableTestSubThing'
    end

    class RevisionableTestManyOtherThing < ActiveRecord::Base
      connection.create_table(:revisionable_test_many_other_things) do |t|
        t.column :name, :string
        t.column :revisionable_test_model_id, :integer
      end unless table_exists?
    end

    class RevisionableTestCompositeKeyThing < ActiveRecord::Base
      connection.create_table(:revisionable_test_composite_key_things, :id => false) do |t|
        t.column :name, :string
        t.column :revisionable_test_model_id, :integer
        t.column :other_id, :integer
      end unless table_exists?
      set_primary_keys :revisionable_test_model_id, :other_id
      belongs_to :revisionable_test_model
    end

    class RevisionableTestOneThing < ActiveRecord::Base
      connection.create_table(:revisionable_test_one_things) do |t|
        t.column :name, :string
        t.column :revisionable_test_model_id, :integer
      end unless table_exists?
    end

    class NonRevisionableTestModel < ActiveRecord::Base
      connection.create_table(:non_revisionable_test_models) do |t|
        t.column :name, :string
      end unless table_exists?
    end

    class NonRevisionableTestModelsRevisionableTestModel < ActiveRecord::Base
      connection.create_table(:non_revisionable_test_models_revisionable_test_models, :id => false) do |t|
        t.column :non_revisionable_test_model_id, :integer
        t.column :revisionable_test_model_id, :integer
      end unless table_exists?
    end

    class RevisionableTestModel < ActiveRecord::Base
      connection.create_table(:revisionable_test_models) do |t|
        t.column :name, :string
        t.column :secret, :integer
      end unless table_exists?

      has_many :many_things, :class_name => 'RevisionableTestManyThing', :dependent => :destroy
      has_many :many_other_things, :class_name => 'RevisionableTestManyOtherThing', :dependent => :destroy
      has_one :one_thing, :class_name => 'RevisionableTestOneThing'
      has_and_belongs_to_many :non_revisionable_test_models
      has_many :composite_key_things, :class_name => 'RevisionableTestCompositeKeyThing', :dependent => :destroy

      attr_protected :secret

      acts_as_revisionable :limit => 3, :associations => [:one_thing, :non_revisionable_test_models, {:many_things => :sub_things}, :composite_key_things]

      def set_secret(val)
        self.secret = val
      end

      private

      def secret=(val)
        self[:secret] = val
      end
    end

    module ActsAsRevisionable
      class RevisionableNamespaceModel < ActiveRecord::Base
        connection.create_table(:revisionable_namespace_models) do |t|
          t.column :name, :string
          t.column :type_name, :string
        end unless table_exists?

        set_inheritance_column :type_name
        acts_as_revisionable :dependent => :keep, :on_destroy => true, :encoding => :xml
        self.store_full_sti_class = false
      end

      class RevisionableSubclassModel < RevisionableNamespaceModel
      end
    end
  end

  after :all do
    ActsAsRevisionable::Test.delete_database
  end

  before :each do
    RevisionableTestModel.delete_all
    RevisionableTestManyThing.delete_all
    RevisionableTestManyOtherThing.delete_all
    RevisionableTestSubThing.delete_all
    RevisionableTestOneThing.delete_all
    NonRevisionableTestModelsRevisionableTestModel.delete_all
    NonRevisionableTestModel.delete_all
    ActsAsRevisionable::RevisionRecord.delete_all
    ActsAsRevisionable::RevisionableNamespaceModel.delete_all
  end

  it "should only store revisions in a store revision block if :on_update is not true" do
    model = RevisionableTestModel.new(:name => 'test')
    model.set_secret(1234)
    model.save!
    ActsAsRevisionable::RevisionRecord.count.should == 0
    model.name = 'new_name'
    model.save!
    ActsAsRevisionable::RevisionRecord.count.should == 0
  end

  it "should not save a revision if an update raises an exception" do
    model = RevisionableTestModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 0

    model.should_receive(:update).and_raise("update failed")
    model.name = 'new_name'
    begin
      model.store_revision do
        ActsAsRevisionable::RevisionRecord.count.should == 1
        model.save
      end
    rescue
    end
    ActsAsRevisionable::RevisionRecord.count.should == 0
  end

  it "should not save a revision if an update fails with errors" do
    model = RevisionableTestModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 0

    model.name = 'new_name'
    model.store_revision do
      ActsAsRevisionable::RevisionRecord.count.should == 1
      model.save!
      model.errors.add(:name, "isn't right")
    end
    ActsAsRevisionable::RevisionRecord.count.should == 0
  end

  it "should restore a record without associations" do
    model = RevisionableTestModel.new(:name => 'test')
    model.set_secret(1234)
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 0

    model.name = 'new_name'
    model.set_secret(5678)
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
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
    ActsAsRevisionable::RevisionRecord.count.should == 2
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
    ActsAsRevisionable::RevisionRecord.count.should == 0

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
    ActsAsRevisionable::RevisionRecord.count.should == 1
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
    model.many_things(true).collect{|t| t.name}.sort.should == ['many_thing_3', 'new_many_thing_1']
    model.many_things.detect{|t| t.name == 'new_many_thing_1'}.sub_things.collect{|t| t.name}.sort.should == ['new_sub_thing_1', 'sub_thing_3']
    model.many_other_things.collect{|t| t.name}.sort.should == ['many_other_thing_3', 'new_many_other_thing_1']

    model.restore_revision!(1)
    RevisionableTestModel.count.should == 1
    RevisionableTestManyThing.count.should == 2
    RevisionableTestSubThing.count.should == 3
    RevisionableTestManyOtherThing.count.should == 2
    ActsAsRevisionable::RevisionRecord.count.should == 2
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
    ActsAsRevisionable::RevisionRecord.count.should == 0
    RevisionableTestOneThing.count.should == 1
  
    model.name = 'new_name'
    model.one_thing.name = 'new_other'
    model.store_revision do
      model.one_thing.save!
      model.save!
    end
  
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    model.one_thing.name.should == 'new_other'
  
    # restore to memory
    restored = model.restore_revision(1)
    restored.name.should == 'test'
    restored.one_thing.name.should == 'other'
    restored.one_thing.id.should == model.one_thing.id
  
    # make sure restore to memory didn't affect the database
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
    model.name.should == 'new_name'
    model.one_thing(true).name.should == 'new_other'
  
    model.restore_revision!(1)
    RevisionableTestModel.count.should == 1
    RevisionableTestOneThing.count.should == 1
    ActsAsRevisionable::RevisionRecord.count.should == 2
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
    ActsAsRevisionable::RevisionRecord.count.should == 0
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
    ActsAsRevisionable::RevisionRecord.count.should == 1
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
    model.non_revisionable_test_models(true).collect{|r| r.name}.sort.should == ['111', '333']
  
    model.restore_revision!(1)
    NonRevisionableTestModelsRevisionableTestModel.count.should == 2
    RevisionableTestModel.count.should == 1
    NonRevisionableTestModel.count.should == 3
    ActsAsRevisionable::RevisionRecord.count.should == 2
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
    ActsAsRevisionable::RevisionRecord.count.should == 0
  
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
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
    ActsAsRevisionable::RevisionRecord.count.should == 0
  
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
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
    ActsAsRevisionable::RevisionRecord.count.should == 0
  
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
    model.name.should == 'new_name'
  
    model.destroy
    ActsAsRevisionable::RevisionRecord.count.should == 0
  end
  
  it "should not destroy revisions if :dependent => :keep was specified" do
    model = ActsAsRevisionable::RevisionableSubclassModel.new(:name => 'test')
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 0
  
    model.name = 'new_name'
    model.store_revision do
      model.save!
    end
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
    model.name.should == 'new_name'
  
    # Destroy adds a revision in this model
    model.destroy
    ActsAsRevisionable::RevisionRecord.count.should == 2
  end
  
  it "should handle composite primary keys" do
    thing_1 = RevisionableTestCompositeKeyThing.new(:name => 'thing_1')
    thing_1.other_id = 1
    thing_2 = RevisionableTestCompositeKeyThing.new(:name => 'thing_2')
    thing_2.other_id = 2
    thing_3 = RevisionableTestCompositeKeyThing.new(:name => 'thing_3')
    thing_3.other_id = 3
  
    model = RevisionableTestModel.new(:name => 'test')
    model.composite_key_things << thing_1
    model.composite_key_things << thing_2
    model.save!
    model.reload
    RevisionableTestCompositeKeyThing.count.should == 2
    ActsAsRevisionable::RevisionRecord.count.should == 0
  
    model.store_revision do
      thing_1 = model.composite_key_things.detect{|t| t.name == 'thing_1'}
      thing_1.name = 'new_thing_1'
      thing_2 = model.composite_key_things.detect{|t| t.name == 'thing_2'}
      model.composite_key_things.delete(thing_2)
      model.composite_key_things << thing_3
      model.save!
      thing_1.save!
    end
  
    model.reload
    ActsAsRevisionable::RevisionRecord.count.should == 1
    RevisionableTestCompositeKeyThing.count.should == 2
    model.composite_key_things.collect{|t| t.name}.sort.should == ['new_thing_1', 'thing_3']
  
    # restore to memory
    restored = model.restore_revision(1)
    restored.composite_key_things.collect{|t| t.name}.sort.should == ['thing_1', 'thing_2']
    restored.valid?.should == true
  
    # make sure the restore to memory didn't affect the database
    model.reload
    model.composite_key_things(true).collect{|t| t.name}.sort.should == ['new_thing_1', 'thing_3']
    RevisionableTestCompositeKeyThing.count.should == 2
  
    model.restore_revision!(1)
    RevisionableTestModel.count.should == 1
    RevisionableTestCompositeKeyThing.count.should == 3
    restored_model = RevisionableTestModel.find(model.id)
    restored_model.name.should == 'test'
    restored.composite_key_things.collect{|t| t.name}.sort.should == ['thing_1', 'thing_2']
  end
  
  it "should restore a deleted record" do
    model = ActsAsRevisionable::RevisionableNamespaceModel.new(:name => 'test')
    model.save!
    model.store_revision do
      model.name = "new name"
      model.save!
    end
    model.destroy
    ActsAsRevisionable::RevisionRecord.count.should == 2
    
    model.restore_revision!(1)
  end
end
