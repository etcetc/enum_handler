# Supports the read_attribute and write_attribute methods for classes that don't have
# them so we can use common code
module EnumHandler
  module MockActiveRecordMethods
    def read_attribute(attribute)
      eval "@#{attribute}"
    end

    def write_attribute(attribute,value)
      eval "@#{attribute} = #{value.inspect}"
    end
  end
end