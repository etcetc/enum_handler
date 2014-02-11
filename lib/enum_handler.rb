require_relative './enum_handler/active_record_ext'
require_relative './enum_handler/base'
module EnumHandler
  
  def self.included(base)
    Base::define_state_variables(base)
    base.extend Base::ClassMethods
    base.send(:include, Base::InstanceMethods)
    unless base.ancestors.include?(ActiveRecord::Base)
      puts "Mimicking the attribute accessors for class #{base.to_s}"
      base.send(:include, MockActiveRecordMethods)
    end
  
  end
  
end
