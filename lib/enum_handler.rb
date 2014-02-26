require_relative './enum_handler/active_record_ext'
require_relative './enum_handler/base'
require_relative './enum_handler/mock_active_record'

module EnumHandler
  
  def self.included(base)
    base.send(:cattr_accessor, :eh_params) unless base.respond_to?(:eh_params)
    # Base::define_state_variable(base)
    base.extend Base::ClassMethods
    base.send(:include, Base::InstanceMethods)
    unless base.ancestors.include?(ActiveRecord::Base)
      puts "Mimicking the attribute accessors for class #{base.to_s}"
      base.send(:include, MockActiveRecordMethods)
    end
  
  end
  
end
