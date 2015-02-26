# This helps manage an enum for an active record class.
# The assumption is that the actual values are stored as integers or strings in the DB, but you want to use symbols in the rest of
# the code. For example, if you have a status field, you might want to store the values as 0 for pending, 1 for active, and 2 for 
# terminated, but you want to reference them as :active, :terminated, etc.
# This over-rides the default accessors by having them interact with symbols, while it saves the value as an integer under the covers
# WARNING - This has an unfortunate side-effect:
#   - inspect will show the underlying values as stored in the DB

# You can use this module two ways.  
# In the more common case, you simply want 'enum'-ify an attribute in the existing activeRecord, you simply indicate:
#     define_enum :attribute, values_hash (symbol_name => integer_id), options
#     e.g. define_enum :status, { :active => 0, :suspended => 1, :terminated => -1}
# or 
#     define_enum :attribute, symbol_values_array
#     e.g. define_enum :kind, [:normal, :test, :admin]
#
# In the first case, the values are saved as integers (the integer constraint is not enforced by the system - it's just common)
# In the second case, the symbol values are stored as strings (as if the to_s had been used on the symbol)
# 
# This takes a few options:
#    :sets => { set_symbol  => [:value1,:value2]}
#    sets let you aggregate a bunch of values together and reference them.  
#    :primary => true
#    setting an enum to primary affects the naming of the convenience methods used for finders and queries
# 
# If we are to generate methods, the finders and counters are created with the syntax shown in the example below:
# class User
#  define_enum, :status => { :active => 0, :terminated => 1}
# end
# 
# scope :status_active, { :conditions => { :status => :active} }
# scope :status_not_active, {:conditions => ["status <> ?",:active]}
# 
# So then the statement
#    User.status_active
# would return all the users with status set to active (0 in the DB)
#
# However, if the :primary option is set to true, then the prefix is taken out of the named scope, and we just have:
# scope, :active, { :conditions => { :status => :active} }
# scope, :not_active, :{:conditions => ["status <> ?",:active]
# 
# Now you can use the more readable
#    User.active
# to get all the users with status active
#
# In a less common scenario, you want to enum-ify values that are actually saved by a different class.  The common example is that
# of preferences.  Suppose you have a single class that saves the preferences for other classes or instances in a polymorphic way.
# Each client (the object that wants to have its preferences saved) wants to use its own namespace regarding the attributes and the 
# symbols that each can map to.  
# EnumHandler supports this case in the following way:
# In the Preference class, you specify
# 
#  supports_polymorphic_enum_handling(attribute_name), where the attribute name is the name of the polymorphic attribute
#
# If the class saves attributes :name, and :value, then :value would be what we call the polymorphic attribute
# 
# The client model (that wants to save personalized preferences in the Preference object) then indicates:
#
#   Preference.define_enum :attribute_name, values, :context => context
#
# where the context is simply the name of the calling (client) class (or self)
# 
# Now, when the choices are retrieved, underlying attribute names are interpreted
# within the context of the client class.
# 
# This module creates a number of class and instance methods in the base "including" class
# Class Methods
#   <attribute_name>_choices: returns the attributes as an array of a simple class, each of has only two attributes: id (code) and value(symbolic value)
#   db_code(attribute_name,value): is the same as db_<attribute_name>_code
#
# Instances methods
#   attribute: the attribute method is overwritten so that it returns the value
#   attribute=(value): This method can take a value as a FixNum code value, a symbol, or the corresponding string, and stores the value as a
#                      integer code underneath.  Note that the setter is quite permissive - values such as "Big Dog", "big_dog", "Big dog",
#                      etc. are all treated the same and become :big_dog. 
#   is_<attribute>_<value>?: For non-primary enums, this generates a method that allows checking if attribute is set to indicated value
#   is_<value>?: For primary enums, this generates a method that allows checking if attribute is set to indicated value
# How it works:
#   This actually creates several variables in the including class

