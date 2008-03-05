module ActsAsRevisionable
  
  def self.included (base)
    base.extend(ActsMethods)
  end
  
  module ActsMethods
    # Calling acts_as_revisionable will inject the revisionable behavior into the class. Specifying a :limit option
    # will limit the number of revisions that are kept per record. Specifying :minimum_age will ensure that revisions are
    # kept for at least a certain amount of time (i.e. 2.weeks). Associations to be revisioned can be specified with
    # the :associations option as an array of association names. To specify associations of associations, use a hash
    # for that association with the association name as the key and the value as an array of sub associations.
    # For instance, this declaration will revision :tags, :comments, as well as the :ratings association on :comments:
    #
    #   :associations => [:tags, {:comments => [:ratings]}]
    #
    # You can also pass an options of :on_update => true to automatically enable revisioning on every update.
    # Otherwise you will need to perform your updates in a store_revision block. The reason for this is so that
    # revisions for complex models with associations can be better controlled.
    #
    # A has_many :revision_records will also be added to the model for accessing the revisions.
    def acts_as_revisionable (options = {})
      write_inheritable_attribute(:acts_as_revisionable_options, options)
      class_inheritable_reader(:acts_as_revisionable_options)
      extend ClassMethods
      include InstanceMethods
      has_many :revision_records, :as => :revisionable, :dependent => :destroy, :order => 'revision DESC'
      alias_method_chain :update, :revision if options[:on_update]
    end
  end
  
  module ClassMethods
    # Load a revision for a record with a particular id. If this revision has association it
    # will not delete associated records added since the revision was added if you save it.
    # If you want to save a revision with associations properly, use restore_revision!
    def restore_revision (id, revision)
      revision = RevisionRecord.find_revision(self, id, revision)
      return revision.restore if revision
    end

    # Load a revision for a record with a particular id and save it to the database. You should
    # always use this method to save a revision if it has associations.
    def restore_revision! (id, revision)
      record = restore_revision(id, revision)
      if record
        record.store_revision do
          save_restorable_associations(record, revisionable_associations)
        end
      end
      return record
    end
    
    # Returns a hash structure used to identify the revisioned associations.
    def revisionable_associations (options = acts_as_revisionable_options[:associations])
      return nil unless options
      options = [options] unless options.kind_of?(Array)
      associations = {}
      options.each do |association|
        if association.kind_of?(Symbol)
          associations[association] = true
        elsif association.kind_of?(Hash)
          association.each_pair do |key, value|
            associations[key] = revisionable_associations(value)
          end
        end
      end
      return associations
    end
    
    private
    
    def save_restorable_associations (record, associations)
      record.class.transaction do
        if associations.kind_of?(Hash)
          associations.each_pair do |association, sub_associations|
            associated_records = record.send(association)
            reflection = record.class.reflections[association].macro
            
            if reflection == :has_and_belongs_to_many
              associated_records = associated_records.collect{|r| r}
              record.send(association, true).clear
              associated_records.each do |assoc_record|
                record.send(association) << assoc_record
              end
            else
              if reflection == :has_many
                existing = associated_records.find(:all)
                existing.each do |existing_association|
                  associated_records.delete(existing_association) unless associated_records.include?(existing_association)
                end
              end
            
              associated_records = [associated_records] unless associated_records.kind_of?(Array)
              associated_records.each do |associated_record|
                save_restorable_associations(associated_record, sub_associations) if associated_record
              end
            end
          end
        end
        record.save! unless record.new_record?
      end
    end
  end
  
  module InstanceMethods
    # Restore a revision of the record and return it. The record is not saved to the database. If there
    # is a problem restoring values, errors will be added to the record.
    def restore_revision (revision)
      self.class.restore_revision(self.id, revision)
    end
    
    # Restore a revision of the record and save it along with restored associations.
    def restore_revision! (revision)
      self.class.restore_revision!(self.id, revision)
    end
    
    # Call this method to implement revisioning. The object changes should happen inside the block.
    def store_revision
      if new_record? or @revisions_disabled
        return yield
      else
        retval = nil
        revision = nil
        begin
          RevisionRecord.transaction do
            read_only = self.class.find(self.id, :readonly => true) rescue nil
            if read_only
              revision = read_only.create_revision!
              truncate_revisions!
            end
            
            disable_revisioning do
              retval = yield
            end
            
            raise 'rollback_revision' unless errors.empty?
          end
        rescue => e
          # In case the database doesn't support transactions
          if revision
            revision.destroy rescue nil
          end
          raise e unless e.message == 'rollback_revision'
        end
        return retval
      end
    end
    
    # Create a revision record based on this record and save it to the database.
    def create_revision!
      revision = RevisionRecord.new(self)
      revision.save!
      return revision
    end
    
    # Truncate the number of revisions kept for this record. Available options are :limit and :minimum_age.
    def truncate_revisions! (options = nil)
      options = {:limit => acts_as_revisionable_options[:limit], :minimum_age => acts_as_revisionable_options[:minimum_age]} unless options
      RevisionRecord.truncate_revisions(self.class, self.id, options)
    end
    
    # Disable the revisioning behavior inside of a block passed to the method.
    def disable_revisioning
      save_val = @revisions_disabled
      retval = nil
      begin
        @revisions_disabled = true
        retval = yield if block_given?
      ensure
        @revisions_disabled = save_val
      end
      return retval
    end
    
    private
    
    # This is the update call that overrides the default update method.
    def update_with_revision
      store_revision do
        update_without_revision
      end
    end
  end
  
end
