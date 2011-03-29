require 'zlib'
require 'yaml'

module ActsAsRevisionable
  class RevisionRecord < ActiveRecord::Base

    before_create :set_revision_number
    attr_reader :data_encoding

    set_table_name :revision_records

    class << self
      # Find a specific revision record.
      def find_revision (klass, id, revision)
        find(:first, :conditions => {:revisionable_type => klass.base_class.to_s, :revisionable_id => id, :revision => revision})
      end

      # Truncate the revisions for a record. Available options are :limit and :max_age.
      def truncate_revisions (revisionable_type, revisionable_id, options)
        return unless options[:limit] or options[:minimum_age]

        conditions = ['revisionable_type = ? AND revisionable_id = ?', revisionable_type.base_class.to_s, revisionable_id]
        if options[:minimum_age]
          conditions.first << ' AND created_at <= ?'
          conditions << options[:minimum_age].ago
        end

        start_deleting_revision = find(:first, :conditions => conditions, :order => 'revision DESC', :offset => options[:limit])
        if start_deleting_revision
          delete_all(['revisionable_type = ? AND revisionable_id = ? AND revision <= ?', revisionable_type.base_class.to_s, revisionable_id, start_deleting_revision.revision])
        end
      end

      def create_table
        connection.create_table :revision_records do |t|
          t.string :revisionable_type, :null => false, :limit => 100
          t.integer :revisionable_id, :null => false
          t.integer :revision, :null => false
          t.binary :data, :limit => (connection.adapter_name == "MySQL" ? 5.megabytes : nil)
          t.timestamp :created_at, :null => false
        end

        connection.add_index :revision_records, [:revisionable_type, :revisionable_id, :revision], :name => "revisionable", :unique => true
      end
    end

    # Create a revision record based on a record passed in. The attributes of the original record will
    # be serialized. If it uses the acts_as_revisionable behavior, associations will be revisioned as well.
    def initialize (record, encoding = :ruby)
      super({})
      @data_encoding = encoding
      self.revisionable_type = record.class.base_class.name
      self.revisionable_id = record.id
      associations = record.class.revisionable_associations if record.class.respond_to?(:revisionable_associations)
      self.data = Zlib::Deflate.deflate(serialize_hash(serialize_attributes(record, associations)))
    end

    # Returns the attributes that are saved in the revision.
    def revision_attributes
      return nil unless self.data
      uncompressed = Zlib::Inflate.inflate(self.data)
      deserialize_hash(uncompressed)
    end

    # Restore the revision to the original record. If any errors are encountered restoring attributes, they
    # will be added to the errors object of the restored record.
    def restore
      restore_class = self.revisionable_type.constantize

      # Check if we have a type field, if yes, assume single table inheritance and restore the actual class instead of the stored base class
      sti_type = self.revision_attributes[restore_class.inheritance_column]
      if sti_type
        begin
          if !restore_class.store_full_sti_class && !sti_type.start_with?("::")
            sti_type = "#{restore_class.parent.name}::#{sti_type}"
          end
          restore_class = sti_type.constantize
        rescue NameError => e
          raise e
          # Seems our assumption was wrong and we have no STI
        end
      end

      attrs, association_attrs = attributes_and_associations(restore_class, self.revision_attributes)

      record = restore_class.new
      attrs.each_pair do |key, value|
        begin
          record.send("#{key}=", value)
        rescue
          record.errors.add(key.to_sym, "could not be restored to #{value.inspect}")
        end
      end

      association_attrs.each_pair do |association, attribute_values|
        restore_association(record, association, attribute_values)
      end

      record.instance_variable_set(:@new_record, nil) if record.instance_variable_defined?(:@new_record)
      # ActiveRecord 3.0.2 and 3.0.3 used @persisted instead of @new_record
      record.instance_variable_set(:@persisted, true) if record.instance_variable_defined?(:@persisted)

      return record
    end

    private

    def serialize_hash (hash)
      encoding = data_encoding.blank? ? :ruby : data_encoding
      case encoding.to_sym
      when :yaml
        return YAML.dump(hash)
      when :xml
        return hash.to_xml(:root => 'revision')
      else
        return Marshal.dump(hash)
      end
    end

    def deserialize_hash (data)
      if data.starts_with?('---')
        return YAML.load(data)
      elsif data.starts_with?('<?xml')
        return Hash.from_xml(data)['revision']
      else
        return Marshal.load(data)
      end
    end

    def set_revision_number
      last_revision = self.class.maximum(:revision, :conditions => {:revisionable_type => self.revisionable_type, :revisionable_id => self.revisionable_id}) || 0
      self.revision = last_revision + 1
    end

    def serialize_attributes (record, revisionable_associations, already_serialized = {})
      return if already_serialized["#{record.class}.#{record.id}"]
      attrs = record.attributes.dup
      already_serialized["#{record.class}.#{record.id}"] = true

      if revisionable_associations.kind_of?(Hash)
        record.class.reflections.values.each do |association|
          if revisionable_associations[association.name]
            assoc_name = association.name.to_s
            if association.macro == :has_many
              attrs[assoc_name] = record.send(association.name).collect{|r| serialize_attributes(r, revisionable_associations[association.name], already_serialized)}
            elsif association.macro == :has_one
              associated = record.send(association.name)
              unless associated.nil?
                attrs[assoc_name] = serialize_attributes(associated, revisionable_associations[association.name], already_serialized)
              else
                attrs[assoc_name] = nil
              end
            elsif association.macro == :has_and_belongs_to_many
              attrs[assoc_name] = record.send("#{association.name.to_s.singularize}_ids".to_sym)
            end
          end
        end
      end

      return attrs
    end

    def attributes_and_associations (klass, hash)
      attrs = {}
      association_attrs = {}

      if hash
        hash.each_pair do |key, value|
          if klass.reflections.include?(key.to_sym)
            association_attrs[key] = value
          else
            attrs[key] = value
          end
        end
      end

      return [attrs, association_attrs]
    end

    def restore_association (record, association, association_attributes)
      association = association.to_sym
      reflection = record.class.reflections[association]
      associated_record = nil
      exists = false

      begin
        if reflection.macro == :has_many
          if association_attributes.kind_of?(Array)
            record.send("#{association}=".to_sym, [])
            association_attributes.each do |attrs|
              restore_association(record, association, attrs)
            end
          else
            associated_record = record.send(association).build
            associated_record.class.primary_key.each do |key|
              associated_record.send("#{key.to_s}=", association_attributes[key.to_s])
            end
            exists = associated_record.class.find(associated_record.send(associated_record.class.primary_key)) rescue nil
          end
        elsif reflection.macro == :has_one
          associated_record = reflection.klass.new
          associated_record.class.primary_key.each do |key|
            associated_record.send("#{key.to_s}=", association_attributes[key.to_s])
          end
          exists = associated_record.class.find(associated_record.send(associated_record.class.primary_key)) rescue nil
          record.send("#{association}=", associated_record)
        elsif reflection.macro == :has_and_belongs_to_many
          record.send("#{association.to_s.singularize}_ids=", association_attributes)
        end
      rescue => e
        record.errors.add(association, "could not be restored from the revision: #{e.message}")
      end

      return unless associated_record

      attrs, association_attrs = attributes_and_associations(associated_record.class, association_attributes)
      attrs.each_pair do |key, value|
        begin
          associated_record.send("#{key}=", value)
        rescue
          associated_record.errors.add(key.to_sym, "could not be restored to #{value.inspect}")
          record.errors.add(association, "could not be restored from the revision") unless record.errors[association]
        end
      end

      association_attrs.each_pair do |key, values|
        restore_association(associated_record, key, values)
      end

      if exists
        associated_record.instance_variable_set(:@new_record, nil) if associated_record.instance_variable_defined?(:@new_record)
        # ActiveRecord 3.0.2 and 3.0.3 used @persisted instead of @new_record
        associated_record.instance_variable_set(:@persisted, true) if associated_record.instance_variable_defined?(:@persisted)
      end
    end
  end
end