require 'active_record'
module EnumHandler
  class SimpleObj
    attr_reader :id, :name
  end

  module Base

    def self.define_state_variable(base)
      # eh_params has the following keys
      # :has_enums: Set to true if an enum is actually defined  with this class
      # :db_codes: codes that map from the attribute value to the code stored in the DB
      # :enum_set_mappings: This contains the mappings from a set to other symbols
      # :enum_contexts: maps out the contexts for various attributes
      # :use_polymorphic_context: boolean that defines if we should be considering the polymorphic context here (e.g. using enums for)
      # :polymorphic_attribute: The name of the polymorphic attribute for the class that supports polymorphic contexts (e.g. Preferences)
      # :attribute_options: Options associated with the attribute - for example, we specify :strict if we don't want additional enums values supported
      # :keyed_attribute: the attribute name ....
    end

    module ClassMethods

      #  The main method called by the class to define an enum for an attribute
      #    define_enum :cook_style, { :broiled  => 1, :braised => 2, :poached => 3},
      #  but one could also call it as 
      #    define_enum :cook_style, [:broiled, :braised, :poached]
      #  if the item is saved as a string 
      def define_enum( attribute, values_hash, options = {})
        self.eh_params ||= {}
        self.eh_params[:has_enums] = true
        self.eh_params[:enum_contexts] ||= {}
        if ( context = options[:context] )
          self.eh_params[:use_polymorphic_context] = true
        else
          context = nil
        end
        context = context.to_s
        self.eh_params[:enum_contexts][attribute.to_s] = context

        # If values_hash is an array, we just map it to itself in a hash
        values_hash = normalize_values_to_hash(values_hash)

        self.eh_params[:db_codes] ||= {}
        self.eh_params[:db_codes][context] ? self.eh_params[:db_codes][context].merge!( attribute.to_s => values_hash) :  self.eh_params[:db_codes].merge!( {context => { attribute.to_s => values_hash}})

        # Save the mapping sets
        self.eh_params[:enum_set_mappings] ||= {}
        if (sets = options[:sets])
          illegals = sets.values.flatten - values_hash.keys - sets.keys
          unless illegals.empty?
            raise "set values #{illegals.inspect} are not part of the defined enums"
          end
          if self.eh_params[:enum_set_mappings][context]
            self.eh_params[:enum_set_mappings][context].merge!( {attribute.to_s => sets} )
          else
            self.eh_params[:enum_set_mappings].merge!( {context => {attribute.to_s => sets}} )
          end
        end

        self.eh_params[:attribute_options] ||= {}
        self.eh_params[:attribute_options][attribute.to_s] = {}

        # We can specify that the enum is strict and not a set of predefined values.  If so, then 
        # any attempt to set the value to anything other than one of the enum values will generate an
        # error.  If not specified, the symantics are strict, but it can be set to false to override the
        # validation
        self.eh_params[:attribute_options][attribute.to_s][:strict] = options.has_key?(:strict) ? options[:strict] : (self.eh_params[:attribute_options][attribute.to_s][:strict].nil? ? true : nil)

        # If a nil options is specified, then if we see that the attribute value is nil, then we substitute this
        self.eh_params[:attribute_options][attribute.to_s][:nil] = options[:nil]

        # ==========================
        # = The underlying methods =
        # ==========================
        # Return the coded value for the indicated symbol or string value for a given attribute
        # Note that if the attribute is a keyed attribute (that is, its value depends upon the value set in another element), 
        # we call the keyed_db_ methods instead


        # the following are done in a class eval because we are creating methods that use the attribute name
        class_eval <<-END, __FILE__, __LINE__
        def self.validate_#{attribute.to_s}_value(symbol_value,eval_context='')
          eval_context = eval_context.blank? ? '' : eval_context
          if ( self.eh_params[:db_codes][eval_context].blank? )
            raise "Looks like the enum translation context for "+eval_context+" has not yet been defined"
          end
          if symbol_value.is_a?(Symbol)
            raise("Illegal #{attribute} value specified (" + symbol_value.to_s + ") - valid values are " + self.eh_params[:db_codes][eval_context]['#{attribute}'].keys.join(',')) unless self.eh_params[:db_codes][eval_context]['#{attribute}'] && self.eh_params[:db_codes][eval_context]['#{attribute}'].has_key?(symbol_value.to_sym)
          else 
            raise("Illegal #{attribute} value specified (" + symbol_value.to_s + ") - valid values are " + self.eh_params[:db_codes][eval_context]['#{attribute}'].values.join(',')) unless self.eh_params[:db_codes][eval_context]['#{attribute}'] && self.eh_params[:db_codes][eval_context]['#{attribute}'].has_value?(symbol_value)
          end
        end
        
        # Used to see if the enum matches a give value for an attribute.  This is useful in that you don't have to
        # care if the value is a set value or a fixed enum value. 
        # The attribute and match_value should be symbols - the value can be the symbol or the underlying value mapping 
        # to the symbol
        def self.enum_matches?(attribute,value,match_value)
          v =  Symbol === value ? value : db_value(attribute,value)
          Array(enum_values(attribute,match_value)).include?(v)
        end
        
        END

        # ============================
        # = Enum'ed attribute values =
        # ============================
        class_eval <<-END, __FILE__, __LINE__
        class << self
        
          # Returns an array of possible enum values
          # options:
          #  :include_sets => true: also add the sets as independent entries
          #  :set => set_symbol(s): returns only the choices for the indicated sets. 
          def choices_list(attribute,options={})
            if options[:set]
              r= Array(options[:set]).map { |set| self.eh_params[:enum_set_mappings]['#{context}'][attribute.to_s][set] }.flatten.uniq
            else
              r = self.eh_params[:db_codes]['#{context}'][attribute.to_s].keys
              r += self.eh_params[:enum_set_mappings]['#{context}'][attribute.to_s].keys if options[:include_sets]
              r = r.sort_by{ |s| s.to_s }
            end
            r = r.map{ |v| humanize(v) } if options[:humanize]
            r          
          end

          # This is mainly useful for handling sets - it expands the set values
          def enum_values(attribute,value_or_options,options={})
            value = value_or_options.is_a?(Hash) ? nil : value_or_options
            if value
              if self.eh_params[:db_codes]['#{context}'][attribute.to_s][value] 
                r = value
                r = humanize(r) if options[:humanize]
              elsif r = self.eh_params[:enum_set_mappings]['#{context}'][attribute.to_s][value].map { |value| 
                enum_values(attribute,value,options)
                }.flatten
              end
            else
              # TBD: If no value is provided, just return the complete list
            end
            r
          end
        end
        END

        # Define methods to get the various enum values the attribute can take
        # Do not to use these, instead use the choices_list option above
        # These will be DEPRECATED
        define_singleton_method("#{attribute}_choices") do |options={}|
          choices_list(attribute,options).keys
          # self.eh_params[:db_codes]['#{context}']['#{attribute}'].collect { |name,id| EnumHandler::SimpleObj.new(id,name) }.sort { |a,b| a.id <=> b.id }
        end

        # Return the choices as a list, suitable for presentation,for example
        puts "Defining #{attribute}_choices_list"
        define_singleton_method("#{attribute}_choices_list".to_sym) do |options={}|
          choices_list(attribute,options)
        end    

        self.singleton_class.send(:alias_method, attribute.to_s.pluralize.to_sym, "#{attribute}_choices_list".to_sym)


        # Define the accessors for the attribute, e.g. for attribute 'status', define
        # instance.status and instance.status=
        module_eval(<<-END, __FILE__, __LINE__
        define_method(attribute) {
          eval_context = eh_evaluation_context

          v = eval %{ self.eh_params[:db_codes][eval_context]['#{attribute}'].key(read_attribute(attribute.to_sym)) }
          if !v && !self.eh_params[:attribute_options]['#{attribute}'][:strict]
            v = read_attribute(attribute.to_sym)
          end
          if v.nil? then v = self.eh_params[:attribute_options]['#{attribute}'][:nil]; end
          v
        }

        define_method(attribute.to_s+'=') { |value| 
          if value.blank? 
            eval "write_attribute(attribute.to_sym,nil)"           
          elsif value.is_a?(Fixnum) 
            eval_context = eh_evaluation_context
            self.class.validate_#{attribute}_value(value,eval_context) if self.eh_params[:attribute_options]['#{attribute}'][:strict]
            eval "write_attribute(attribute.to_sym,value)" 
          else
            eval_context = eh_evaluation_context
            value_sym =  (value.is_a? String) ? value.gsub(/\s/,'_').downcase.to_sym  : value
            v = if self.eh_params[:attribute_options]['#{attribute}'][:strict]
              self.class.validate_#{attribute}_value(value_sym,eval_context) 
              self.eh_params[:db_codes][eval_context]['#{attribute}'][value_sym]
            else
              self.eh_params[:db_codes][eval_context]['#{attribute}'][value_sym] || value
            end
            eval " write_attribute(attribute.to_sym,v) "
          end
        }
        END
        )

        # =======================
        # = Define test methods =
        # =======================
        # For example, for status we can have
        #   is_active? or
        #   is_status_active?  
        # depending upon whether status is defined as :primary or not
        # We also define them for the sets
        values_hash.keys.each do |v|
          # If this is a primary attribute (such as status) we simply create the method as is_active? rather than is_status_active?
          # Note that multiple attributes can be primary, but then the user needs to make sure there is no collision between the attributes
          if options[:primary]
            define_method("is_#{v}?") { eval " #{attribute} == '#{v}'.to_sym "}
          else
            define_method("is_#{attribute}_#{v}?") { eval " #{attribute} == '#{v}'.to_sym "}
          end
          define_method("set_#{attribute}_to_#{v}") { eval " self.#{attribute} = '#{v}'.to_sym "}
          define_method("set_#{attribute}!") { eval "update_attribute(#{attribute},'#{v}'.to_sym) " }
        end

        if (sets = options[:sets])
          sets.each { |k,v| 
            # define_method(options[:primary] ? "is_#{k}?" : "is_#{attribute}_#{k}?" ) { eval "#{v.inspect}.include?(#{attribute}) " }
            define_method(options[:primary] ? "is_#{k}?" : "is_#{attribute}_#{k}?" ) { self.class.enum_values(attribute,k).include?(send(attribute))  }
          }
        end
      
        # ================================================
        # = Define class-level scopes =
        # ================================================
        # Scopes allow us to define common, readable things like
        #   Myclass.active
        # which returns all the items with status active, assuming status is tagged :primary options, or if not
        #   Myclass.status_active
        # We also support the negation, such as
        #   Myclass.not_active
        # and
        #   Myclass.status_not_active

        if ActiveRecord::Base.respond_to?(:scope)
          (values_hash.keys + (options[:sets] ? options[:sets].keys : [])).each do |v|
            if options[:primary]
              class_eval do
                scope v.to_sym, lambda { where(attribute => db_code(attribute,v,true)) }
                scope "not_#{v}".to_sym, lambda {  where(["#{attribute} <> ?",db_code(attribute,v,true)]) }
              end
            else
              class_eval do
                scope "#{attribute}_#{v}".to_sym, lambda { where("#{attribute}".to_sym => db_code("#{attribute}",v,true)) }
                scope "#{attribute}_not_#{v}".to_sym, lambda { where(["#{attribute} <> ?",db_code("#{attribute}",v,true)]) }
              end
            end
          end
        end

      end

      # When a class calls this, it means that other callers can call define_enum on it
      def supports_polymorphic_enum_handling(attribute_name)
        self.eh_params[:polymorphic_attribute] = "#{attribute_name}_type".to_sym
      end

      # Does this class have enums defined for it?
      def has_enums?
        !!eh_params[:has_enums]
      end

      # Does this class have an enum defined for the the indicated attribute?
      def enum_defined_for?(attribute)
        context = self.eh_params[:enum_contexts][attribute.to_s]
        !!(eh_params[:db_codes][context] && eh_params[:db_codes][context][attribute.to_s])
        # Returns true if the indicated attribute has an enum defined
      end
    
      # Given the attribute value (as represented by the attribute), what is the code
      # stored in the database?
      def db_code(attribute,value,include_sets=true)
        if ( value.is_a?(Array) )
          value.map { |v| db_code(attribute,v,include_sets)}.flatten.uniq
        else
          context = self.eh_params[:enum_contexts][attribute.to_s]
          if context && self.eh_params[:db_codes][context].has_key?(attribute.to_s) 
            v = self.eh_params[:db_codes][context][attribute.to_s][dehumanize(value)]
            if v.nil?
              if include_sets and self.eh_params[:enum_set_mappings][context] and self.eh_params[:enum_set_mappings][context][attribute.to_s] and values=self.eh_params[:enum_set_mappings][context][attribute.to_s][value.to_sym]
                db_code(attribute,values,true)
              else 
                raise("Illegal " +  attribute.to_s + " value specified (" + value.inspect + ") - valid values are " + self.eh_params[:db_codes][context][attribute.to_s].keys.inspect)
              end
            else
              v
            end
          else 
            value  
          end
        end
      end

      # Given the code stored in the DB, what is the value that should be set in the attribute?
      def db_value(attribute,code)
        context = self.eh_params[:enum_contexts][attribute.to_s]
        self.eh_params[:db_codes][context][attribute.to_s].key(code)
      end

      # ===============
      # = Keyed enums =
      # ===============

      # This is slightly more complex code to support a more flexible model for storing enums in things like preferences
      # The class that uses this defines an attribute whose values should be interpreted depending upon the value of a key
      # the key_values_hash maps the key_attribute value to the interpretation of the attribute values
      # The keys in the attribute hash may be scalars or arrays.  The value in the values_hash is 
      # a hash that maps the symbol to the integer value, or a simple array (in which case the values are persisted as strings)
      # Example:
      #  define_key_attribute(:cooking_method, :food_type, {['fowl','beef'] => { :braised => 1, :roasted => 2, :grilled => 3}, 'egg' => { :poached => 1, :fried => 2, :scrambled => 3}})
      #  Assumes we have a food_type attribute, and depending upon its value, we can have different cooking methods
      # To establish a default value, establish the hash with a default, or else support a nil key value(?)
      # Note that the key attribute value has to be established before trying to get to the value of the attribute
      # WARNING: All key attribute values are stored as symbols - even when they are given as strings!!! (not sure why)
      # However, the key values are stored as strings (don't remember why)

      def define_keyed_enum(attribute, key_attribute, key_values_hash,options={} )
        raise "Only one key attribute currently allowed - it has already been set to #{self.eh_params[:key_attribute]}"  if self.eh_params[:key_attribute] && key_attribute != self.eh_params[:key_attribute]
        self.eh_params[:key_attribute] = key_attribute;
        # Expand the values hash so that we keep track of each individual key independently
        # Note that the value can be 
        key_values_hash.each { |key_attribute_value,values| 
          if ( key_attribute_value.is_a? Array )
            values_hash = normalize_values_to_hash(values)
            key_attribute_value.each { |k| key_values_hash[k.to_s] = values_hash}
            key_values_hash.delete(key_attribute_value)
          else
            key_values_hash[key_attribute_value.to_s] = normalize_values_to_hash(values)
          end
        }      
        self.eh_params[:keyed_db_codes] ||= {}
        self.eh_params[:keyed_db_codes][attribute.to_s] ||= {}
        self.eh_params[:keyed_db_codes][attribute.to_s].merge!(key_values_hash)
        self.eh_params[:attribute_options] = {}
        self.eh_params[:attribute_options][attribute.to_s] = {}
        self.eh_params[:attribute_options][attribute.to_s][:strict] = options.has_key?(:strict) ? options[:strict] : true

        # Define the various choices 
        class_eval(<<-END, __FILE__, __LINE__
        class #{attribute.to_s.camelize}
          attr_accessor :id,:name
          def initialize(id,name)
            self.name = name;
            self.id = id;
          end          
        end

        def self.#{attribute}_choices_for_key(key)
          self.eh_params[:keyed_db_codes]['#{attribute}'][key.to_s].collect { |name,id| #{attribute.to_s.camelize}.new(id,name) }.sort { |a,b| a.id <=> b.id }
        end

        def self.#{attribute}_choices_list_for_key(key,options={})
          key = key.to_s
          r = self.eh_params[:keyed_db_codes]['#{attribute}'][key].keys
          r = r.map{ |v| humanize(v) } if options[:humanize]
          r
        end

        END
        )

        # puts "In #{self}: Creating db code #{attribute} for context #{context}: #{self.eh_params[:keyed_db_codes].object_id}: #{self.eh_params[:keyed_db_codes].inspect}"
        # Note that below, the key represents the value of the key, and the symbol_represents the symbol that we're trying
        # to set the attribute to
        class_eval(<<-END,__FILE__, __LINE__
        def self.validate_keyed_#{attribute.to_s}_value(key,symbol_value)
          # If this key is not keyed, return false indicating that the key is not validated
          key = key.to_s
          return false unless self.eh_params[:keyed_db_codes]['#{attribute}'].has_key?(key)
          raise("Illegal #{attribute} key specified (" + key + ") - valid keys are " + self.eh_params[:keyed_db_codes]['#{attribute}'].keys.join(',')) unless self.eh_params[:keyed_db_codes]['#{attribute}'].has_key?(key)
          raise("Illegal #{attribute} value specified (" + symbol_value.to_s + ") - valid values are " + self.eh_params[:keyed_db_codes]['#{attribute}'][key].keys.join(',')) unless self.eh_params[:keyed_db_codes]['#{attribute}'][key] && self.eh_params[:keyed_db_codes]['#{attribute}'][key].has_key?(symbol_value.to_sym)
          true
        end
        # private_class_method :validate_#{attribute.to_s}_value

        def self.db_#{attribute}_code(symbol_value,key)
          key = key.to_s
          validate_keyed_#{attribute}_value(key,symbol_value.to_sym) ? self.eh_params[:keyed_db_codes]['#{attribute}'][key][symbol_value.to_sym] : symbol_value
        end

        def self.db_#{attribute}_value(code,key)
          key = key.to_s
          self.eh_params[:keyed_db_codes]['#{attribute}'][key].key(code)
        end

        END
        )

        module_eval(<<-END, __FILE__, __LINE__
        define_method(attribute) {
          eval %{ self.eh_params[:keyed_db_codes]['#{attribute}'][read_attribute(self.eh_params[:key_attribute])] ? self.eh_params[:keyed_db_codes]['#{attribute}'][read_attribute(self.eh_params[:key_attribute])].key(read_attribute(attribute.to_sym)) : read_attribute(attribute) }  
        }

        define_method(attribute.to_s+'=') { |value| 
          if value.blank? 
            eval "write_attribute(attribute.to_sym,nil)"           
          elsif value.is_a?(Fixnum) 
            eval "write_attribute(attribute.to_sym,value)" 
          else
            key=read_attribute(key_attribute)
            keyed = self.class.validate_keyed_#{attribute}_value(key,value) 
            eval " write_attribute(attribute.to_sym,keyed ? (self.eh_params[:keyed_db_codes]['#{attribute}'][key.to_s][value.to_sym] || (!self.eh_params[:attribute_options][attribute.to_s][:strict] && value)): value )";
          end
        }

        END
        )
        key_values_hash.keys.each do |v|
          define_method("is_#{attribute}_#{v}?") { eval " #{attribute} == '#{v}'.to_sym "}
          define_method("set_#{attribute}_to_#{v}") { eval " self.#{attribute} = '#{v}'.to_sym "}
        end

        def self.keyed_db_code(attribute,value,key)
          key = key.to_s
          self.eh_params[:keyed_db_codes][attribute.to_s][key.to_s][value]
        end

      end
      private :define_keyed_enum

      # Convert the values to a hash if it's just an array.  
      # Note that in this case, we convert the underscores to a space (don't remember why - presumably so it's easier to read?)
      def normalize_values_to_hash(values)
        values.is_a?(Array) ? Hash[values.zip(values.map{ |v| v.to_s.gsub('_',' ') })]  : values
      end
      private :normalize_values_to_hash


      def humanize(value)
        value.to_s.humanize
      end


      # If we want to dehumanize a value we have received
      # This is the opposite of the humanization that we do
      # Assume we return a string or value
      def dehumanize(v)
        v.is_a?(String) ? v.gsub(/\s/,'_').downcase.to_sym : v
      end

    end
    
    module InstanceMethods
      def eh_evaluation_context
        if ( self.class.eh_params[:use_polymorphic_context] )
          context = read_attribute(self.eh_params[:polymorphic_attribute])
          raise("Value for polymorphic parameter " + self.class.eh_params[:polymorphic_attribute].to_s + " has not been set yet")  if ( context.blank? )
        else
          # context = self.class.to_s
          context = ''
        end
        context
      end
      private :eh_evaluation_context
    end
    
  end
end