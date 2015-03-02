module ActiveRecord
  module Sanitization

    require 'active_support/concern'

    module ClassMethods

      protected

      # This does seem to work with Rails 3.2
      unless method_defined?(:replace_bind_variables_with_enum_extensions)
        def replace_bind_variables_with_enum_extensions(statement,values)
          if self.respond_to?(:has_enums?) && self.has_enums?
            segments = statement.split(/\(\s*\?\s*\)/).map { |r| r.split('?')}.flatten
            # logger.tmp_debug("segments = #{segments.inspect}")
            new_values = []
            rebuilt_segments = []
            values.each_with_index  { |v,i|
              # If this is some kind of collection, we need to process each of its entries
              segment = segments.shift.strip
              portion = segment.split(/\b(and|or)\b/i).last.strip
              equality_operand = portion.match(/(<>|!=|=)$/) and $1
              translated_value = v
              if column_name = (m=portion.strip.match(/^\(*\s*(\S+\.)?(\S+)\b/i)) ? m[2].gsub('`','').to_sym : nil and enum_defined_for?(column_name)
                includes_table_name =true if m[1]
                if ( v.is_a?(Array) )
                  translated_value = v.map{ |vi| vi.is_a?(Symbol) ? self.db_code(column_name,vi,true) : vi}.flatten.uniq
                elsif v.is_a?(Symbol)
                  # puts "translating #{v.inspect} to self.db_code(column_name.to_sym,v,true) }"
                  if v.to_s.index('!') == 0
                    # puts "reversing sense on ENTRY v=#{v.inspect}, segment = #{segment.inspect}"
                    segment.sub!(/(<>|!=)$/,'=') || segment.sub!(/\=$/,'<>') || segment.sub!(/NOT IN$/i,'IN') || segment.sub!(/IN$/,'NOT IN')
                    v = v.to_s[1..-1].intern
                    # puts "reversing sense on EXIT v=#{v.inspect}, segment = #{segment.inspect}"
                  end
                  translated_value = self.db_code(column_name.to_sym,v,true)
                end
                includes_table_name or segment.sub!(/\b#{column_name}\b/,"#{table_name}.#{column_name}")
                # puts("segment = #{segment.inspect}, column_name = #{column_name.inspect}, v=#{v.inspect} => #{translated_value.inspect}")
                segment.sub!(/(<>|!=)\s*$/,"NOT IN ") or segment.sub!(/(=)\s*$/,"IN ") if equality_operand && translated_value.is_a?(Array)
              end
              new_values << translated_value
              rebuilt_segments << segment + (segment.match(/IN\s*$/i) ? ' (?)' : ' ?')
            }
            rebuilt_segments += segments
            rebuilt_statement = rebuilt_segments*' '
            # puts "rebuilt statement = #{rebuilt_statement.inspect}, new_values = #{new_values.inspect}"
            # We need to substitute for the % sign b/c it causes problems
            rebuilt_statement.gsub!(/([^%])%([^%])/,'\1%%\2')
          else
            new_values = values
            rebuilt_statement = statement
          end
          replace_bind_variables_without_enum_extensions(rebuilt_statement,new_values)
        end
        alias_method_chain :replace_bind_variables, :enum_extensions
      end

      # This is for an update command, where we're setting the value
      unless method_defined?(:sanitize_sql_hash_for_assignment_with_enum_extensions)
        def sanitize_sql_hash_for_assignment_with_enum_extensions(attrs)
          if self.respond_to?(:has_enums?) && self.has_enums?
            attrs = attrs.inject({}) { |r,(attr,value)|
              r.merge( attr => enum_defined_for?(attr) && Symbol === value ? db_code(attr,value,false) : value)
            }
          end
          sanitize_sql_hash_for_assignment_without_enum_extensions(attrs)
        end
        alias_method_chain :sanitize_sql_hash_for_assignment, :enum_extensions
      end

      # EnumHandler fails for joins:
      #   find(:all,:joins => :users, :conditions => {:users => {:status => :active}})
      # fails unless I can modify this sanitize_sql_hash_for_conditions method
      # Unfortunately, to do it I have to get the class name from the table_name, which is a bit iffy
      unless method_defined?(:sanitize_sql_hash_for_conditions_with_enum_extensions)
        def sanitize_sql_hash_for_conditions_with_enum_extensions(attrs, table_name=quoted_table_name)
          def unquote(table_name)
            if m = table_name.match(/^['"`]/) and table_name.match(/#{m[0]}$/)
              table_name[1...-1]
            else
              table_name
            end
          end
          # If for some reason we can't find the appropriate class from the table name
          # Just pass the existing attributes, don't throw up
          begin
            myKlass = unquote(table_name).classify.constantize
            if myKlass.respond_to?(:has_enums?) && myKlass.has_enums?
              attrs = attrs.inject({}) { |r,(attr,value)|
                r.merge( attr => myKlass.enum_defined_for?(attr) && (Symbol === value || Array === value) ? myKlass.db_code(attr,value,true) : value)
              }
            end
          rescue
          end
          sanitize_sql_hash_for_conditions_without_enum_extensions(attrs,table_name)
        end
      end
      alias_method_chain :sanitize_sql_hash_for_conditions, :enum_extensions

      unless method_defined?(:attribute_condition_with_enum_extensions)
        def attribute_condition_with_enum_extensions(quoted_column_name,argument)
          if Symbol === argument
            argument = db_code(quoted_column_name.gsub(/\b`(\w+)`\b/,'\1'))
          end
          attribute_condition_without_enum_extensions(quoted_column_name, argument)
        end
        # alias_method_chain :attribute_condition, :enum_extensions
      end

    end
  end

  module QueryMethods
    extend ActiveSupport::Concern

    private

    # This is for getting the where clause to work for Rails 3
    # Note that there is a problem w/ the way relation delegates to the enclosing class (i.e. the ActiveRecord subclass)
    # in that it builds the method via method_missing and then delegates to the AR subclass.
    # However, when it hits an AR subclasses that does not support has_enums?, it still thinks it
    # can delegate to it, but in fact it can't and we get the has_enums? error
    # Quick fix is to include enum_handler in every class even if it isn't used
    def build_where_with_enum_extensions(opts, other = [])
      if Hash === opts
        begin
          if self.respond_to?(:has_enums?) && self.has_enums?
            opts = opts.inject({}) { |r,(attr,value)|
              r.merge( attr => enum_defined_for?(attr) && Symbol === value ? db_code(attr,value,true) : value)
            }
          end
        rescue
          puts "WARN: has_enums? called but not defined for #{self.klass.name}"
        end
      end
      @arel = nil # Prevent: DEPRECATION WARNING: Modifying already cached Relation. The cache will be reset. Use a cloned Relation to prevent this warning
      build_where_without_enum_extensions(opts,other)
    end
    alias_method_chain :build_where, :enum_extensions

  end

end

