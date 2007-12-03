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
    #   :associations => :tags, {:comments => [:ratings]}
    def acts_as_revisionable (options = {})
      write_inheritable_attribute(:acts_as_revisionable_options, options)
      class_inheritable_reader(:acts_as_revisionable_options)
      extend ClassMethods
      include InstanceMethods
      has_many :revision_records, :as => :revisionable, :dependent => :destroy, :order => 'revision DESC'
      alias_method_chain :update, :revision
    end
  end
  
  module ClassMethods
    # Restore a revision for a record with a particular id.
    def restore_revision (id, revision)
      revision = RevisionRecord.find_revision(self, id, revision)
      return revision.restore if revision
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
  end
  
  module InstanceMethods
    # Restore a revision of the record and return it. The record is not saved to the database. If there
    # is a problem restoring values, errors will be added to the record.
    def restore_revision (revision)
      self.class.restore_revision(self.id, revision)
    end
    
    # This is the update call that overrides the default update method.
    def update_with_revision
      return update_without_revision if @update_revisions_disabled
      RevisionRecord.transaction do
        read_only = self.class.find(self.id, :readonly => true)
        read_only.create_revision! if read_only
        truncate_revisions!(:limit => acts_as_revisionable_options[:limit], :minimum_age => acts_as_revisionable_options[:minimum_age])
        return update_without_revision
      end
    end
    
    # Create a revision record based on this record and save it to the database.
    def create_revision!
      revision = RevisionRecord.new(self)
      revision.save!
      return revision
    end
    
    # Truncate the number of revisions kept for this record. Available options are :limit and :minimum_age.
    def truncate_revisions! (options)
      RevisionRecord.truncate_revisions(self.class, self.id, options)
    end
    
    # Disable the revisioning behavior inside of a block passed to the method.
    def disable_revisioning
      save_val = @update_revisions_disabled
      begin
        @update_revisions_disabled = true
        yield if block_given?
      ensure
        @update_revisions_disabled = save_val
      end
    end
  end
  
end
